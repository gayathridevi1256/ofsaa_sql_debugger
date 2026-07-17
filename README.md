# OFSAA Scenario Debugger

A full-stack diagnostic tool for AML (Anti-Money Laundering) scenario analysts. When an OFSAA scenario runs but generates no alerts, this tool automatically diagnoses why — parsing the log file, re-executing the SQL against Oracle, splitting it into CTEs, and pinpointing the exact condition that is filtering out all rows.

---

## What It Does

OFSAA AML scenarios are complex SQL pipelines. When alerts stop generating, the root cause is almost always a CTE (Common Table Expression) returning zero rows due to a date mismatch, missing data, or a threshold condition. Manually tracing this takes hours.

This tool automates that investigation in six steps:

| Step | Name | What It Does |
|------|------|--------------|
| 1 | **Log Reader** | Parses the OFSAA log file — extracts scenario name, business date, threshold set ID, and embedded SQL |
| 2 | **Set Batch Date** | SSHs into the OFSAA server and sets the business date to match the log |
| 3 | **SQL Executer** | Runs the full scenario SQL against Oracle — if alerts are found, stops here (scenario is working) |
| 4 | **CTE Parser** | Splits the scenario SQL into individual CTEs and saves each as a separate `.sql` file |
| 5 | **CTE Executer** | Creates Oracle views for each CTE in order, validates row counts — stops at the first empty CTE |
| 6 | **SQL Diagnostics** | Runs granular diagnosis on the failing CTE — identifies the exact JOIN condition, filter, or date range causing zero rows |

Results are streamed live to the browser via WebSocket as each step completes.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Browser (React)                       │
│  Login → Upload .log file → Run → Live progress → Results   │
└───────────────────┬──────────────────────────────────────────┘
                    │  HTTP + WebSocket
