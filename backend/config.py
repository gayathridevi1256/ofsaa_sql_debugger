"""
config.py — Central configuration for Scenario Debugger.

All settings are loaded from environment variables or a .env file.
Every other file imports from here — never hardcode paths or secrets elsewhere.

HOW TO USE:
    1. Copy .env.example to .env
    2. Set APP_BASE_PATH to your desired base directory
    3. Everything else is created automatically on first run

LAYMAN'S EXPLANATION:
    This file is like the "settings page" of the application.
    Instead of hardcoding paths and secrets inside every Python file,
    we store them here in one place. If something changes (like the
    base path), you change it in ONE place and everything updates.
"""

import os
import logging
from pathlib import Path
from dotenv import load_dotenv

# ----------------------------------------------------------------------
# LOAD .env FILE
# ----------------------------------------------------------------------
# dotenv reads your .env file and makes all variables available
# via os.getenv(). If .env doesn't exist, it silently continues
# (useful when environment variables are set directly on the server).

load_dotenv()

# ----------------------------------------------------------------------
# BASE PATH  (the only path the user needs to set)
# ----------------------------------------------------------------------

# Read APP_BASE_PATH from .env — default to /opt/scenario-debugger
# on Linux or C:/scenario-debugger on Windows if not set.
_default_base = (
    "C:/scenario-debugger"
    if os.name == "nt"          # nt = Windows
    else "/opt/scenario-debugger"
)

APP_BASE_PATH = Path(os.getenv("APP_BASE_PATH", _default_base))

# ----------------------------------------------------------------------
# ALL PATHS DERIVED FROM BASE  (auto-created on startup)
# ----------------------------------------------------------------------

# Where users upload OFSAA log files
UPLOADS_DIR     = APP_BASE_PATH / "uploads"

# Where pipeline outputs are stored (metadata, parsed CTEs, etc.)
OUTPUTS_DIR     = APP_BASE_PATH / "outputs"

# Application log files (errors, audit trail)
LOGS_DIR        = APP_BASE_PATH / "logs"

# SQLite database (users, job history, audit log)
DB_DIR          = APP_BASE_PATH / "db"
DB_PATH         = DB_DIR / "scenario_debugger.db"

# ----------------------------------------------------------------------
# SECURITY SETTINGS
# ----------------------------------------------------------------------

# Secret key for signing JWT tokens.
# IMPORTANT: Change this in .env before deploying — never use the default.
# Generate a strong key with: python -c "import secrets; print(secrets.token_hex(32))"
SECRET_KEY      = os.getenv("SECRET_KEY", "CHANGE_ME_BEFORE_DEPLOYING_USE_SECRETS_TOKEN_HEX")

# JWT algorithm — HS256 is standard for internal apps
JWT_ALGORITHM   = "HS256"

# How long a login token stays valid (in minutes)
# 480 minutes = 8 hours (a full work day)
JWT_EXPIRY_MINUTES = int(os.getenv("JWT_EXPIRY_MINUTES", "480"))

# ----------------------------------------------------------------------
# APPLICATION SETTINGS
# ----------------------------------------------------------------------

# App name shown in the UI and logs
APP_NAME        = os.getenv("APP_NAME", "OFSAA Scenario Debugger")

# App version
APP_VERSION     = "1.0.0"

# Host and port FastAPI listens on
# 0.0.0.0 means "accept connections from any network interface"
# Change to 127.0.0.1 if Nginx is on the same machine (recommended)
API_HOST        = os.getenv("API_HOST", "127.0.0.1")
API_PORT        = int(os.getenv("API_PORT", "8000"))

# Allowed origins for CORS (which domains can call the API)
# In production this should be your exact server domain
# e.g. "https://scenario-debugger.yourbank.com"
CORS_ORIGINS    = os.getenv(
    "CORS_ORIGINS",
    "http://localhost:5173,http://localhost:3000"   # Vite + CRA dev defaults
).split(",")

# Max upload file size in MB
MAX_UPLOAD_MB   = int(os.getenv("MAX_UPLOAD_MB", "50"))

# Max log file size in bytes (used by log_reader.py)
MAX_SQL_FILE_BYTES = int(os.getenv("MAX_SQL_FILE_BYTES", str(10 * 1024 * 1024)))

# ----------------------------------------------------------------------
# PIPELINE SETTINGS
# ----------------------------------------------------------------------

