"""
main.py — FastAPI application entry point for Scenario Debugger.

WHAT THIS FILE DOES:
    1. Creates the FastAPI app and configures it
    2. Defines all API routes (endpoints the UI calls)
    3. Handles file uploads
    4. Streams pipeline progress via WebSocket
    5. Manages user authentication
    6. Admin routes for user management

LAYMAN'S EXPLANATION:
    This is the "front door" of the backend.
    Every request from the React UI comes here first.

    ROUTES are like phone extensions:
        POST /api/auth/login     → extension for logging in
        POST /api/jobs/run       → extension for starting a pipeline run
        GET  /api/jobs           → extension for listing past runs
        WS   /api/ws/{job_id}    → live progress feed for a running job

    When React calls POST /api/jobs/run:
        1. FastAPI checks the JWT token (are you logged in?)
        2. Saves the uploaded file
        3. Creates a job record in the database
        4. Starts the pipeline in the background
        5. Returns the job_id so the UI can track progress via WebSocket

WEBSOCKET:
    A WebSocket is a persistent two-way connection between browser and server.
    Unlike normal HTTP (ask → answer → done), WebSocket stays open.
    The server can keep pushing messages as the pipeline progresses.
    React shows each message as a live progress update.
"""

import sys

# Pipeline steps print emoji (✅ ❌ ⚠️) — Windows cp1252 console can't encode them.
# Reconfigure stdout/stderr to UTF-8 once here so every print() in every module works.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

