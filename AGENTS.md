# OFSAA Scenario Debugger — Codebase Guide for AI Agents

## Project Overview
Full-stack AML diagnostic tool. Parses OFSAA log files, re-executes scenario SQL against Oracle, splits into CTEs, pinpoints why zero alerts were generated (date mismatch, missing data, threshold condition, JOIN failure).

**Stack:** FastAPI (Python 3.13) + React 19 (Vite) + SQLite + Oracle + SSH (Paramiko)

## Directory Structure

```
Scenario_Debugger/
├── backend/                    # Python FastAPI backend
│   ├── main.py                 # FastAPI app, all API routes (898 lines)
│   ├── config.py               # Central config loader (.env -> settings)
│   ├── auth.py                 # JWT auth, bcrypt, LDAP stub
│   ├── orchestrator.py         # 6-step pipeline orchestrator (async background)
│   ├── jobs.py                 # SQLite DB schema + CRUD (users, jobs, job_steps, audit_log)
│   ├── users.py                # Thin alias to jobs.py
│   ├── pipeline/               # The 6 diagnostic step scripts
│   │   ├── log_reader.py       # Step 1: Parse OFSAA log -> metadata + SQL queries
│   │   ├── set_batch_date.py   # Step 2: SSH into OFSAA server, set business date
│   │   ├── sql_executer.py     # Step 3: Run full SQL against Oracle, check alert count
│   │   ├── cte_parser.py       # Step 4: Split SQL into individual CTE .sql files
│   │   ├── cte_executer.py     # Step 5: Create Oracle views per CTE, find first empty one
│   │   ├── sql_diagnostics.py  # Step 6: Granular root-cause diagnosis (2888 lines)
│   │   ├── db_connect.py       # Oracle connection with retry
│   │   ├── path_manager.py     # Output directory creation/management
│   │   ├── run_logger.py       # Structured per-run log writer
│   │   └── scenario_config.py  # Scenario ID constants
│   ├── uploads/                # Uploaded log files
│   ├── outputs/                # Pipeline output per scenario
│   └── pdf_reports/            # Auto-generated PDF reports
├── frontend/                   # React + Vite
│   └── src/
│       ├── main.jsx            # React entry point
│       ├── App.jsx             # Root: BrowserRouter + AuthContext + routes
│       ├── api.js              # Axios API client + WebSocket helper
│       └── pages/
│           ├── Login.jsx       # Login form
│           ├── Dashboard.jsx   # Upload + run + job history
│           ├── Results.jsx     # Live pipeline progress via WebSocket
│           └── BatchResults.jsx# Batch run summary
├── deploy/                     # Production configs
│   ├── nginx/scenario-debugger.conf
│   └── systemd/scenario-debugger.service
├── start.ps1                   # Windows dev launcher
├── README.md                   # Full docs
└── README_DEPLOY.md            # Production deploy guide
```

## API Routes (all in `backend/main.py`)

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/auth/login` | Login -> JWT token |
| `GET` | `/api/auth/me` | Current user info |
| `POST` | `/api/upload` | Upload .log/.txt file |
| `POST` | `/api/jobs/run` | Start pipeline for uploaded file |
| `POST` | `/api/jobs/batch` | Sequential batch of runs |
| `POST` | `/api/jobs/{id}/rerun` | Re-run existing job |
| `GET` | `/api/jobs` | List jobs (analyst: own, admin: all) |
| `GET` | `/api/jobs/{id}` | Job detail + step statuses |
| `WS` | `/api/ws/{job_id}` | Live progress stream |
| `GET` | `/api/admin/users` | List users (admin only) |
| `POST` | `/api/admin/users` | Create user (admin only) |
| `DELETE` | `/api/admin/users/{id}` | Deactivate user (admin only) |
| `GET` | `/api/admin/audit` | Audit log (admin only) |
| `GET` | `/docs` | Swagger docs |

## Pipeline (6 steps in `backend/orchestrator.py`)

1. **Log Reader** (`pipeline/log_reader.py`) — Parse log -> scenario name, date, SQL
2. **Set Batch Date** (`pipeline/set_batch_date.py`) — SSH + set business date
3. **SQL Executer** (`pipeline/sql_executer.py`) — Run SQL against Oracle, check alert count
4. **CTE Parser** (`pipeline/cte_parser.py`) — Split SQL into individual CTEs
5. **CTE Executer** (`pipeline/cte_executer.py`) — Create Oracle views, find first empty CTE
6. **SQL Diagnostics** (`pipeline/sql_diagnostics.py`) — Granular diagnosis of failing CTE

## Database (SQLite, `backend/jobs.py`)

Tables: `users`, `jobs`, `job_steps`, `audit_log`
- DB path: `<APP_BASE_PATH>/db/scenario_debugger.db`
- Accessed via `get_db()` which returns `sqlite3.Connection`
- Functions: `create_user`, `get_user_by_username`, `create_job`, `get_job`, `list_jobs`, `update_job_status`, `update_step_status`, `get_cached_job`, `audit`, `get_audit_log`

## Key Backend Dependencies

- `fastapi` + `uvicorn[standard]` — Web + ASGI server
- `oracledb` — Oracle driver
- `paramiko` — SSH client
- `pyjwt` + `bcrypt` — Auth
- `sqlglot` — SQL parsing (CTE decomposition)
- `websockets` — Real-time progress
- `pydantic` — Validation
- `python-multipart` — File uploads

## Frontend Key Details

- **Auth:** `AuthContext` + `useAuth()` hook in `App.jsx`. JWT stored in memory, sent via Axios interceptor.
- **WebSocket:** `createProgressWebSocket(jobId, handlers)` in `api.js` — receives `step_started`, `step_completed`, `step_failed`, `job_completed`, `job_failed` events.
- **API client:** `api` (Axios instance) auto-attaches Bearer token. Separate modules: `authAPI`, `filesAPI`, `jobsAPI`, `adminAPI`.
- **Vite proxy:** `/api/*` -> `http://127.0.0.1:8000`, `/api/ws/*` -> `ws://127.0.0.1:8000`

## How to Run

```powershell
# Backend only
cd backend; uv run uvicorn main:app --host 127.0.0.1 --port 8000 --reload

# Frontend only
cd frontend; npm run dev

# Both (from root)
.\start.ps1
# OR: npm run dev (uses concurrently)
```

Backend: `http://127.0.0.1:8000` | Frontend: `http://localhost:5173`
Default login: `admin` / `changeme123`

## Config (`.env` at root)

Key vars: `APP_BASE_PATH`, `SECRET_KEY`, `DB_USERNAME`, `DB_PASSWORD`, `DB_DSN`, `SERVER_HOST`, `SERVER_USERNAME`, `SERVER_PASSWORD`, `MANTAS_BATCH_PATH`, `LDAP_ENABLED`, `JWT_EXPIRY_MINUTES`, `PIPELINE_TIMEOUT_SECONDS`, `CORS_ORIGINS`

## Conventions

- Backend: FastAPI async routes, Pydantic models, JWT dependency injection for auth
- Pipeline state passed as dict with keys: `step`, `status`, `result`, `error`, `job_id`
- WebSocket messages have `event` field: `step_started`, `step_completed`, `step_failed`, `job_completed`, `job_failed`, `ping`
- Frontend: functional components, React Router v7, Axios, CSS variables in `index.css`
- SQLite connection per request, simple functions (no ORM)