# Path to the pipeline scripts folder
# Defaults to a "pipeline" folder next to this config file
PIPELINE_DIR    = Path(os.getenv(
    "PIPELINE_DIR",
    str(Path(__file__).parent.parent / "pipeline")
))

# How long (seconds) to wait before killing a hung pipeline step
PIPELINE_TIMEOUT_SECONDS = int(os.getenv("PIPELINE_TIMEOUT_SECONDS", "300"))

# ----------------------------------------------------------------------
# LOGGING SETTINGS
# ----------------------------------------------------------------------

LOG_LEVEL       = os.getenv("LOG_LEVEL", "INFO")

# ----------------------------------------------------------------------
# LDAP SETTINGS  (disabled for now — enable later in .env)
# ----------------------------------------------------------------------
# To enable LDAP:
#   1. Set LDAP_ENABLED=true in .env
#   2. Fill in LDAP_SERVER, LDAP_BASE_DN, LDAP_BIND_DN, LDAP_BIND_PASSWORD

LDAP_ENABLED    = os.getenv("LDAP_ENABLED", "false").lower() == "true"
LDAP_SERVER     = os.getenv("LDAP_SERVER", "")           # e.g. ldap://your-bank-ldap:389
LDAP_BASE_DN    = os.getenv("LDAP_BASE_DN", "")           # e.g. dc=yourbank,dc=com
LDAP_BIND_DN    = os.getenv("LDAP_BIND_DN", "")           # service account DN
LDAP_BIND_PASS  = os.getenv("LDAP_BIND_PASSWORD", "")


# ----------------------------------------------------------------------
# DIRECTORY BOOTSTRAP
# ----------------------------------------------------------------------

def create_app_directories():
    """
    Creates all required application directories if they don't exist.
    Called once at application startup.

    LAYMAN: Think of this as the app "setting up its filing cabinet"
    the first time it runs. If the folders already exist, nothing happens.
    """
    dirs = [UPLOADS_DIR, OUTPUTS_DIR, LOGS_DIR, DB_DIR]

    for directory in dirs:
        directory.mkdir(parents=True, exist_ok=True)

    return dirs


# ----------------------------------------------------------------------
# LOGGING SETUP
# ----------------------------------------------------------------------

def setup_logging():
    """
    Configures application-wide logging.
    Logs go to both the console AND a rotating file in LOGS_DIR.

    LAYMAN: This sets up the app's "diary" — every important event
    gets written to a log file so you can look back and see what happened.
    """
    log_file = LOGS_DIR / "app.log"

    # Ensure log directory exists before setting up file handler
    LOGS_DIR.mkdir(parents=True, exist_ok=True)

    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        handlers=[
            # Print to terminal
            logging.StreamHandler(),
            # Write to file (max 10MB, keep 5 old files)
            logging.handlers.RotatingFileHandler(
                log_file,
                maxBytes=10 * 1024 * 1024,   # 10 MB
                backupCount=5,
                encoding="utf-8"
            )
        ]
    )

    logger = logging.getLogger(__name__)
    logger.info("Logging initialised — level: %s", LOG_LEVEL)
    logger.info("App base path: %s", APP_BASE_PATH)
    return logger


# ----------------------------------------------------------------------
# SETTINGS SUMMARY  (printed at startup for easy verification)
# ----------------------------------------------------------------------

def print_config_summary():
    """
    Prints a summary of current configuration at startup.
    Helps catch misconfiguration early.
    SECRET_KEY is intentionally masked.
    """
    key_status = "*** SET ***" if SECRET_KEY != "CHANGE_ME_BEFORE_DEPLOYING_USE_SECRETS_TOKEN_HEX" else "[!] NOT SET - change in .env"
    print("\n" + "=" * 60)
    print(f"  {APP_NAME}  v{APP_VERSION}")
    print("=" * 60)
    print(f"  Base path     : {APP_BASE_PATH}")
    print(f"  Uploads       : {UPLOADS_DIR}")
    print(f"  Outputs       : {OUTPUTS_DIR}")
    print(f"  Database      : {DB_PATH}")
    print(f"  API           : http://{API_HOST}:{API_PORT}")
    print(f"  CORS origins  : {CORS_ORIGINS}")
    print(f"  JWT expiry    : {JWT_EXPIRY_MINUTES} minutes")
    print(f"  LDAP enabled  : {LDAP_ENABLED}")
    print(f"  Secret key    : {key_status}")
    print(f"  Log level     : {LOG_LEVEL}")
    print("=" * 60 + "\n")


# Need this for RotatingFileHandler
import logging.handlers
