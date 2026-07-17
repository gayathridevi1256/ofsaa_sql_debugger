"""
pipeline.py — Orchestrates the 6-step OFSAA diagnostic pipeline.

WHAT THIS FILE DOES:
    Runs all 6 pipeline steps in order, tracks progress in the database,
    and streams live updates to the UI via a queue.

    Steps:
        1. log_reader     — reads OFSAA log, extracts metadata + SQL
        2. set_batch_date — SSHs into OFSAA server, sets business date
        3. sql_executer   — runs the full scenario SQL, checks for alerts
        4. cte_parser     — splits SQL into individual CTEs
        5. cte_executer   — runs each CTE, finds the empty one
        6. sql_diagnostics— diagnoses the empty CTE, finds root cause

LAYMAN'S EXPLANATION:
    Think of this file as a "project manager" that:
        - Assigns each task (pipeline step) to the right worker (script)
        - Tracks progress (updates the database after each step)
        - Reports back to the UI in real time (via the progress queue)
        - Handles failures gracefully (logs what went wrong and why)

HOW PROGRESS STREAMING WORKS:
    We use asyncio.Queue — a simple message box.
    As each step runs, it puts a message in the box.
    The WebSocket in main.py reads from the box and sends to the browser.
    The browser updates the UI live without refreshing.
"""

import os
import sys
import json
import asyncio
import logging
import traceback
from datetime import datetime, timezone
from pathlib import Path

from config import OUTPUTS_DIR, PIPELINE_DIR
from jobs import (
    update_job_status,
    update_step_status,
    audit
)

logger = logging.getLogger(__name__)

# Add pipeline directory to Python path so we can import pipeline scripts
sys.path.insert(0, str(PIPELINE_DIR))


# ----------------------------------------------------------------------
# PROGRESS MESSAGE HELPER
# ----------------------------------------------------------------------

async def _emit(queue: asyncio.Queue, event: str, data: dict):
    """
    Puts a progress message into the queue.
    The WebSocket in main.py reads this and sends it to the browser.

    LAYMAN: This is like the pipeline sending a text message to the UI
    saying "Step 2 started" or "Step 3 failed — here's why".

    Event types:
        step_started    — a step just began
        step_completed  — a step finished successfully
        step_failed     — a step failed with an error
        step_output     — a step produced some output text
        job_completed   — entire pipeline finished
        job_failed      — pipeline stopped due to fatal error
    """
    message = {
        "event":     event,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        **data
    }
    await queue.put(message)


# ----------------------------------------------------------------------
# MAIN PIPELINE RUNNER
# ----------------------------------------------------------------------

