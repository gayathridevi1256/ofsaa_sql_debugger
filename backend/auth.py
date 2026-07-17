"""
auth.py — Authentication for Scenario Debugger.

WHAT THIS FILE DOES:
    1. Verifies username and password on login
    2. Creates a JWT token after successful login
    3. Verifies JWT tokens on every protected API route
    4. Provides role-based access (analyst vs admin)
    5. LDAP stub — ready to enable later via config

LAYMAN'S EXPLANATION:
    Think of this file as the "security desk" at the bank entrance.

    LOGIN:
        You show your ID (username + password)
        Security checks it against the records (database or LDAP)
        If valid → you get a visitor badge (JWT token)
        If invalid → access denied

    EVERY OTHER REQUEST:
        You show your badge (JWT token in the request header)
        Security scans it — is it real? is it expired?
        If valid → you're let through
        If invalid/expired → 401 Unauthorized, please log in again

    JWT TOKEN:
        Just a long string like:
        eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoxfQ.abc123
        It contains your user ID and expiry time, cryptographically signed.
        Nobody can fake it without knowing the SECRET_KEY.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

from config import SECRET_KEY, JWT_ALGORITHM, JWT_EXPIRY_MINUTES, LDAP_ENABLED
from jobs import (
    get_user_by_username,
    get_user_by_id,
    update_last_login,
    audit
)

logger = logging.getLogger(__name__)

# ----------------------------------------------------------------------
# OAUTH2 SCHEME
# ----------------------------------------------------------------------
# This tells FastAPI where to find the JWT token in incoming requests.
# It looks for:  Authorization: Bearer <token>
# in the request headers.
#
# LAYMAN: This is how your visitor badge gets checked at each door.
# Every API request must include the token in its headers.
# The tokenUrl is the login endpoint that issues tokens.

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


# ----------------------------------------------------------------------
# PASSWORD HASHING
# ----------------------------------------------------------------------

def hash_password(plain_password: str) -> str:
    """
    Hashes a plain text password using bcrypt.
    NEVER store plain text passwords — always hash first.

    LAYMAN: bcrypt turns "mypassword123" into something like
    "$2b$12$abc...xyz" — a scrambled version that can't be reversed.
    We store the scrambled version. When someone logs in, we scramble
    their attempt and compare the scrambled versions.
    """
    return bcrypt.hashpw(
        plain_password.encode("utf-8"),
        bcrypt.gensalt()
    ).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Checks if a plain text password matches a stored hash.
    Returns True if they match, False otherwise.
    """
    return bcrypt.checkpw(
        plain_password.encode("utf-8"),
        hashed_password.encode("utf-8")
    )


# ----------------------------------------------------------------------
# JWT TOKEN CREATION
# ----------------------------------------------------------------------

def create_access_token(user_id: int, username: str, role: str) -> str:
    """
    Creates a signed JWT token for a successfully authenticated user.
    Token expires after JWT_EXPIRY_MINUTES (default 8 hours).

    LAYMAN: This creates the "visitor badge" after a successful login.
    The badge contains:
        - who you are (user_id, username, role)
        - when it expires
    It's signed with SECRET_KEY so nobody can forge it.
    """
    expiry = datetime.now(timezone.utc) + timedelta(minutes=JWT_EXPIRY_MINUTES)

    payload = {
        "sub":      str(user_id),   # subject — who this token is for
        "username": username,
        "role":     role,
        "exp":      expiry,         # expiry — when the badge expires
        "iat":      datetime.now(timezone.utc)  # issued at
    }

    token = jwt.encode(payload, SECRET_KEY, algorithm=JWT_ALGORITHM)
    logger.debug("Token created for user: %s (expires: %s)", username, expiry)
    return token


