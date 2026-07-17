"""
jobs.py — SQLite database setup and job tracking for Scenario Debugger.

WHAT THIS FILE DOES:
    1. Creates the SQLite database and all tables on first run
    2. Tracks every pipeline run (who ran it, when, which log file, status)
    3. Stores audit logs (who logged in, what actions were taken)
    4. Manages user accounts (username, hashed password, role)

LAYMAN'S EXPLANATION:
    SQLite is a database that lives in a single file on your disk.
    No separate database server needed — it's just a file like scenario_debugger.db.
    Think of it as a very powerful Excel file that Python can read/write quickly.

    We have 3 tables (like 3 sheets in Excel):
        users     — who can log in
        jobs      — every pipeline run ever triggered
        audit_log — every important action (login, upload, run, etc.)
"""

import sqlite3
import logging
from datetime import datetime, timezone
from pathlib import Path
from contextlib import contextmanager

from config import DB_PATH

logger = logging.getLogger(__name__)


# ----------------------------------------------------------------------
# DATABASE CONNECTION
# ----------------------------------------------------------------------

@contextmanager
def get_db():
    """
    Context manager that opens a database connection and closes it cleanly.

    LAYMAN: This is like opening a filing cabinet, doing your work,
    then making sure it's locked when you're done — even if something
    goes wrong in the middle.

    USAGE:
        with get_db() as db:
            db.execute("SELECT * FROM users")
    """
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row   # rows behave like dicts: row["username"]
    conn.execute("PRAGMA journal_mode=WAL")   # safer for concurrent access
    conn.execute("PRAGMA foreign_keys=ON")    # enforce relationships
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


# ----------------------------------------------------------------------
# DATABASE INITIALISATION
# ----------------------------------------------------------------------