async def run_pipeline(
    job_id:       str,
    user_id:      int,
    username:     str,
    log_file_path: str,
    progress_queue: asyncio.Queue
):
    """
    Runs the full 6-step pipeline for a given log file.

    PARAMETERS:
        job_id          — unique ID for this run (UUID)
        user_id         — who triggered this run
        username        — their username (for audit logs)
        log_file_path   — full path to the uploaded OFSAA log file
        progress_queue  — asyncio Queue for streaming progress to UI

    Each step:
        1. Updates the job_steps table to "running"
        2. Runs the actual Python function
        3. Updates to "completed" or "failed"
        4. Emits a progress message to the queue
    """

    logger.info("Pipeline started — job_id=%s user=%s", job_id, username)

    # Mark job as running
    update_job_status(job_id, "running", current_step="log_reader")
    audit("pipeline_started", username=username, user_id=user_id, job_id=job_id)

    # Shared state passed between steps
    state = {
        "job_id":        job_id,
        "log_file_path": log_file_path,
        "metadata":      {},
        "output_dir":    None,
        "has_alerts":    False,
        "results":       [],
        "run_logger":    None,
    }

    # ------------------------------------------------------------------
    # STEP 1 — LOG READER
    # ------------------------------------------------------------------
    success = await _run_step(
        job_id         = job_id,
        step_name      = "log_reader",
        queue          = progress_queue,
        fn             = _step_log_reader,
        state          = state,
        next_step      = "set_batch_date"
    )
    if not success:
        await _fail_job(job_id, username, user_id, "log_reader failed", progress_queue)
        return

    # Create RunLogger now that we know output_dir and scenario_name
    from run_logger import RunLogger
    state["run_logger"] = RunLogger(
        output_dir     = state["output_dir"],
        job_id         = job_id,
        scenario_name  = state["metadata"].get("job_description", "UNKNOWN_SCENARIO"),
    )

    # ------------------------------------------------------------------
    # STEP 2 — SET BATCH DATE
    # ------------------------------------------------------------------
    success = await _run_step(
        job_id         = job_id,
        step_name      = "set_batch_date",
        queue          = progress_queue,
        fn             = _step_set_batch_date,
        state          = state,
        next_step      = "sql_executer"
    )
    if not success:
        await _fail_job(job_id, username, user_id, "set_batch_date failed", progress_queue)
        return

    # ------------------------------------------------------------------
    # ROUTE BASED ON SCENARIO TYPE
    # ------------------------------------------------------------------
    if state.get("multi_query"):
        # ── FUNCTION SCENARIO FLOW ──
        # Step 3: Execute resolved function SQL → check alerts → done
        success = await _run_step(
            job_id         = job_id,
            step_name      = "sql_executer",
            queue          = progress_queue,
            fn             = _step_execute_resolved_function,
            state          = state,
            next_step      = None
        )
        if not success:
            await _fail_job(job_id, username, user_id, "resolved function execution failed", progress_queue, state)
            return

        has_alerts = state.get("has_alerts", False)
        if has_alerts:
            update_job_status(job_id, "completed", alerts_generated=1,
                              root_cause="Function executed — alerts generated")
            await _emit(progress_queue, "job_completed", {
                "job_id": job_id, "alerts_generated": True,
                "root_cause": "Function executed — alerts generated"
            })
            audit("pipeline_completed", username=username, user_id=user_id, job_id=job_id,
                  detail="Function executed — alerts generated")

            # Close the run logger
            run_logger = state.get("run_logger")
            if run_logger:
                run_logger.close()

            return
        # else: no alerts → fall through to standard Steps 4-6

        # Skip standard Step 3 (SQL Executer) for function scenarios
        # since the resolved function SQL already ran above.
        if not state.get("multi_query"):
            # STEP 3 — SQL EXECUTER
            success = await _run_step(
                job_id         = job_id,
                step_name      = "sql_executer",
                queue          = progress_queue,
                fn             = _step_sql_executer,
                state          = state,
                next_step      = "cte_parser"
            )
            if not success:
                await _fail_job(job_id, username, user_id, "sql_executer failed", progress_queue, state)
                return

            # If alerts were found — pipeline is done
            if state.get("has_alerts"):
                update_job_status(
                    job_id,
                    "completed",
                    alerts_generated = 1,
                    root_cause       = "Alerts generated successfully — no diagnosis needed"
                )
                await _emit(progress_queue, "job_completed", {
                    "job_id":          job_id,
                    "alerts_generated": True,
                    "root_cause":      "Alerts generated successfully"
                })
                audit("pipeline_completed", username=username, user_id=user_id, job_id=job_id,
                      detail="Alerts generated")

                # Close the run logger
                run_logger = state.get("run_logger")
                if run_logger:
                    run_logger.close()

                return

        # STEP 4 — CTE PARSER (for both function and non-function scenarios)
        success = await _run_step(
            job_id         = job_id,
            step_name      = "cte_parser",
            queue          = progress_queue,
            fn             = _step_cte_parser,
            state          = state,
            next_step      = "cte_executer"
        )
        if not success:
            await _fail_job(job_id, username, user_id, "cte_parser failed", progress_queue, state)
            return

        # STEP 5 — CTE EXECUTER
        success = await _run_step(
            job_id         = job_id,
            step_name      = "cte_executer",
            queue          = progress_queue,
            fn             = _step_cte_executer,
            state          = state,
            next_step      = "sql_diagnostics"
        )
        if not success:
            await _fail_job(job_id, username, user_id, "cte_executer failed", progress_queue, state)
            return

        # STEP 6 — SQL DIAGNOSTICS
        success = await _run_step(
            job_id         = job_id,
            step_name      = "sql_diagnostics",
            queue          = progress_queue,
            fn             = _step_sql_diagnostics,
            state          = state,
            next_step      = None
        )
        if not success:
            await _fail_job(job_id, username, user_id, "sql_diagnostics failed", progress_queue, state)
            return

        # ALL STANDARD STEPS COMPLETE
        root_cause       = state.get("root_cause", "Unknown")
        results_json     = json.dumps(state.get("results", []))
        cte_results_json = json.dumps(state.get("cte_results", []))

        update_job_status(
            job_id,
            "completed",
            alerts_generated = 0,
            root_cause       = root_cause,
            result_json      = results_json,
            cte_results_json = cte_results_json
        )

        await _emit(progress_queue, "job_completed", {
            "job_id":           job_id,
            "alerts_generated": False,
            "root_cause":       root_cause,
            "results":          state.get("results", []),
            "cte_results":      state.get("cte_results", [])
    })

    audit(
        "pipeline_completed",
        username  = username,
        user_id   = user_id,
        job_id    = job_id,
        detail    = f"No alerts — root cause: {root_cause}"
    )

    # Close the run logger
    run_logger = state.get("run_logger")
    if run_logger:
        run_logger.close()

    logger.info("Pipeline completed — job_id=%s", job_id)