def decode_access_token(token: str) -> dict:
    """
    Decodes and validates a JWT token.
    Raises an exception if the token is invalid or expired.

    Returns the payload dict containing user_id, username, role.
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[JWT_ALGORITHM])
        return payload

    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session expired — please log in again",
            headers={"WWW-Authenticate": "Bearer"}
        )

    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token — please log in again",
            headers={"WWW-Authenticate": "Bearer"}
        )


# ----------------------------------------------------------------------
# LOGIN
# ----------------------------------------------------------------------

def authenticate_user(username: str, password: str,
                      ip_address: str = None) -> dict:
    """
    Authenticates a user by username and password.

    Flow:
        1. If LDAP is enabled → try LDAP first, fall back to local
        2. If LDAP is disabled → check local database only
        3. On success → update last_login, write audit log, return user dict
        4. On failure → write audit log, raise 401

    Returns the user dict on success.
    Raises HTTPException 401 on failure.
    """

    # ------------------------------------------------------------------
    # LDAP authentication (if enabled in config)
    # ------------------------------------------------------------------
    if LDAP_ENABLED:
        ldap_user = _authenticate_ldap(username, password)
        if ldap_user:
            audit(
                "user_login",
                username=username,
                user_id=ldap_user.get("id"),
                detail="LDAP authentication",
                ip_address=ip_address
            )
            return ldap_user
        # If LDAP fails, fall through to local auth as backup
        logger.warning("LDAP auth failed for %s — trying local", username)

    # ------------------------------------------------------------------
    # Local database authentication
    # ------------------------------------------------------------------
    user = get_user_by_username(username)

    if not user:
        logger.warning("Login failed — user not found: %s from %s", username, ip_address)
        audit(
            "user_login_failed",
            username=username,
            detail="User not found",
            ip_address=ip_address
        )
        # IMPORTANT: same error message for "not found" and "wrong password"
        # Never tell an attacker which one it was
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password"
        )

    if not verify_password(password, user["password_hash"]):
        logger.warning("Login failed — wrong password: %s from %s", username, ip_address)
        audit(
            "user_login_failed",
            username=username,
            user_id=user["id"],
            detail="Wrong password",
            ip_address=ip_address
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username or password"
        )

    # Success
    update_last_login(user["id"])
    audit(
        "user_login",
        username=username,
        user_id=user["id"],
        detail="Local authentication",
        ip_address=ip_address
    )
    logger.info("Login successful: %s from %s", username, ip_address)
    return user


# ----------------------------------------------------------------------
# FASTAPI DEPENDENCY FUNCTIONS
# ----------------------------------------------------------------------
# These are used with FastAPI's Depends() system.
#
# LAYMAN: In FastAPI, you add these to your route functions like this:
#
#   @app.get("/api/jobs")
#   def get_jobs(current_user = Depends(get_current_user)):
#       # current_user is the logged-in user dict
#       # FastAPI automatically checks the token before running this
#
# If the token is missing or invalid, FastAPI returns 401 automatically.
# You don't need to write any checking code in the route itself.

async def get_current_user(token: str = Depends(oauth2_scheme)) -> dict:
    """
    FastAPI dependency — extracts and validates the current user from JWT.
    Use this on any route that requires a logged-in user.

    USAGE:
        @app.get("/api/jobs")
        def get_jobs(user = Depends(get_current_user)):
            return list_jobs(user_id=user["id"])
    """
    payload = decode_access_token(token)

    user_id = int(payload.get("sub"))
    user    = get_user_by_id(user_id)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User no longer exists"
        )

    return user


async def get_current_analyst(
    current_user: dict = Depends(get_current_user)
) -> dict:
    """
    FastAPI dependency — requires analyst OR admin role.
    Use on routes that any logged-in user can access.
    """
    if current_user["role"] not in ("analyst", "admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Insufficient permissions"
        )
    return current_user


async def get_current_admin(
    current_user: dict = Depends(get_current_user)
) -> dict:
    """
    FastAPI dependency — requires admin role only.
    Use on routes like user management and audit log viewing.

    USAGE:
        @app.get("/api/admin/users")
        def list_users(admin = Depends(get_current_admin)):
            # only admins reach here
    """
    if current_user["role"] != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return current_user


# ----------------------------------------------------------------------
# LDAP STUB  (enabled via LDAP_ENABLED=true in .env)
# ----------------------------------------------------------------------

def _authenticate_ldap(username: str, password: str) -> Optional[dict]:
    """
    Authenticates against an LDAP server (e.g. Active Directory).
    Returns a user dict on success, None on failure.

    TO ENABLE:
        1. Set LDAP_ENABLED=true in .env
        2. Fill in LDAP_SERVER, LDAP_BASE_DN, LDAP_BIND_DN, LDAP_BIND_PASSWORD
        3. pip install python-ldap

    LAYMAN: LDAP is your bank's central user directory — the same system
    that controls Windows logins. When enabled, this lets staff log in
    with their existing bank credentials instead of a separate password.
    """
    try:
        from config import LDAP_SERVER, LDAP_BASE_DN, LDAP_BIND_DN, LDAP_BIND_PASS
        import ldap

        conn = ldap.initialize(LDAP_SERVER)
        conn.set_option(ldap.OPT_REFERRALS, 0)
        conn.set_option(ldap.OPT_NETWORK_TIMEOUT, 10)

        # Bind with service account to search for the user
        conn.simple_bind_s(LDAP_BIND_DN, LDAP_BIND_PASS)

        # Search for user in directory
        search_filter = f"(sAMAccountName={username})"
        results = conn.search_s(
            LDAP_BASE_DN,
            ldap.SCOPE_SUBTREE,
            search_filter,
            ["cn", "mail", "memberOf"]
        )

        if not results:
            return None

        user_dn, attrs = results[0]

        # Try to bind as the user to verify password
        conn.simple_bind_s(user_dn, password)

        # Return a user-like dict (same shape as local DB user)
        return {
            "id":       None,
            "username": username,
            "full_name": attrs.get("cn", [b""])[0].decode(),
            "email":    attrs.get("mail", [b""])[0].decode(),
            "role":     "analyst",   # default role for LDAP users
            "is_active": 1
        }

    except Exception as e:
        logger.warning("LDAP authentication error: %s", e)
        return None
