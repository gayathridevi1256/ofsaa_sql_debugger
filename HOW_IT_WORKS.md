# How the OFSAA Scenario Debugger Works

## Problem Statement

OFSAA AML scenarios are complex SQL pipelines. When a scenario runs but produces **zero alerts**, an analyst must manually trace through nested CTEs, date filters, JOIN conditions, and threshold logic to find the root cause — a process that takes hours.

This tool **automates that investigation** end-to-end by re-executing the scenario SQL and diagnosing which condition filters out all rows.

---

## Two Scenario Types

The system handles two fundamentally different types of OFSAA scenarios, each with its own pipeline flow:

| Type | Description | Detection |
|------|-------------|-----------|
| **Standard (non-function)** | SQL query with WITH clause (CTEs) | Scenario ID does NOT match function patterns |
| **Function** | PL/SQL function with `@param` placeholders that must be resolved | Scenario ID matches patterns like `F_*` |

The system detects the type automatically in **Step 1 (Log Reader)** via `scenario_config.py` and branches accordingly.

---

## Standard (Non-Function) Scenario Flow

```
User uploads .log file
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: Log Reader                                                  │
│ • Read .log file                                                    │
│ • Extract metadata: scenario name, business date, threshold set ID  │
│ • Extract embedded SQL query                                        │
│ • Detect scenario type → STANDARD                                    │
│ • Save extracted query as outputs/<Name>/extracted_queries/         │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 2: Set Batch Date                                              │
│ • SSH into OFSAA server (Paramiko)                                  │
│ • Update MANTAS_BATCH_PARAMETER table with business date from log   │
│ • Ensures re-execution uses same date context as original run       │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 3: SQL Executer                                                │
│ • Connect to Oracle with credentials from .env                       │
│ • Load full scenario SQL from extracted_queries/                    │
│ • Execute the SQL                                                   │
│ • Check if any rows (alerts) are returned                           │
│                                                                    │
│   ┌─ Alerts found? ──► ✅ Pipeline stops — scenario is working     │
│   │                                                                │
│   └─ No alerts ──────► Continue to CTE analysis                    │
└────────────────────────────────┬────────────────────────────────────┘
                                 │  (no alerts)
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 4: CTE Parser                                                  │
│ • Use sqlglot to decompose scenario SQL                             │
│ • Split into individual CTEs + final SELECT query                   │
│ • Save each as separate .sql file:                                  │
│                                                                    │
│   parsed_ctes/                                                      │
│   ├── cte_01_data.sql                                               │
│   ├── cte_02_filtered.sql                                           │
│   ├── cte_03_aggregated.sql                                         │
│   └── final_query.sql                                               │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 5: CTE Executer                                                │
│ • Connect to Oracle                                                  │
│ • For each CTE (in definition order):                                │
│     1. Create temporary Oracle view                                  │
│     2. Count rows returned                                           │
│     3. Record result                                                 │
│ • Execute final query, record count                                  │
│ • Identify ALL empty CTEs (continues past the first)                 │
│                                                                    │
│   ┌─ All CTEs have rows? ──► Diagnose final query                   │
│   │                                                                │
│   └─ Empty CTE found ──► Diagnose the failing CTE                   │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 6: SQL Diagnostics (2888 lines — the core engine)              │
│                                                                     │
│ Runs granular condition analysis on the failing CTE or final query: │
│                                                                     │
│ 1. JOIN Analysis:                                                   │
│    Replace each JOIN condition with 1=1 → test if rows appear       │
│                                                                     │
│ 2. WHERE Filter Analysis:                                           │
│    Comment out each WHERE condition → test if rows appear           │
│                                                                     │
│ 3. Date Range Analysis:                                             │
│    Check if date filters exclude all data (common: format mismatch) │
│                                                                     │
│ 4. Threshold Condition Analysis:                                    │
│    Check if threshold params are too high/low → filter out all      │
│                                                                     │
│ 5. Missing Data Detection:                                          │
│    Verify source tables contain data for the given date range       │
│                                                                     │
│ Each condition is tested IN ISOLATION — remove one at a time        │
│ while keeping everything else intact.                               │
│                                                                     │
│ Output: root cause report showing:                                  │
│ • Which CTE failed                                                  │
│ • The exact condition causing zero rows                             │
│ • Line number in original SQL                                       │
│ • Likely cause description                                          │
│ • Row counts before/after killer condition                          │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
                    📋 Results displayed in browser UI
```