# ----------------------------------------------------------------------
# GENERIC STEP RUNNER
# ----------------------------------------------------------------------

async def _run_step(
    job_id:    str,
    step_name: str,
    queue:     asyncio.Queue,
    fn,
    state:     dict,
    next_step: str
) -> bool:
    """
    Runs a single pipeline step function.
    Handles DB updates, progress emission, and error catching.

    Returns True on success, False on failure.

    LAYMAN: This is the "task runner" wrapper. Every step goes through
    this so we don't repeat the same try/except + DB update + progress
    emit code 6 times.
    """
    logger.info("Step starting: %s", step_name)

    # Mark step as running in DB + notify UI
    update_step_status(job_id, step_name, "running")
    update_job_status(job_id, "running", current_step=step_name)

    await _emit(queue, "step_started", {
        "job_id":    job_id,
        "step":      step_name,
        "message":   f"Starting {_step_label(step_name)}..."
    })

    try:
        # Run the actual step function
        # We use asyncio.to_thread because the pipeline scripts are
        # synchronous (blocking) Python — this runs them in a thread
        # so they don't freeze the async FastAPI server.
        #
        # LAYMAN: asyncio.to_thread is like saying "run this heavy task
        # in a separate worker so the server stays responsive"
        output = await asyncio.to_thread(fn, state)

        # Success
        update_step_status(job_id, step_name, "completed", output=output)
        if next_step:
            update_job_status(job_id, "running", current_step=next_step)

        await _emit(queue, "step_completed", {
            "job_id":  job_id,
            "step":    step_name,
            "message": f"{_step_label(step_name)} completed",
            "output":  output
        })

        logger.info("Step completed: %s", step_name)
        return True

    except Exception as e:
        error_msg = f"{type(e).__name__}: {str(e)}"
        tb        = traceback.format_exc()

        logger.error("Step failed: %s — %s", step_name, error_msg)

        update_step_status(job_id, step_name, "failed", error=error_msg)

        await _emit(queue, "step_failed", {
            "job_id":  job_id,
            "step":    step_name,
            "message": f"{_step_label(step_name)} failed",
            "error":   error_msg
        })

        return False


# ----------------------------------------------------------------------
# STEP FUNCTIONS
# Each function receives the shared `state` dict and returns
# a short output string describing what happened.
# They update `state` in place to pass data to the next step.
# ----------------------------------------------------------------------