def init_db():
    """
    Creates all tables if they don't exist.
    Safe to call every time the app starts — won't overwrite existing data.

    LAYMAN: This is the app "setting up its filing cabinet drawers"
    on first run. On subsequent runs it checks if the drawers exist
    and skips if they do.
    """
    logger.info("Initialising database at: %s", DB_PATH)

    # Ensure the db directory exists
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)

    with get_db() as db:

        # ------------------------------------------------------------------
        # USERS TABLE
        # Stores who can log in to the application.
        # Passwords are NEVER stored in plain text — only a bcrypt hash.
        # ------------------------------------------------------------------
        db.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                username      TEXT    NOT NULL UNIQUE,
                password_hash TEXT    NOT NULL,
                full_name     TEXT    NOT NULL DEFAULT '',
                email         TEXT    NOT NULL DEFAULT '',
                role          TEXT    NOT NULL DEFAULT 'analyst',
                is_active     INTEGER NOT NULL DEFAULT 1,
                created_at    TEXT    NOT NULL,
                last_login    TEXT
            )
        """)

        # ------------------------------------------------------------------
        # JOBS TABLE
        # Every pipeline run is a "job". Tracks status of each step.
        #
        # status values:
        #   pending    — job created, not started yet
        #   running    — pipeline is currently executing
        #   completed  — all steps finished (alerts may or may not have fired)
        #   failed     — pipeline crashed with an error
        # ------------------------------------------------------------------
        db.execute("""
            CREATE TABLE IF NOT EXISTS jobs (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id           TEXT    NOT NULL UNIQUE,  -- UUID
                user_id          INTEGER NOT NULL REFERENCES users(id),
                log_filename     TEXT    NOT NULL,          -- uploaded log file name
                scenario_name    TEXT,                      -- extracted from log
                batch_date       TEXT,                      -- extracted from log
                status           TEXT    NOT NULL DEFAULT 'pending',
                current_step     TEXT,                      -- which pipeline step is running
                started_at       TEXT    NOT NULL,
                completed_at     TEXT,
                error_message    TEXT,                      -- if failed, why
                output_dir       TEXT,                      -- where outputs are stored
                alerts_generated INTEGER DEFAULT 0,         -- 1 = yes, 0 = no
                root_cause       TEXT,                      -- final diagnosis summary
                result_json      TEXT,                      -- full JSON result blob (diagnostic results)
                cte_results_json TEXT                       -- CTE waterfall row data
            )
        """)

        # ------------------------------------------------------------------
        # JOB STEPS TABLE
        # Tracks each individual pipeline step within a job.
        # This powers the live progress tracker in the UI.
        #
        # step_name values match your pipeline scripts:
        #   log_reader, set_batch_date, sql_executer,
        #   cte_parser, cte_executer, sql_diagnostics
        # ------------------------------------------------------------------
        db.execute("""
            CREATE TABLE IF NOT EXISTS job_steps (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id      TEXT    NOT NULL REFERENCES jobs(job_id),
                step_name   TEXT    NOT NULL,
                status      TEXT    NOT NULL DEFAULT 'pending',
                started_at  TEXT,
                completed_at TEXT,
                output      TEXT,   -- stdout/stderr from the step
                error       TEXT    -- error message if step failed
            )
        """)

        # ------------------------------------------------------------------
        # AUDIT LOG TABLE
        # Records every important action for security compliance.
        # In a bank environment this is non-negotiable.
        #
        # action values examples:
        #   user_login, user_logout, user_login_failed,
        #   file_upload, pipeline_started, pipeline_completed,
        #   user_created, user_deactivated
        # ------------------------------------------------------------------
        db.execute("""
            CREATE TABLE IF NOT EXISTS audit_log (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp  TEXT    NOT NULL,
                user_id    INTEGER REFERENCES users(id),
                username   TEXT,                  -- stored separately in case user deleted
                action     TEXT    NOT NULL,
                detail     TEXT,                  -- extra context about the action
                ip_address TEXT,                  -- client IP address
                job_id     TEXT                   -- linked job if relevant
            )
        """)

    logger.info("Database initialised successfully")


# ----------------------------------------------------------------------
# USER FUNCTIONS
# ----------------------------------------------------------------------

def create_user(username: str, password_hash: str, full_name: str,
                email: str, role: str = "analyst") -> int:
    """
    Creates a new user. Password must already be hashed before calling this.
    Returns the new user's ID.

    Roles:
        analyst — can upload files and run the pipeline
        admin   — can also manage users
    """
    now = _now()
    with get_db() as db:
        cursor = db.execute("""
            INSERT INTO users (username, password_hash, full_name, email, role, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """, (username, password_hash, full_name, email, role, now))
        user_id = cursor.lastrowid

    logger.info("User created: %s (role: %s)", username, role)
    return user_id


def get_user_by_username(username: str) -> dict | None:
    """Returns a user dict by username, or None if not found."""
    with get_db() as db:
        row = db.execute(
            "SELECT * FROM users WHERE username = ? AND is_active = 1",
            (username,)
        ).fetchone()
    return dict(row) if row else None


def get_user_by_id(user_id: int) -> dict | None:
    """Returns a user dict by ID, or None if not found."""
    with get_db() as db:
        row = db.execute(
            "SELECT * FROM users WHERE id = ? AND is_active = 1",
            (user_id,)
        ).fetchone()
    return dict(row) if row else None


def update_last_login(user_id: int):
    """Updates the last_login timestamp for a user."""
    with get_db() as db:
        db.execute(
            "UPDATE users SET last_login = ? WHERE id = ?",
            (_now(), user_id)
        )


def list_users() -> list[dict]:
    """Returns all active users (admin use only)."""
    with get_db() as db:
        rows = db.execute("""
            SELECT id, username, full_name, email, role,
                   is_active, created_at, last_login
            FROM users
            ORDER BY created_at DESC
        """).fetchall()
    return [dict(r) for r in rows]


def deactivate_user(user_id: int):
    """Deactivates a user (soft delete — data is kept)."""
    with get_db() as db:
        db.execute(
            "UPDATE users SET is_active = 0 WHERE id = ?",
            (user_id,)
        )
    logger.info("User deactivated: id=%s", user_id)


# ----------------------------------------------------------------------
# JOB FUNCTIONS
# ----------------------------------------------------------------------

def create_job(job_id: str, user_id: int, log_filename: str) -> dict:
    """
    Creates a new pipeline job record.
    Returns the created job as a dict.

    LAYMAN: Every time someone uploads a log file and clicks Run,
    a new "job" is created here. It's like a ticket that tracks
    the entire pipeline run from start to finish.
    """
    now = _now()

    # Create the job record
    with get_db() as db:
        db.execute("""
            INSERT INTO jobs (job_id, user_id, log_filename, status, started_at)
            VALUES (?, ?, ?, 'pending', ?)
        """, (job_id, user_id, log_filename, now))

        # Create a pending record for each pipeline step
        steps = [
            "log_reader",
            "set_batch_date",
            "sql_executer",
            "cte_parser",
            "cte_executer",
            "sql_diagnostics"
        ]
        for step in steps:
            db.execute("""
                INSERT INTO job_steps (job_id, step_name, status)
                VALUES (?, ?, 'pending')
            """, (job_id, step))

    logger.info("Job created: %s for user_id=%s file=%s", job_id, user_id, log_filename)
    return get_job(job_id)


def get_job(job_id: str) -> dict | None:
    """Returns a job dict with all its steps, or None if not found."""
    with get_db() as db:
        job_row = db.execute(
            "SELECT * FROM jobs WHERE job_id = ?", (job_id,)
        ).fetchone()

        if not job_row:
            return None

        step_rows = db.execute(
            "SELECT * FROM job_steps WHERE job_id = ? ORDER BY id",
            (job_id,)
        ).fetchall()

    job = dict(job_row)
    job["steps"] = [dict(s) for s in step_rows]
    return job


def list_jobs(user_id: int = None, limit: int = 50) -> list[dict]:
    """
    Returns recent jobs, optionally filtered by user.
    Admins see all jobs; analysts see only their own.
    """
    with get_db() as db:
        if user_id:
            rows = db.execute("""
                SELECT j.*, u.username
                FROM jobs j
                JOIN users u ON j.user_id = u.id
                WHERE j.user_id = ?
                ORDER BY j.started_at DESC
                LIMIT ?
            """, (user_id, limit)).fetchall()
        else:
            rows = db.execute("""
                SELECT j.*, u.username
                FROM jobs j
                JOIN users u ON j.user_id = u.id
                ORDER BY j.started_at DESC
                LIMIT ?
            """, (limit,)).fetchall()

    return [dict(r) for r in rows]


def update_job_status(job_id: str, status: str,
                      current_step: str = None,
                      error_message: str = None,
                      scenario_name: str = None,
                      batch_date: str = None,
                      output_dir: str = None,
                      alerts_generated: int = None,
                      root_cause: str = None,
                      result_json: str = None,
                      cte_results_json: str = None):
    """Updates a job's status and optional fields."""
    fields = ["status = ?"]
    values = [status]

    if current_step      is not None: fields.append("current_step = ?");      values.append(current_step)
    if error_message     is not None: fields.append("error_message = ?");     values.append(error_message)
    if scenario_name     is not None: fields.append("scenario_name = ?");     values.append(scenario_name)
    if batch_date        is not None: fields.append("batch_date = ?");        values.append(batch_date)
    if output_dir        is not None: fields.append("output_dir = ?");        values.append(output_dir)
    if alerts_generated  is not None: fields.append("alerts_generated = ?");  values.append(alerts_generated)
    if root_cause        is not None: fields.append("root_cause = ?");        values.append(root_cause)
    if result_json       is not None: fields.append("result_json = ?");       values.append(result_json)
    if cte_results_json  is not None: fields.append("cte_results_json = ?");  values.append(cte_results_json)

    if status in ("completed", "failed"):
        fields.append("completed_at = ?")
        values.append(_now())

    values.append(job_id)

    with get_db() as db:
        db.execute(
            f"UPDATE jobs SET {', '.join(fields)} WHERE job_id = ?",
            values
        )


def update_step_status(job_id: str, step_name: str, status: str,
                       output: str = None, error: str = None):
    """
    Updates the status of a specific pipeline step within a job.
    Called by pipeline.py as each step starts/completes/fails.

    LAYMAN: This is what makes the live progress tracker in the UI work.
    As each pipeline step runs, it calls this to say "I started" or
    "I finished" and the UI picks that up in real time.
    """
    fields = ["status = ?"]
    values = [status]

    if status == "running":
        fields.append("started_at = ?")
        values.append(_now())

    if status in ("completed", "failed"):
        fields.append("completed_at = ?")
        values.append(_now())

    if output is not None:
        fields.append("output = ?")
        values.append(output)

    if error is not None:
        fields.append("error = ?")
        values.append(error)

    values.extend([job_id, step_name])

    with get_db() as db:
        db.execute(
            f"UPDATE job_steps SET {', '.join(fields)} "
            f"WHERE job_id = ? AND step_name = ?",
            values
        )


# ----------------------------------------------------------------------
# CACHE LOOKUP
# ----------------------------------------------------------------------

def get_cached_job(scenario_name: str, batch_date: str) -> dict | None:
    """
    Returns the most recent completed job for this scenario + batch date.
    Used to offer cached results instead of re-running the full pipeline.
    """
    with get_db() as db:
        row = db.execute("""
            SELECT * FROM jobs
            WHERE scenario_name = ?
              AND batch_date     = ?
              AND status         = 'completed'
            ORDER BY completed_at DESC
            LIMIT 1
        """, (scenario_name, batch_date)).fetchone()
    return dict(row) if row else None


# ----------------------------------------------------------------------
# AUDIT LOG FUNCTIONS
# ----------------------------------------------------------------------

def audit(action: str, username: str = None, user_id: int = None,
          detail: str = None, ip_address: str = None, job_id: str = None):
    """
    Records an audit log entry.

    LAYMAN: This is the app's security diary. Every important action
    — login, file upload, pipeline run — gets written here with a
    timestamp. Banks require this for compliance.

    USAGE:
        audit("user_login", username="john", ip_address="192.168.1.5")
        audit("pipeline_started", username="john", job_id="abc-123")
    """
    with get_db() as db:
        db.execute("""
            INSERT INTO audit_log
                (timestamp, user_id, username, action, detail, ip_address, job_id)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (_now(), user_id, username, action, detail, ip_address, job_id))


def get_audit_log(limit: int = 100, user_id: int = None) -> list[dict]:
    """Returns recent audit log entries (admin use only)."""
    with get_db() as db:
        if user_id:
            rows = db.execute("""
                SELECT * FROM audit_log
                WHERE user_id = ?
                ORDER BY timestamp DESC LIMIT ?
            """, (user_id, limit)).fetchall()
        else:
            rows = db.execute("""
                SELECT * FROM audit_log
                ORDER BY timestamp DESC LIMIT ?
            """, (limit,)).fetchall()

    return [dict(r) for r in rows]


# ----------------------------------------------------------------------
# HELPER
# ----------------------------------------------------------------------

def _now() -> str:
    """Returns current UTC time as ISO 8601 string."""
    return datetime.now(timezone.utc).isoformat()


# ----------------------------------------------------------------------
# FIRST-RUN ADMIN SETUP
# ----------------------------------------------------------------------

def ensure_admin_exists():
    """
    Creates a default admin user if no users exist at all.
    This runs once on first startup so there's always a way to log in.

    IMPORTANT: Change the default password immediately after first login.
    Default credentials: admin / changeme123
    """
    import bcrypt

    with get_db() as db:
        count = db.execute("SELECT COUNT(*) FROM users").fetchone()[0]

    if count == 0:
        password_hash = bcrypt.hashpw(
            "changeme123".encode(),
            bcrypt.gensalt()
        ).decode()

        create_user(
            username="admin",
            password_hash=password_hash,
            full_name="Administrator",
            email="admin@localhost",
            role="admin"
        )

        logger.warning(
            "=" * 60
        )
        logger.warning("DEFAULT ADMIN CREATED")
        logger.warning("Username : admin")
        logger.warning("Password : changeme123")
        logger.warning("CHANGE THIS PASSWORD IMMEDIATELY AFTER FIRST LOGIN")
        logger.warning("=" * 60)