import asyncio
import json
import logging
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from fastapi import (
    FastAPI, Depends, HTTPException, UploadFile,
    File, WebSocket, WebSocketDisconnect, Request,
    status, BackgroundTasks
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel, EmailStr

from auth import (
    authenticate_user,
    create_access_token,
    get_current_user,
    get_current_analyst,
    get_current_admin,
    hash_password
)
from config import (
    APP_NAME, APP_VERSION, CORS_ORIGINS,
    UPLOADS_DIR, MAX_UPLOAD_MB,
    create_app_directories, setup_logging, print_config_summary
)
from jobs import (
    init_db, ensure_admin_exists,
    create_job, get_job, list_jobs,
    create_user, list_users, deactivate_user,
    get_audit_log, audit, update_job_status,
    get_cached_job
)
from orchestrator import run_pipeline

# ----------------------------------------------------------------------
# STARTUP
# ----------------------------------------------------------------------

# Setup logging first
setup_logging()
logger = logging.getLogger(__name__)

# Create all required directories
create_app_directories()

# Initialise database and tables
init_db()

# Create default admin if no users exist
ensure_admin_exists()

# Print config summary to terminal
print_config_summary()

# ----------------------------------------------------------------------
# FASTAPI APP
# ----------------------------------------------------------------------

app = FastAPI(
    title       = APP_NAME,
    version     = APP_VERSION,
    description = "OFSAA AML Scenario Diagnostic Tool",
    # Disable docs in production by setting docs_url=None
    # For now keep enabled — useful for development
    docs_url    = "/docs",
    redoc_url   = "/redoc"
)

# ----------------------------------------------------------------------
# MIDDLEWARE
# ----------------------------------------------------------------------

# CORS — controls which domains can call the API
# LAYMAN: Without this, the browser blocks React from calling FastAPI
# because they run on different ports locally (5173 vs 8000)
app.add_middleware(
    CORSMiddleware,
    allow_origins     = CORS_ORIGINS,
    allow_credentials = True,
    allow_methods     = ["*"],
    allow_headers     = ["*"]
)

# ----------------------------------------------------------------------
# ACTIVE WEBSOCKET CONNECTIONS
# Stores job_id → list of connected WebSocket clients
# Multiple browser tabs can watch the same job
# ----------------------------------------------------------------------
active_connections: dict[str, list[WebSocket]] = {}

# Active pipeline progress queues: job_id → asyncio.Queue
active_queues: dict[str, asyncio.Queue] = {}


# ----------------------------------------------------------------------
# PYDANTIC MODELS
# Pydantic models define the shape of request and response data.
# LAYMAN: These are like "forms" — they describe what fields
# are expected in a request and what fields will be in a response.
# FastAPI automatically validates incoming data against these.
# ----------------------------------------------------------------------

class LoginResponse(BaseModel):
    access_token: str
    token_type:   str = "bearer"
    username:     str
    full_name:    str
    role:         str
    expires_in:   int  # minutes


class BatchRunRequest(BaseModel):
    file_paths: list[str]


class CreateUserRequest(BaseModel):
    username:  str
    password:  str
    full_name: str
    email:     str = ""
    role:      str = "analyst"


class JobResponse(BaseModel):
    job_id:       str
    status:       str
    scenario_name: Optional[str]
    batch_date:   Optional[str]
    started_at:   str
    completed_at: Optional[str]
    alerts_generated: Optional[int]
    root_cause:   Optional[str]
    steps:        list


# ----------------------------------------------------------------------
# ROUTES — HEALTH CHECK
# ----------------------------------------------------------------------

@app.get("/", tags=["Health"])
async def root():
    """
    Health check endpoint.
    Useful for monitoring — if this returns 200, the app is running.
    """
    return {
        "app":     APP_NAME,
        "version": APP_VERSION,
        "status":  "running",
        "time":    datetime.now(timezone.utc).isoformat()
    }


@app.get("/api/health", tags=["Health"])
async def health():
    """Detailed health check."""
    return {"status": "healthy", "version": APP_VERSION}


# ----------------------------------------------------------------------
# ROUTES — AUTHENTICATION
# ----------------------------------------------------------------------

@app.post("/api/auth/login", response_model=LoginResponse, tags=["Auth"])
async def login(
    request:    Request,
    form_data:  OAuth2PasswordRequestForm = Depends()
):
    """
    Login endpoint. Accepts username and password, returns JWT token.

    LAYMAN: This is the login page backend.
    React sends username + password here.
    If correct → returns a JWT token.
    React stores the token and sends it with every future request.

    The token is like a session cookie but more secure.
    """
    ip_address = request.client.host

    # Authenticate — raises 401 if invalid
    user = authenticate_user(
        username   = form_data.username,
        password   = form_data.password,
        ip_address = ip_address
    )

    # Create JWT token
    token = create_access_token(
        user_id  = user["id"],
        username = user["username"],
        role     = user["role"]
    )

    from config import JWT_EXPIRY_MINUTES
    return LoginResponse(
        access_token = token,
        username     = user["username"],
        full_name    = user["full_name"],
        role         = user["role"],
        expires_in   = JWT_EXPIRY_MINUTES
    )


@app.get("/api/auth/me", tags=["Auth"])
async def get_me(current_user: dict = Depends(get_current_user)):
    """
    Returns the currently logged-in user's details.
    React calls this on app load to check if the stored token is still valid.
    """
    return {
        "id":        current_user["id"],
        "username":  current_user["username"],
        "full_name": current_user["full_name"],
        "email":     current_user["email"],
        "role":      current_user["role"],
        "last_login": current_user.get("last_login")
    }


# ----------------------------------------------------------------------
# ROUTES — FILE UPLOAD
# ----------------------------------------------------------------------

@app.post("/api/upload", tags=["Pipeline"])
async def upload_log_file(
    file:         UploadFile = File(...),
    current_user: dict       = Depends(get_current_analyst)
):
    """
    Uploads an OFSAA log file.
    Returns the saved file path for use in /api/jobs/run.

    LAYMAN: This is the "drop zone" endpoint.
    When a user drags and drops a log file in the UI,
    React sends it here. We save it to the uploads folder
    and return the path so the pipeline knows where to find it.
    """
    # Validate file type
    if not file.filename.endswith((".log", ".txt")):
        raise HTTPException(
            status_code = 400,
            detail      = "Only .log and .txt files are accepted"
        )

    # Validate file size
    max_bytes = MAX_UPLOAD_MB * 1024 * 1024
    content   = await file.read()

    if len(content) > max_bytes:
        raise HTTPException(
            status_code = 413,
            detail      = f"File too large. Maximum size is {MAX_UPLOAD_MB}MB"
        )

    # Save file with unique name to avoid collisions
    safe_name  = f"{uuid.uuid4().hex}_{file.filename}"
    saved_path = UPLOADS_DIR / safe_name

    with open(saved_path, "wb") as f:
        f.write(content)

    audit(
        "file_upload",
        username   = current_user["username"],
        user_id    = current_user["id"],
        detail     = f"Uploaded: {file.filename} ({len(content)} bytes)"
    )

    logger.info(
        "File uploaded: %s by %s (%d bytes)",
        file.filename, current_user["username"], len(content)
    )

    return {
        "filename":   file.filename,
        "saved_as":   safe_name,
        "file_path":  str(saved_path),
        "size_bytes": len(content)
    }


# ----------------------------------------------------------------------
# HELPERS — CACHE
# ----------------------------------------------------------------------

def _quick_extract_metadata(file_path: str) -> dict:
    """
    Read the first 4 KB of a log file and extract scenario name + batch date.
    Used to check the results cache before starting a full pipeline run.
    """
    import re
    from datetime import datetime as _dt
    try:
        with open(file_path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read(4096)
        pattern = re.compile(
            r'(?i)\b(Job\s*description|Current\s*business\s*date)\b\s*[:=]\s*(.*)'
        )
        result: dict = {}
        for m in pattern.finditer(text):
            key   = m.group(1).strip().lower().replace(" ", "_")
            value = m.group(2).strip()
            if key == "current_business_date":
                try:
                    value = str(_dt.strptime(value, "%d/%m/%Y").date())
                except ValueError:
                    pass
            result[key] = value
        return {
            "scenario_name": result.get("job_description"),
            "batch_date":    result.get("current_business_date"),
        }
    except Exception:
        return {}


# ----------------------------------------------------------------------
# ROUTES — PIPELINE JOBS
# ----------------------------------------------------------------------

@app.post("/api/jobs/run", tags=["Pipeline"])
async def run_job(
    request:          Request,
    background_tasks: BackgroundTasks,
    file_path:        str,
    force:            bool = False,
    current_user:     dict = Depends(get_current_analyst)
):
    """
    Starts a pipeline run for an uploaded log file.
    Returns job_id immediately — use WebSocket to track progress.

    LAYMAN: After uploading a file, React calls this to actually
    start the pipeline. We create a job record, start the pipeline
    in the background, and immediately return the job_id.
    React then opens a WebSocket to /api/ws/{job_id} to watch progress.

    We return immediately (don't wait for the pipeline to finish)
    because the pipeline takes minutes — the browser can't just wait.
    """
    # Validate file exists
    if not Path(file_path).exists():
        raise HTTPException(
            status_code = 400,
            detail      = "File not found — upload the file first"
        )

    # Cache check — skip if force=true
    if not force:
        meta = _quick_extract_metadata(file_path)
        s_name = meta.get("scenario_name")
        b_date = meta.get("batch_date")
        if s_name and b_date:
            cached = get_cached_job(s_name, b_date)
            if cached:
                return {
                    "cached":        True,
                    "cached_job_id": cached["job_id"],
                    "scenario_name": s_name,
                    "batch_date":    b_date,
                    "cached_at":     cached.get("completed_at"),
                }

    # Create job record
    job_id   = str(uuid.uuid4())
    filename = Path(file_path).name

    create_job(
        job_id       = job_id,
        user_id      = current_user["id"],
        log_filename = filename
    )

    # Create progress queue for this job
    progress_queue = asyncio.Queue()
    active_queues[job_id] = progress_queue

    # Start pipeline in background
    # LAYMAN: add_task says "run this after sending the response"
    # so the user gets the job_id immediately without waiting
    background_tasks.add_task(
        _run_pipeline_background,
        job_id       = job_id,
        user_id      = current_user["id"],
        username     = current_user["username"],
        log_file_path = file_path,
        queue        = progress_queue
    )

    audit(
        "pipeline_started",
        username = current_user["username"],
        user_id  = current_user["id"],
        job_id   = job_id,
        detail   = f"File: {filename}"
    )

    logger.info(
        "Job started: %s by %s for file %s",
        job_id, current_user["username"], filename
    )

    return {
        "job_id":  job_id,
        "status":  "started",
        "message": "Pipeline started — connect to WebSocket for live progress"
    }


async def _run_pipeline_background(
    job_id:        str,
    user_id:       int,
    username:      str,
    log_file_path: str,
    queue:         asyncio.Queue
):
    """
    Wrapper that runs the pipeline and broadcasts progress to WebSocket clients.

    LAYMAN: This runs in the background. It:
        1. Runs the pipeline (which puts messages in the queue)
        2. As messages arrive, broadcasts them to all connected WebSockets
    """
    try:
        # Start pipeline — it puts progress messages into queue
        pipeline_task = asyncio.create_task(
            run_pipeline(
                job_id         = job_id,
                user_id        = user_id,
                username       = username,
                log_file_path  = log_file_path,
                progress_queue = queue
            )
        )

        # Broadcast queue messages to WebSocket clients as they arrive
        while not pipeline_task.done():
            try:
                # Wait up to 0.5s for a message
                message = await asyncio.wait_for(queue.get(), timeout=0.5)
                await _broadcast(job_id, message)
            except asyncio.TimeoutError:
                continue

        # Drain remaining messages after pipeline completes
        while not queue.empty():
            message = queue.get_nowait()
            await _broadcast(job_id, message)

    except Exception as e:
        logger.error("Background pipeline error: %s", e)
        update_job_status(job_id, "failed", error_message=str(e))
        await _broadcast(job_id, {
            "event":   "job_failed",
            "message": str(e)
        })
    finally:
        # Clean up queue
        active_queues.pop(job_id, None)


@app.post("/api/jobs/batch", tags=["Pipeline"])
async def run_batch_jobs(
    body:             BatchRunRequest,
    background_tasks: BackgroundTasks,
    current_user:     dict = Depends(get_current_analyst)
):
    """
    Accepts multiple file paths and runs the pipeline for each one SEQUENTIALLY.
    All jobs are created immediately; the pipeline runs one at a time to avoid
    concurrent set_batch_date conflicts on the OFSAA server.
    Returns all job IDs so the UI can track them on the batch results page.
    """
    batch = []
    for file_path in body.file_paths:
        if not Path(file_path).exists():
            logger.warning("Batch: skipping missing file %s", file_path)
            continue
        job_id   = str(uuid.uuid4())
        filename = Path(file_path).name
        create_job(job_id=job_id, user_id=current_user["id"], log_filename=filename)
        queue = asyncio.Queue()
        active_queues[job_id] = queue
        batch.append({
            "job_id":    job_id,
            "filename":  filename,
            "file_path": file_path,
            "queue":     queue,
        })

    if not batch:
        raise HTTPException(status_code=400, detail="No valid files found in batch")

    background_tasks.add_task(
        _run_batch_sequential,
        batch    = batch,
        user_id  = current_user["id"],
        username = current_user["username"]
    )

    audit(
        "batch_started",
        username = current_user["username"],
        user_id  = current_user["id"],
        detail   = f"Batch of {len(batch)} jobs"
    )

    return {
        "jobs":  [{"job_id": j["job_id"], "filename": j["filename"]} for j in batch],
        "count": len(batch),
    }


async def _run_batch_sequential(batch: list[dict], user_id: int, username: str):
    """
    Runs each pipeline job one after another — waits for the previous job to
    complete (or fail) before starting the next. This prevents concurrent
    set_batch_date calls that would conflict on the OFSAA server.
    """
    for item in batch:
        logger.info(
            "Batch: starting job %s (%s)", item["job_id"], item["filename"]
        )
        await _run_pipeline_background(
            job_id        = item["job_id"],
            user_id       = user_id,
            username      = username,
            log_file_path = item["file_path"],
            queue         = item["queue"]
        )
        logger.info(
            "Batch: completed job %s — proceeding to next", item["job_id"]
        )


@app.post("/api/jobs/{job_id}/rerun", tags=["Pipeline"])
async def rerun_job(
    job_id:           str,
    background_tasks: BackgroundTasks,
    force:            bool = False,
    current_user:     dict = Depends(get_current_analyst)
):
    """Re-runs the pipeline for an existing job using the same log file."""
    original = get_job(job_id)
    if not original:
        raise HTTPException(status_code=404, detail="Job not found")
    if current_user["role"] != "admin" and original["user_id"] != current_user["id"]:
        raise HTTPException(status_code=403, detail="Access denied")

    log_file_path = UPLOADS_DIR / original["log_filename"]
    if not log_file_path.exists():
        raise HTTPException(status_code=404, detail="Original log file no longer available")

    # Cache check — skip if force=true
    if not force:
        s_name = original.get("scenario_name")
        b_date = original.get("batch_date")
        if s_name and b_date:
            cached = get_cached_job(s_name, b_date)
            if cached and cached["job_id"] != job_id:
                return {
                    "cached":        True,
                    "cached_job_id": cached["job_id"],
                    "scenario_name": s_name,
                    "batch_date":    b_date,
                    "cached_at":     cached.get("completed_at"),
                }

    new_job_id = str(uuid.uuid4())
    create_job(
        job_id       = new_job_id,
        user_id      = current_user["id"],
        log_filename = original["log_filename"]
    )

    progress_queue = asyncio.Queue()
    active_queues[new_job_id] = progress_queue

    background_tasks.add_task(
        _run_pipeline_background,
        job_id        = new_job_id,
        user_id       = current_user["id"],
        username      = current_user["username"],
        log_file_path = str(log_file_path),
        queue         = progress_queue
    )

    audit(
        "pipeline_rerun",
        username = current_user["username"],
        user_id  = current_user["id"],
        job_id   = new_job_id,
        detail   = f"Rerun of job: {job_id}"
    )

    return {"job_id": new_job_id, "status": "started"}


@app.get("/api/jobs", tags=["Pipeline"])
async def get_jobs(current_user: dict = Depends(get_current_analyst)):
    """
    Returns list of pipeline jobs.
    Analysts see only their own jobs.
    Admins see all jobs.
    """
    if current_user["role"] == "admin":
        jobs = list_jobs(limit=100)
    else:
        jobs = list_jobs(user_id=current_user["id"], limit=50)

    return {"jobs": jobs, "count": len(jobs)}


@app.get("/api/jobs/{job_id}", tags=["Pipeline"])
async def get_job_detail(
    job_id:       str,
    current_user: dict = Depends(get_current_analyst)
):
    """
    Returns full details of a specific job including all step statuses.
    Used by the UI to show the pipeline progress after page refresh.
    """
    job = get_job(job_id)

    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    # Analysts can only see their own jobs
    if current_user["role"] != "admin" and job["user_id"] != current_user["id"]:
        raise HTTPException(status_code=403, detail="Access denied")

    return job


# ----------------------------------------------------------------------
# WEBSOCKET — LIVE PROGRESS STREAMING
# ----------------------------------------------------------------------

@app.websocket("/api/ws/{job_id}")
async def websocket_progress(
    websocket: WebSocket,
    job_id:    str
):
    """
    WebSocket endpoint for live pipeline progress.

    LAYMAN: When the pipeline is running, React opens a WebSocket
    connection here. Every time a step starts, completes, or fails,
    a message is sent through this connection to the browser.
    React shows these messages as live updates in the UI — like
    watching a progress bar fill up in real time.

    Multiple browser tabs can connect to the same job_id
    and all get the same live updates.
    """
    await websocket.accept()

    # Register this connection
    if job_id not in active_connections:
        active_connections[job_id] = []
    active_connections[job_id].append(websocket)

    logger.info("WebSocket connected: job_id=%s", job_id)

    try:
        # Send current job state immediately on connect
        # (in case the user refreshed mid-run)
        job = get_job(job_id)
        if job:
            await websocket.send_json({
                "event":  "job_state",
                "job":    job
            })

        # Keep connection alive — wait for disconnect
        while True:
            try:
                # Wait for a ping from the client (keep-alive)
                await asyncio.wait_for(websocket.receive_text(), timeout=30)
            except asyncio.TimeoutError:
                # Send a ping to keep the connection alive
                await websocket.send_json({"event": "ping"})

    except WebSocketDisconnect:
        logger.info("WebSocket disconnected: job_id=%s", job_id)

    finally:
        # Remove this connection from active list
        if job_id in active_connections:
            active_connections[job_id] = [
                ws for ws in active_connections[job_id]
                if ws != websocket
            ]
            if not active_connections[job_id]:
                del active_connections[job_id]


async def _broadcast(job_id: str, message: dict):
    """
    Sends a message to all WebSocket clients watching a job.
    Removes dead connections automatically.
    """
    if job_id not in active_connections:
        return

    dead = []
    for ws in active_connections[job_id]:
        try:
            await ws.send_json(message)
        except Exception:
            dead.append(ws)

    # Remove dead connections
    for ws in dead:
        active_connections[job_id].remove(ws)


# ----------------------------------------------------------------------
# ROUTES — ADMIN: USER MANAGEMENT
# ----------------------------------------------------------------------

@app.get("/api/admin/users", tags=["Admin"])
async def admin_list_users(admin: dict = Depends(get_current_admin)):
    """Returns all users. Admin only."""
    return {"users": list_users()}


@app.post("/api/admin/users", tags=["Admin"])
async def admin_create_user(
    body:  CreateUserRequest,
    admin: dict = Depends(get_current_admin)
):
    """
    Creates a new user. Admin only.

    LAYMAN: Only admins can create new accounts.
    The password is hashed before storing — never stored in plain text.
    """
    password_hash = hash_password(body.password)

    try:
        user_id = create_user(
            username      = body.username,
            password_hash = password_hash,
            full_name     = body.full_name,
            email         = body.email,
            role          = body.role
        )
    except Exception as e:
        if "UNIQUE constraint failed" in str(e):
            raise HTTPException(
                status_code = 400,
                detail      = f"Username '{body.username}' already exists"
            )
        raise

    audit(
        "user_created",
        username = admin["username"],
        user_id  = admin["id"],
        detail   = f"Created user: {body.username} (role: {body.role})"
    )

    return {"message": f"User '{body.username}' created", "user_id": user_id}


@app.delete("/api/admin/users/{user_id}", tags=["Admin"])
async def admin_deactivate_user(
    user_id: int,
    admin:   dict = Depends(get_current_admin)
):
    """Deactivates a user account. Admin only."""
    if user_id == admin["id"]:
        raise HTTPException(
            status_code = 400,
            detail      = "Cannot deactivate your own account"
        )

    deactivate_user(user_id)

    audit(
        "user_deactivated",
        username = admin["username"],
        user_id  = admin["id"],
        detail   = f"Deactivated user_id: {user_id}"
    )

    return {"message": "User deactivated"}


# ----------------------------------------------------------------------
# ROUTES — ADMIN: AUDIT LOG
# ----------------------------------------------------------------------

@app.get("/api/admin/audit", tags=["Admin"])
async def admin_audit_log(
    limit: int   = 100,
    admin: dict  = Depends(get_current_admin)
):
    """Returns audit log entries. Admin only."""
    return {"entries": get_audit_log(limit=limit)}


# ----------------------------------------------------------------------
# GLOBAL EXCEPTION HANDLER
# ----------------------------------------------------------------------

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """
    Catches any unhandled exception and returns a clean JSON error.
    Prevents raw Python tracebacks leaking to the browser.

    LAYMAN: If something unexpected crashes, instead of showing a scary
    Python error to the user, we show a friendly "something went wrong"
    message and log the real error on the server.
    """
    logger.error("Unhandled exception: %s", exc, exc_info=True)
    return JSONResponse(
        status_code = 500,
        content     = {
            "detail":  "An internal error occurred",
            "message": "Please check the server logs"
        }
    )


# ----------------------------------------------------------------------
# ENTRY POINT
# ----------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn
    from config import API_HOST, API_PORT

    logger.info("Starting %s v%s", APP_NAME, APP_VERSION)

    uvicorn.run(
        "main:app",
        host     = API_HOST,
        port     = API_PORT,
        reload   = True,    # Auto-reload on code changes (dev only)
        # reload = False    # Use this in production
        log_level = "info"
    )