def _step_log_reader(state: dict) -> str:
    """
    Step 1: Read OFSAA log file, extract metadata and SQL queries.
    """
    from log_reader import (
        _read_uploaded_text,
        _extract_log_metadata,
        _extract_all_queries_from_log,
        _save_queries_to_files,
        _save_metadata,
        _is_function_scenario
    )
    from path_manager import create_output_directory

    log_file_path = state["log_file_path"]

    # Read and decode log file
    log_text = _read_uploaded_text(log_file_path)

    # Extract metadata (scenario name, business date, threshold set ID)
    metadata = _extract_log_metadata(log_text)
    state["metadata"] = metadata

    # Detect flow type based on scenario ID
    multi_query = _is_function_scenario(metadata)
    state["multi_query"] = multi_query
    if multi_query:
        print("\n  Function scenario detected — using multi-query flow")
    else:
        print("\n  Standard scenario — using single-query flow")

    # Create output directory based on scenario name
    scenario_name = metadata.get("job_description", "UNKNOWN_SCENARIO")
    output_dir    = create_output_directory(scenario_name)
    state["output_dir"] = output_dir

    # Save metadata.json
    _save_metadata(metadata, output_dir)

    # Extract SQL queries from log
    queries = _extract_all_queries_from_log(log_text, multi_query=multi_query)

    if queries["count"] == 0:
        raise ValueError("No SQL queries found in log file")

    # Save SQL files (use separate connection for function extraction if needed)
    from db_connect import connect_to_oracle
    func_conn = None
    try:
        if multi_query:
            func_conn = connect_to_oracle()
        _save_queries_to_files(queries, metadata, db_conn=func_conn, multi_query=multi_query)
    finally:
        if func_conn:
            func_conn.close()

    # Update job in DB with scenario info
    from jobs import update_job_status
    update_job_status(
        state.get("job_id", ""),
        "running",
        scenario_name = scenario_name,
        batch_date    = str(metadata.get("current_business_date", "")),
        output_dir    = output_dir
    )

    return (
        f"Scenario: {scenario_name} | "
        f"Date: {metadata.get('current_business_date')} | "
        f"Queries extracted: {queries['count']}"
    )