---

## Function Scenario Flow

Function scenarios contain a PL/SQL function body with parameter placeholders (e.g., `@p_cash_threshold`). These must be **resolved** before execution.

```
User uploads .log file
        │
        ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 1: Log Reader                                                  │
│ • Read .log file                                                    │
│ • Extract metadata: scenario name, business date, threshold set ID  │
│ • Extract function SQL + parameter definitions from log             │
│ • Detect scenario type → FUNCTION                                    │
│ • Save function body as F_*.sql, parameters as parameters_*.json    │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 2: Set Batch Date                                              │
│ • Same as standard flow — SSH + set business date                    │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEP 3: Resolve & Execute Function SQL                              │
│ • Load F_*.sql function body                                        │
│ • Load parameters_*.json extracted from log                         │
│ • Extract SQL portion between IS and BEGIN keywords                 │
│ • Resolve @param placeholders with values from JSON                 │
│                                                                     │
│   Parameter Resolution Strategy:                                    │
│   ┌────────────────────────────────────────────────────────┐       │
│   │ 1. Direct match: @p_CashThreshold → 50000              │       │
│   │ 2. Fuzzy: try removing "Trxn", fix "__" → ""           │       │
│   │ 3. Fuzzy: try "Cash" → "Csh" variations               │       │
│   │ 4. Fuzzy: combine both + fix double underscore         │       │
│   └────────────────────────────────────────────────────────┘       │
│                                                                     │
│ • Execute resolved SQL against Oracle                               │
│ • Check if any rows (alerts) are returned                           │
│                                                                     │
│   ┌─ Alerts found? ──► ✅ Pipeline stops — scenario is working     │
│   │                                                                │
│   └─ No alerts ──────► Save resolved SQL, continue to CTE analysis │
└────────────────────────────────┬────────────────────────────────────┘
                                 │  (no alerts)
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│ STEPS 4-6: Standard CTE Analysis                                    │
│                                                                     │
│ The resolved function SQL is treated like a standard scenario       │
│ query from this point forward:                                      │
│                                                                     │
│ Step 4: CTE Parser → Split resolved SQL into CTEs                   │
│ Step 5: CTE Executer → Run each CTE, find first empty               │
│ Step 6: SQL Diagnostics → Granular diagnosis on failing CTE         │
└─────────────────────────────────────────────────────────────────────┘
```

### Parameter Resolution Detail

Function scenarios contain SQL like:
```sql
SELECT * FROM transactions
WHERE amount > @p_CashThreshold
  AND customer_type = '@p_CustomerType'
```

The log contains the actual values for these parameters. The resolution process:

1. **Extract** the SQL portion between `IS` and `BEGIN` keywords from the function body
2. **Match** each `@param` to its value from the log's parameter JSON
3. **Substitute** directly — case-insensitive regex replacement
4. **Fuzzy fallback** — if `@p_CashTrxnThreshold` doesn't match, try `@p_CashThreshold` (remove "Trxn"), `@p_CshThreshold` (Cash → Csh), etc.
5. **Execute** the fully resolved SQL

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     Browser (React SPA)                          │
│                                                                  │
│  Login → Dashboard → Upload .log → Results (live WebSocket)     │
└──────────────────────────────────────────────────┬───────────────┘
                                                   │
                          HTTP (REST) + WebSocket (ws://)
                                                   │
┌──────────────────────────────────────────────────┼───────────────┐
│                     FastAPI Backend (Python 3.13)                │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────────┐   │
│  │  Auth    │  │ Upload   │  │  Jobs    │  │  WebSocket     │   │
│  │  Routes  │  │ Handler  │  │  Runner  │  │  (live stream) │   │
│  └──────────┘  └──────────┘  └────┬─────┘  └────────────────┘   │
│                                    │                             │
│                           ┌────────▼────────┐                   │
│                           │   Orchestrator  │                   │
│                           │  (runs steps    │                   │
│                           │   with branching│                   │
│                           │   for function  │                   │
│                           │   vs standard)  │                   │
│                           └────────┬────────┘                   │
│                                    │                             │
│    ┌───────────┬───────────┬───────┼───────┬───────────┐       │
│    │           │           │       │       │           │       │
│    ▼           ▼           ▼       ▼       ▼           ▼       │
│  Step 1      Step 2     Step 3   Step 4  Step 5     Step 6    │
│  log_reader  set_batch  sql_exec  cte_par cte_exec   sql_diag │
│              _date      _uter     ser     _uter      _nostics │
│                         └──┬──┘                                │
│                      (branches here:                          │
│                       standard vs function)                    │
│                                                               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐  │
│  │    SQLite DB     │  │  File System    │  │  Output Dir  │  │
│  │  (users, jobs,  │  │  (uploads/)     │  │  (outputs/)  │  │
│  │   audit_log)    │  │                 │  │              │  │
│  └─────────────────┘  └─────────────────┘  └──────────────┘  │
└───────────────────────┬───────────────────────────────────────┘
                        │
          ┌─────────────┴─────────────┐
          │                           │
          ▼                           ▼
   ┌──────────────┐          ┌──────────────┐
   │  Oracle DB   │          │ OFSAA Server │
   │  (run SQL,   │          │  (SSH — set  │
   │   check rows)│          │  batch date) │
   └──────────────┘          └──────────────┘
```

---

## Orchestrator Branching Logic

The orchestrator (`backend/orchestrator.py`) detects the scenario type after Step 1 and chooses the appropriate path:

```
Step 1 (Log Reader) completes
        │
        ├── multi_query = false ──► STANDARD FLOW
        │                              │
        │                              ▼
        │                         Step 2 (Set Batch Date)
        │                              │
        │                              ▼
        │                         Step 3 (SQL Executer)
        │                              │
        │                         ┌────┴────┐
        │                         │         │
        │                      alerts   no alerts
        │                         │         │
        │                      ✅ STOP    Step 4 (CTE Parser)
        │                                    │
        │                                    ▼
        │                               Step 5 (CTE Executer)
        │                                    │
        │                                    ▼
        │                               Step 6 (SQL Diagnostics)
        │                                    │
        │                                    ▼
        │                               📋 Root cause
        │
        └── multi_query = true ───► FUNCTION FLOW
                                       │
                                       ▼
                                  Step 2 (Set Batch Date)
                                       │
                                       ▼
                                  Step 3 (Resolve & Execute)
                                       │
                                  ┌────┴────┐
                                  │         │
                               alerts   no alerts
                                  │         │
                               ✅ STOP    Save resolved SQL
                                          Continue to Steps 4-6
```

---

## Real-Time Progress Streaming

Pipeline Step → `asyncio.Queue` → WebSocket broadcast → React UI update

| WebSocket Event | When | Data |
|-----------------|------|------|
| `step_started` | Step begins | step name, message |
| `step_completed` | Step succeeds | step name, output |
| `step_failed` | Step errors | step name, error |
| `job_completed` | All steps done | root cause, alerts, results |
| `job_failed` | Pipeline crashed | error reason |
| `job_state` | On WS connect | current job snapshot |
| `ping` | Every 30s | keep-alive |

---

## Database Schema

SQLite at `<APP_BASE_PATH>/db/scenario_debugger.db`

| Table | Purpose |
|-------|---------|
| `users` | Authentication, roles (admin/analyst), bcrypt hashed passwords |
| `jobs` | Every pipeline run: status, scenario name, batch date, root cause, results |
| `job_steps` | Per-step status for each job (powers live progress) |
| `audit_log` | Immutable record of all actions (login, upload, pipeline, user mgmt) |

---

## Output Directory

```
outputs/
└── SCENARIO_NAME/
    ├── metadata.json              # Extracted scenario metadata
    ├── extracted_queries/
    │   ├── dataset_query_*.sql    # Full scenario SQL (standard flow)
    │   ├── F_*.sql                # Function body (function flow)
    │   └── parameters_*.json      # Parameter values (function flow)
    ├── parsed_ctes/
    │   ├── cte_01_<name>.sql      # Individual CTEs
    │   ├── cte_02_<name>.sql
    │   ├── ...
    │   └── final_query.sql
    └── run_log_*.txt              # Structured per-run log
```

---

## Security

- Passwords: **bcrypt** hashed, never plain text
- Auth: **JWT** tokens (HS256), configurable expiry (default 8h)
- Roles: `admin` (full access) / `analyst` (own jobs only)
- LDAP optional for enterprise Active Directory integration
- Uploads: `.log`/`.txt` only, max 50 MB
- CORS restricted, global exception handler prevents trace leakage
- Audit log tracks all sensitive actions

---

## Caching

Before starting a new pipeline run, the system checks if a completed job already exists for the same scenario name + batch date. If found, it returns the cached result immediately. Pass `?force=true` to bypass.