┌───────────────────▼──────────────────────────────────────────┐
│              FastAPI Backend (Python 3.13)                   │
│  /api/auth/login  →  JWT authentication                      │
│  /api/upload      →  Save log file                           │
│  /api/jobs/run    →  Start pipeline (background task)        │
│  /api/ws/{job_id} →  WebSocket: stream live progress         │
│  /api/jobs        →  Job history                             │
│  /api/admin/*     →  User management, audit log              │
└───────┬───────────────────────────────────┬──────────────────┘
        │                                   │
┌───────▼───────┐                  ┌────────▼────────┐
│  SQLite DB    │                  │  Pipeline       │
│  users        │                  │  (6 Python      │
│  jobs         │                  │   scripts)      │
│  job_steps    │                  └────────┬────────┘
│  audit_log    │                           │
└───────────────┘               ┌───────────┴───────────┐
                                │                       │
                        ┌───────▼──────┐    ┌──────────▼──────┐
                        │  Oracle DB   │    │  OFSAA Server   │
                        │  (scenario   │    │  (SSH — set     │
                        │   SQL)       │    │   batch date)   │
                        └──────────────┘    └─────────────────┘
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | React 18, Vite, React Router |
| Backend | FastAPI, Uvicorn, Python 3.13 |
| Database | SQLite (job tracking, users, audit log) |
| External DB | Oracle (via `oracledb`) |
| SSH | Paramiko (set batch date on OFSAA server) |
| Auth | JWT (PyJWT), bcrypt password hashing |
| Real-time | WebSocket (asyncio) |
| Deployment | Nginx reverse proxy, systemd service |
| Package mgmt | `uv` (backend), `npm` (frontend) |

---

## Project Structure

```
scenario-debugger/
├── backend/
│   ├── main.py          # FastAPI app — all API routes
│   ├── pipeline.py      # 6-step pipeline orchestrator
│   ├── jobs.py          # SQLite DB schema + job/user/audit helpers
│   ├── auth.py          # JWT creation, bcrypt verification, user auth
│   ├── config.py        # All settings (loaded from .env)
│   └── users.py         # User management helpers
│
├── pipeline/            # The 6 diagnostic scripts
│   ├── log_reader.py    # Step 1: parse OFSAA log
│   ├── set_batch_date.py # Step 2: SSH + set date
│   ├── sql_executer.py  # Step 3: run full SQL
│   ├── cte_parser.py    # Step 4: split SQL into CTEs
│   ├── cte_executer.py  # Step 5: run each CTE, find empty one
│   ├── sql_diagnostics.py # Step 6: diagnose failing CTE
│   ├── db_connect.py    # Oracle connection helper
│   └── path_manager.py  # Output directory management
│
├── frontend/
│   └── src/
│       ├── App.jsx          # Routing + auth context
│       ├── api.js           # All API calls to backend
│       └── pages/
│           ├── Login.jsx        # Login page
│           ├── Dashboard.jsx    # Upload + run + job history
│           ├── Results.jsx      # Live pipeline progress + results
│           └── BatchResults.jsx # Batch run tracking
│
├── nginx/
│   └── scenario-debugger.conf  # Nginx reverse proxy config
├── systemd/
│   └── scenario-debugger.service # systemd service file
├── db/                   # SQLite database (auto-created)
├── uploads/              # Uploaded log files (auto-created)
├── outputs/              # Pipeline outputs per scenario (auto-created)
├── logs/                 # App logs (auto-created)
├── pyproject.toml        # Python dependencies
├── start.ps1             # Windows dev launcher
└── README_DEPLOY.md      # Linux production deployment guide
```

---

## Quick Start (Windows — Development)

### Prerequisites

- Python 3.13+
- Node.js 18+
- [`uv`](https://docs.astral.sh/uv/) — `pip install uv` or `winget install astral-sh.uv`
- Oracle Instant Client (for `oracledb`)
- Network access to your OFSAA Oracle DB and OFSAA server (SSH)

### 1. Configure environment

```bash
cd backend
copy .env.example .env
# Edit .env with your Oracle credentials, SSH details, etc.
```

Minimum required `.env` settings:

```env
APP_BASE_PATH=C:/scenario-debugger/data
SECRET_KEY=<generate: python -c "import secrets; print(secrets.token_hex(32))">

# Oracle DB
DB_USERNAME=your_oracle_user
DB_PASSWORD=your_oracle_password
DB_DSN=your_oracle_dsn

# OFSAA server SSH
SERVER_HOST=your_ofsaa_server_ip
SERVER_USERNAME=your_ssh_user
SERVER_PASSWORD=your_ssh_password
MANTAS_BATCH_PATH=/path/to/mantas/batch/on/server
```

### 2. Install backend dependencies

```bash
cd backend
uv sync
```

### 3. Install frontend dependencies

```bash
cd frontend
npm install
```

### 4. Start both servers

```powershell
# From the project root:
.\start.ps1
```

This opens two terminal windows:
- **Backend**: `http://127.0.0.1:8000` (FastAPI + Uvicorn, hot-reload enabled)
- **Frontend**: `http://localhost:5173` (Vite dev server)

Open `http://localhost:5173` in your browser.

**Default login:** `admin` / `changeme123` — change this immediately.

---

## Usage

1. **Login** with your credentials at `/login`
2. **Upload** an OFSAA scenario log file (`.log` or `.txt`, max 50 MB) by dragging onto the upload zone or clicking to browse
3. **Click Run** — the pipeline starts in the background; you are redirected to the Results page
4. **Watch live progress** — each of the 6 steps updates in real time via WebSocket
5. **Read the diagnosis** — when the pipeline completes, the root cause is displayed:
   - If alerts were generated: confirms the scenario is working
   - If no alerts: shows which CTE returned zero rows and exactly why (missing data, date mismatch, threshold condition, etc.)
6. **Batch runs** — upload multiple log files and run all scenarios sequentially via the batch endpoint

---

## API Reference

All endpoints require a Bearer JWT token in the `Authorization` header (except `/api/auth/login`).

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/auth/login` | Login — returns JWT token |
| `GET` | `/api/auth/me` | Get current user info |
| `POST` | `/api/upload` | Upload a `.log` or `.txt` file |
| `POST` | `/api/jobs/run` | Start pipeline for an uploaded file |
| `POST` | `/api/jobs/batch` | Start sequential batch of pipeline runs |
| `POST` | `/api/jobs/{id}/rerun` | Re-run an existing job |
| `GET` | `/api/jobs` | List jobs (analyst: own jobs; admin: all) |
| `GET` | `/api/jobs/{id}` | Get full job detail + step statuses |
| `WS` | `/api/ws/{job_id}` | WebSocket: live pipeline progress stream |
| `GET` | `/api/admin/users` | List all users (admin only) |
| `POST` | `/api/admin/users` | Create a user (admin only) |
| `DELETE` | `/api/admin/users/{id}` | Deactivate a user (admin only) |
| `GET` | `/api/admin/audit` | Get audit log (admin only) |
| `GET` | `/docs` | Interactive Swagger API docs |

### WebSocket events

The `/api/ws/{job_id}` stream sends JSON messages with an `event` field:

| Event | Meaning |
|-------|---------|
| `job_state` | Sent on connect — current job snapshot |
| `step_started` | A pipeline step has begun |
| `step_completed` | A step finished successfully |
| `step_failed` | A step failed with an error |
| `job_completed` | All steps done — includes root cause and results |
| `job_failed` | Pipeline stopped due to a fatal error |
| `ping` | Keep-alive heartbeat |

---

## Configuration Reference

All settings live in `backend/.env`. The backend reads them via `config.py`.

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_BASE_PATH` | `C:/scenario-debugger` | Root directory for uploads, outputs, db, logs |
| `SECRET_KEY` | (must set) | JWT signing secret — generate with `secrets.token_hex(32)` |
| `JWT_EXPIRY_MINUTES` | `480` | Token lifetime (8 hours) |
| `API_HOST` | `127.0.0.1` | FastAPI listen address |
| `API_PORT` | `8000` | FastAPI listen port |
| `CORS_ORIGINS` | `http://localhost:5173` | Comma-separated allowed origins |
| `MAX_UPLOAD_MB` | `50` | Maximum upload file size |
| `PIPELINE_TIMEOUT_SECONDS` | `300` | Max time per pipeline step |
| `LOG_LEVEL` | `INFO` | Logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`) |
| `DB_USERNAME` | (required) | Oracle database username |
| `DB_PASSWORD` | (required) | Oracle database password |
| `DB_DSN` | (required) | Oracle DSN / connection string |
| `SERVER_HOST` | (required) | OFSAA server IP/hostname for SSH |
| `SERVER_USERNAME` | (required) | SSH username |
| `SERVER_PASSWORD` | (required) | SSH password |
| `MANTAS_BATCH_PATH` | (required) | Path to Mantas batch script on OFSAA server |
| `LDAP_ENABLED` | `false` | Enable LDAP authentication |
| `LDAP_SERVER` | — | LDAP server URL (e.g. `ldap://bankldap:389`) |
| `LDAP_BASE_DN` | — | LDAP base DN |
| `LDAP_BIND_DN` | — | LDAP service account DN |
| `LDAP_BIND_PASSWORD` | — | LDAP service account password |

---

## User Roles

| Role | Permissions |
|------|------------|
| `admin` | Full access — user management, audit log, all jobs |
| `analyst` | Can upload files, run pipelines, view own job results |

Users are created by an admin via the UI (Admin panel) or the API. Passwords are hashed with bcrypt and never stored in plain text.

---

## Database Schema

SQLite database at `<APP_BASE_PATH>/db/scenario_debugger.db`.

**`users`** — authentication and roles  
**`jobs`** — every pipeline run (status, scenario name, batch date, root cause, result JSON)  
**`job_steps`** — per-step status for each job (running / completed / failed + output)  
**`audit_log`** — immutable record of every action (logins, uploads, pipeline runs, user changes)

---

## Output Files

For each pipeline run, outputs are written to `<APP_BASE_PATH>/outputs/<ScenarioName>/`:

```
outputs/
└── SCENARIO_NAME/
    ├── metadata.json          # Extracted log metadata
    ├── extracted_queries/
    │   └── dataset_query_*.sql  # Full scenario SQL from the log
    └── parsed_ctes/
        ├── cte_01_<name>.sql    # Individual CTEs
        ├── cte_02_<name>.sql
        ├── ...
        └── final_query.sql      # The final SELECT after all CTEs
```

---

## Production Deployment (Linux)

See [README_DEPLOY.md](README_DEPLOY.md) for the full step-by-step guide covering:

- Creating a dedicated service user
- Configuring `.env` for production
- Installing Python and Node dependencies
- Building the React frontend
- SSL certificate setup (bank CA or self-signed)
- Nginx reverse proxy configuration
- systemd service setup (auto-start on boot)
- Log monitoring and troubleshooting

**Quick summary:**

```bash
# Backend runs as a systemd service
sudo systemctl start scenario-debugger

# Nginx proxies HTTPS → FastAPI + serves React static files
# https://scenario-debugger.yourbank.com → http://127.0.0.1:8000

# Check status
sudo systemctl status scenario-debugger
curl http://127.0.0.1:8000/api/health
```

---

## Security Notes

- JWT tokens expire after 8 hours (configurable via `JWT_EXPIRY_MINUTES`)
- Passwords are hashed with bcrypt — never stored in plain text
- The `.env` file should be `chmod 600` and owned by the service user
- Change `SECRET_KEY` from the default before deploying
- Change the default `admin / changeme123` password immediately after first login
- In production, set `CORS_ORIGINS` to your exact domain (not `*`)
- The audit log records every login attempt, upload, and pipeline run
- File uploads are restricted to `.log` and `.txt` extensions, max 50 MB

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Backend won't start | Check `.env` exists in `backend/` and all required variables are set |
| Oracle connection fails | Verify `DB_USERNAME`, `DB_PASSWORD`, `DB_DSN` and that Oracle Instant Client is installed |
| SSH step fails | Verify `SERVER_HOST`, `SERVER_USERNAME`, `SERVER_PASSWORD`, and `MANTAS_BATCH_PATH` |
| No SQL found in log | The log file may be truncated or from a different OFSAA version — check the file manually |
| WebSocket disconnects | Ensure Nginx has `Upgrade` and `Connection` proxy headers set (see `nginx/` config) |
| Login fails (correct password) | `SECRET_KEY` is not set in `.env` |
| File upload 413 error | Increase `MAX_UPLOAD_MB` in `.env` and `client_max_body_size` in nginx config |
| Pipeline cached result returned | Pass `?force=true` to `/api/jobs/run` to skip the cache |

---

## License

Internal tool — not for public distribution.