def _step_execute_resolved_function(state: dict) -> str:
    """
    Step 3 (function scenarios only):
    Take saved F_*.sql + parameters.json → resolve @params → execute in Oracle → check alerts.
    """
    import json as _json
    from db_connect import connect_to_oracle
    from sql_executer import execute_dataset_query

    output_dir    = state["output_dir"]
    extracted_dir = os.path.join(output_dir, "extracted_queries")
    run_logger    = state.get("run_logger")

    if not os.path.isdir(extracted_dir):
        raise FileNotFoundError(f"Extracted queries directory not found: {extracted_dir}")

    # Find function SQL file
    func_files = [
        f for f in os.listdir(extracted_dir)
        if f.upper().startswith("F_") and f.endswith(".sql")
    ]
    if not func_files:
        raise FileNotFoundError(f"No F_*.sql function files found in {extracted_dir}")

    # Find parameters JSON file
    param_files = [
        f for f in os.listdir(extracted_dir)
        if f.startswith("parameters_") and f.endswith(".json")
    ]
    if not param_files:
        raise FileNotFoundError(f"No parameters_*.json found in {extracted_dir}")

    import os as _os
    func_path = _os.path.join(extracted_dir, max(func_files, key=lambda f: _os.path.getmtime(_os.path.join(extracted_dir, f))))
    param_path = _os.path.join(extracted_dir, max(param_files, key=lambda f: _os.path.getmtime(_os.path.join(extracted_dir, f))))

    with open(func_path, "r", encoding="utf-8") as f:
        func_sql = f.read()

    with open(param_path, "r", encoding="utf-8") as f:
        params = _json.load(f)

    print(f"\nLoaded function: {func_path}")
    print(f"Loaded parameters: {param_path} ({len(params)} params)")

    # Extract SQL portion between after IS and before BEGIN
    import re as _re
    start_match = _re.search(r'\bIS\s+', func_sql, _re.IGNORECASE)
    end_match = _re.search(r'^\s*BEGIN\b', func_sql, _re.MULTILINE)

    if not start_match:
        raise ValueError("Could not find IS in function body")
    if not end_match or end_match.start() <= start_match.end():
        raise ValueError("Could not find BEGIN in function body")

    extracted_sql = func_sql[start_match.end():end_match.start()].strip()
    print(f"\n  Extracted SQL: {len(extracted_sql)} chars")

    # Replace p_* params with resolved values (case-insensitive)
    resolved_sql = extracted_sql
    unmatched = []
    for key, value in params.items():
        pattern = _re.compile(_re.escape(key), _re.IGNORECASE)
        if pattern.search(resolved_sql):
            resolved_sql = pattern.sub(str(value), resolved_sql)
        else:
            unmatched.append((key, value))

    # Fuzzy match for parameters not found directly
    if unmatched:
        print(f"\n  Direct match failed for {len(unmatched)} params, trying fuzzy match...")
        for key, value in unmatched:
            found = False
            # Try removing "Trxn" and fix double underscore
            alt = key.replace("Trxn", "").replace("__", "_")
            if alt != key:
                pattern = _re.compile(_re.escape(alt), _re.IGNORECASE)
                if pattern.search(resolved_sql):
                    resolved_sql = pattern.sub(str(value), resolved_sql)
                    found = True
                    print(f"    Fuzzy match: {key} → {alt}")
            # Try "Cash" → "Csh"
            if not found:
                alt = key.replace("Cash", "Csh")
                if alt != key:
                    pattern = _re.compile(_re.escape(alt), _re.IGNORECASE)
                    if pattern.search(resolved_sql):
                        resolved_sql = pattern.sub(str(value), resolved_sql)
                        found = True
                        print(f"    Fuzzy match: {key} → {alt}")
            # Try both combined + fix double underscore
            if not found:
                alt = key.replace("Trxn", "").replace("Cash", "Csh").replace("__", "_")
                if alt != key:
                    pattern = _re.compile(_re.escape(alt), _re.IGNORECASE)
                    if pattern.search(resolved_sql):
                        resolved_sql = pattern.sub(str(value), resolved_sql)
                        found = True
                        print(f"    Fuzzy match: {key} → {alt}")
            if not found:
                print(f"    WARNING: Could not find '{key}' in SQL")

    resolved_sql = resolved_sql.rstrip(";").strip()
    state["resolved_function_sql"] = resolved_sql  # store for diagnosis

    print(f"  Resolved SQL: {len(resolved_sql)} chars")

    if run_logger:
        run_logger.log_sql(3, "resolved_function", resolved_sql)

    # Execute resolved SQL in Oracle
    conn = None
    try:
        conn = connect_to_oracle()
        has_alerts = execute_dataset_query(conn, resolved_sql, run_logger=run_logger)

        state["has_alerts"] = has_alerts

        if has_alerts:
            return "✅ Resolved function executed — alerts generated. Pipeline complete."
        else:
            # Save resolved SQL as dataset file for CTE analysis (Steps 4-6)
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            ds_file = os.path.join(extracted_dir, f"resolved_function_dataset_{timestamp}.sql")
            with open(ds_file, "w", encoding="utf-8") as f:
                f.write("-- RESOLVED FUNCTION SQL\n")
                f.write(f"-- Extracted: {datetime.now()}\n\n")
                f.write(resolved_sql)
            print(f"\n  Saved resolved function as dataset:\n  {ds_file}")
            return "⚠️ Resolved function executed — no alerts. Proceeding to CTE analysis."
    finally:
        if conn:
            conn.close()
    """
    Step 4 (function scenarios, no alerts):
    Diagnose the resolved function SQL using granular condition analysis.
    """
    from sql_diagnostics import run_granular_cte_diagnostics
    from db_connect import connect_to_oracle

    resolved_sql = state.get("resolved_function_sql", "")
    if not resolved_sql:
        return "No resolved function SQL to diagnose"

    metadata = dict(state.get("cte_metadata", {}))
    metadata["output_dir"] = state.get("output_dir", "")
    run_logger = state.get("run_logger")

    print(f"\n{'=' * 80}")
    print(f"  DIAGNOSING RESOLVED FUNCTION SQL")
    print(f"{'=' * 80}")

    conn = None
    try:
        conn = connect_to_oracle()
        results = run_granular_cte_diagnostics(
            conn,
            [{"name": "resolved_function", "sql": resolved_sql}],
            metadata,
            run_logger=run_logger,
            dataset_query_raw=resolved_sql
        )

        state["results"] = results
        state["diagnostic_results"] = results

        if results:
            r = results[0]
            root_cause = (
                f"CTE '{r['cte_name']}' returns 0 rows. "
                f"Failure type: {r.get('failure_type', 'unknown').upper()}. "
                f"{r.get('likely_cause', '')}"
            )
            if r.get("failure_condition"):
                root_cause += f" Condition: {r['failure_condition'][:200]}"
            if r.get("condition_line_number"):
                root_cause += f" [Line {r['condition_line_number']}]"
        else:
            root_cause = "Diagnosis inconclusive — could not pinpoint root cause"

        state["root_cause"] = root_cause
        return root_cause
    finally:
        if conn:
            conn.close()


def _step_set_batch_date(state: dict) -> str:
    """
    Step 2: SSH into OFSAA server and set the business date.
    """
    from set_batch_date import set_batch_date

    set_batch_date()

    business_date = state["metadata"].get("current_business_date", "unknown")
    return f"Batch date set to: {business_date}"


def _step_sql_executer(state: dict) -> str:
    """
    Step 3: Execute the full scenario SQL and check if alerts are generated.
    If no alerts → sets state["has_alerts"] = False so cte_parser runs next.
    If alerts found → sets state["has_alerts"] = True, pipeline stops here.
    """
    from sql_executer import load_sql_file, execute_dataset_query
    from db_connect import connect_to_oracle

    run_logger = state.get("run_logger")

    # Find dataset query file inside this job's own output directory.
    # We do NOT use get_latest_dataset_query_file() because it walks ALL
    # scenario folders and would return the wrong file when multiple
    # scenarios share the same run date.
    output_dir    = state["output_dir"]
    extracted_dir = os.path.join(output_dir, "extracted_queries")
    dataset_files = [
        os.path.join(extracted_dir, f)
        for f in os.listdir(extracted_dir)
        if "dataset_query" in f.lower() and f.lower().endswith(".sql")
    ] if os.path.isdir(extracted_dir) else []

    if not dataset_files:
        raise FileNotFoundError(
            f"No dataset query file found in {extracted_dir}"
        )
    sql_file = max(dataset_files, key=os.path.getmtime)

    conn = None
    try:
        conn       = connect_to_oracle()
        sql_query  = load_sql_file(sql_file)
        has_alerts = execute_dataset_query(conn, sql_query, run_logger=run_logger)

        state["has_alerts"] = has_alerts

        if has_alerts:
            return "✅ Alerts generated — scenario is working correctly"
        else:
            return "⚠️ No alerts generated — proceeding to CTE analysis"

    finally:
        if conn:
            conn.close()


def _step_cte_parser(state: dict) -> str:
    """
    Step 4: Parse the scenario SQL into individual CTEs and a final query.
    Saves each CTE as a separate .sql file in parsed_ctes/ folder.
    """
    import importlib.util
    cte_parser_path = PIPELINE_DIR / "cte_parser.py"

    spec   = importlib.util.spec_from_file_location("cte_parser", cte_parser_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    # Pass output_dir explicitly so parse_ctes never calls
    # get_latest_output_directory() which could pick a different scenario's folder.
    output_dir = state["output_dir"]
    run_logger = state.get("run_logger")
    if hasattr(module, "parse_ctes"):
        module.parse_ctes(output_dir=output_dir, run_logger=run_logger)
    elif hasattr(module, "main"):
        module.main()

    parsed_dir = os.path.join(output_dir, "parsed_ctes")
    cte_count  = len([
        f for f in os.listdir(parsed_dir)
        if f.endswith(".sql") and f != "final_query.sql"
    ]) if os.path.exists(parsed_dir) else 0

    return f"Parsed {cte_count} CTEs into {parsed_dir}"


def _step_cte_executer(state: dict) -> str:
    """
    Step 5: Execute each CTE as an Oracle view and validate row counts.
    Continues checking ALL CTEs (does NOT stop at first empty).
    Stores results in state for diagnosis.
    """
    import json as _json
    from db_connect import connect_to_oracle

    import importlib.util
    cte_executer_path = PIPELINE_DIR / "cte_executer.py"

    spec   = importlib.util.spec_from_file_location("cte_executer_mod", cte_executer_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    # Use the output dir pinned by step 1 — never call get_latest_output_directory()
    # which could pick a different scenario's folder in concurrent batch runs.
    output_dir = state["output_dir"]
    parsed_dir = os.path.join(output_dir, "parsed_ctes")
    run_logger = state.get("run_logger")

    metadata   = module.load_metadata(output_dir)
    ctes       = module.load_ctes(parsed_dir)
    final_query = module.load_final_query(parsed_dir)

    conn = None
    try:
        conn = connect_to_oracle()

        # Use the new execute_ctes function which checks ALL CTEs
        exec_result = module.execute_ctes(conn, ctes, final_query, metadata, run_logger=run_logger)

        # Store results in state for diagnostics step
        state["cte_results"]    = exec_result["cte_results"]
        state["empty_ctes"]     = exec_result["empty_ctes"]
        state["failed_cte"]     = exec_result["empty_ctes"][0] if exec_result["empty_ctes"] else None
        state["created_views"]  = exec_result["created_views"]
        state["cte_metadata"]   = metadata
        state["conn"]           = conn       # keep connection open for diagnostics
        state["final_query"]    = final_query
        state["final_count"]    = exec_result["final_count"]

        if exec_result["empty_ctes"]:
            empty_names = [c["name"] for c in exec_result["empty_ctes"]]
            return f"Empty CTEs found: {', '.join(empty_names)} — proceeding to diagnosis"
        else:
            return f"All {len(ctes)} CTEs returned rows — final query returned {exec_result['final_count']} rows"

    except Exception as e:
        # Clean up views on error
        if conn and "created_views" in state:
            module.drop_views(conn, state.get("created_views", []))
        raise


def _step_sql_diagnostics(state: dict) -> str:
    """
    Step 6: Run granular diagnosis on the failing CTE.
    Identifies the exact condition causing 0 rows.
    """
    from sql_diagnostics import run_granular_cte_diagnostics, display_granular_results
    from sql_executer import load_sql_file, get_latest_dataset_query_file

    failed_cte    = state.get("failed_cte")
    conn          = state.get("conn")
    metadata      = dict(state.get("cte_metadata", {}))   # copy — don't mutate shared state
    metadata["output_dir"] = state.get("output_dir", "")
    created_views = state.get("created_views", [])
    run_logger    = state.get("run_logger")

    # Load dataset query to find line numbers of killer conditions
    dataset_query_sql = None
    dataset_query_raw = None
    try:
        dataset_file = get_latest_dataset_query_file()
        # Stripped SQL (no comments) — used for diagnosis
        dataset_query_sql = load_sql_file(dataset_file)
        # Raw file content (with comments) — used for accurate line number lookup
        with open(dataset_file, "r", encoding="utf-8") as f:
            dataset_query_raw = f.read()
        logger.info("Loaded dataset query: %s (stripped=%d, raw=%d chars)", dataset_file, len(dataset_query_sql), len(dataset_query_raw))
    except Exception as e:
        logger.warning("Could not load dataset query for line number lookup: %s", e)

    # Import cte_executer module for drop_views
    import importlib.util
    cte_executer_path = PIPELINE_DIR / "cte_executer.py"
    spec   = importlib.util.spec_from_file_location("cte_executer_mod", cte_executer_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    try:
        # Check if any CTE files exist
        import os as _os
        output_dir = metadata.get("output_dir", "")
        parsed_ctes_dir = _os.path.join(output_dir, "parsed_ctes")
        has_ctes = False
        if _os.path.isdir(parsed_ctes_dir):
            cte_files = [f for f in _os.listdir(parsed_ctes_dir)
                         if f.endswith(".sql") and f != "final_query.sql"
                         and not f.startswith("000_")]
            has_ctes = len(cte_files) > 0

        if not failed_cte:
            if not has_ctes:
                # No CTEs — treat entire dataset query as final_query
                if dataset_query_sql:
                    if run_logger:
                        run_logger.log(6, "No CTEs found — treating entire dataset query as final_query")
                    failed_cte = {"name": "final_query", "sql": dataset_query_sql}
                    if run_logger:
                        run_logger.log(6, f"Dataset query loaded for diagnosis ({len(dataset_query_sql)} chars)")
                else:
                    return "No CTEs found and dataset query not available for diagnosis"
            else:
                # All CTEs passed but no alerts — diagnose final query
                final_query = state.get("final_query", "")
                if final_query:
                    failed_cte = {"name": "final_query", "sql": final_query}
                else:
                    # Fallback: use dataset query if no final_query extracted
                    if dataset_query_sql:
                        failed_cte = {"name": "final_query", "sql": dataset_query_sql}
                        if run_logger:
                            run_logger.log(6, "No final_query extracted — using dataset query directly")
                    else:
                        return "No final query or dataset query available for diagnosis"

        # Run diagnosis on the single failing CTE
        results = run_granular_cte_diagnostics(
            conn, [failed_cte], metadata, run_logger=run_logger,
            dataset_query_sql=dataset_query_sql,
            dataset_query_raw=dataset_query_raw
        )

        # Store results in state
        state["results"] = results

        # Build root cause summary
        if results:
            r          = results[0]
            root_cause = (
                f"CTE '{r['cte_name']}' returns 0 rows. "
                f"Failure type: {r.get('failure_type', 'unknown').upper()}. "
                f"{r.get('likely_cause', '')}"
            )
            if r.get("failure_condition"):
                root_cause += f" Condition: {r['failure_condition'][:200]}"
            if r.get("condition_line_number"):
                root_cause += f" [Dataset query line {r['condition_line_number']}]"
        else:
            root_cause = "Diagnosis inconclusive — could not pinpoint root cause"

        state["root_cause"] = root_cause

        # Log root cause summary at the END of the log file (last visible line in UI)
        if run_logger and results:
            r = results[0]
            run_logger.section("ROOT CAUSE SUMMARY")
            run_logger.log(6, f"CTE: {r['cte_name']}")
            run_logger.log(6, f"Failure Type: {r.get('failure_type', 'unknown').upper()}")
            if r.get("failure_condition"):
                run_logger.log(6, f"Killer Condition: {r['failure_condition']}")
            if r.get("condition_line_number"):
                run_logger.log(6, f"Dataset Query Line: {r['condition_line_number']}")
            if r.get("likely_cause"):
                run_logger.log(6, f"Likely Cause: {r['likely_cause']}")
            if r.get("rows_after") is not None:
                run_logger.log(6, f"Rows After Elimination: {r['rows_after']:,}")

        return root_cause

    finally:
        # Always drop views and close connection
        if conn and created_views:
            module.drop_views(conn, created_views)

        # Drop inner query views from final_query diagnosis
        inner_views = []
        for r in state.get("results", []):
            inner_views.extend(r.get("_inner_query_views", []))
        if conn and inner_views:
            module.drop_views(conn, inner_views)

        if conn:
            conn.close()
            logger.info("Oracle connection closed after diagnostics")


# ----------------------------------------------------------------------
# FAILURE HELPER
# ----------------------------------------------------------------------

async def _fail_job(
    job_id:    str,
    username:  str,
    user_id:   int,
    reason:    str,
    queue:     asyncio.Queue,
    state:     dict = None
):
    """Marks the job as failed and notifies the UI."""
    update_job_status(job_id, "failed", error_message=reason)

    await _emit(queue, "job_failed", {
        "job_id":  job_id,
        "message": f"Pipeline stopped: {reason}"
    })

    audit(
        "pipeline_failed",
        username  = username,
        user_id   = user_id,
        job_id    = job_id,
        detail    = reason
    )

    # Close the run logger
    if state:
        run_logger = state.get("run_logger")
        if run_logger:
            run_logger.close()

    logger.error("Pipeline failed — job_id=%s reason=%s", job_id, reason)


# ----------------------------------------------------------------------
# STEP LABEL HELPER
# ----------------------------------------------------------------------

def _step_label(step_name: str) -> str:
    """Returns a human-readable label for a step name."""
    labels = {
        "log_reader":      "Log Reader",
        "set_batch_date":  "Set Batch Date",
        "sql_executer":    "SQL Executer",
        "cte_parser":      "CTE Parser",
        "cte_executer":    "CTE Executer",
        "sql_diagnostics": "SQL Diagnostics"
    }
    return labels.get(step_name, step_name)
