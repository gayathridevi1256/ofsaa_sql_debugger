/**
 * Login.jsx — Login page for Scenario Debugger.
 *
 * LAYMAN'S EXPLANATION:
 *   This is the first page users see.
 *   They enter username + password, click Login,
 *   and if correct they're taken to the Dashboard.
 *
 *   What happens on submit:
 *     1. Calls authAPI.login() from api.js
 *     2. Gets back a JWT token
 *     3. Stores it via login() from AuthContext
 *     4. React Router redirects to Dashboard
 */

import React, { useState } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { useAuth } from "../App";
import { authAPI, getErrorMessage } from "../api";

export default function Login() {
  const { login }    = useAuth();
  const navigate     = useNavigate();
  const location     = useLocation();
  const from         = location.state?.from?.pathname || "/";

  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState("");
  const [showPass, setShowPass] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!username.trim() || !password.trim()) {
      setError("Please enter username and password");
      return;
    }

    setLoading(true);
    setError("");

    try {
      const data = await authAPI.login(username, password);
      login(data);
      navigate(from, { replace: true });
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={styles.page}>
      {/* Background glow effect */}
      <div style={styles.bgGlow} />

      <div style={styles.container} className="animate-fade-in">

        {/* Logo / Header */}
        <div style={styles.header}>
          <div style={styles.logoMark}>
            <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
              <path d="M4 8h24M4 16h16M4 24h20" stroke="#2563eb"
                strokeWidth="2.5" strokeLinecap="round"/>
              <circle cx="26" cy="24" r="4" fill="#2563eb" opacity="0.25"
                stroke="#2563eb" strokeWidth="1.5"/>
            </svg>
          </div>
          <h1 style={styles.title}>Scenario Debugger</h1>
          <p style={styles.subtitle}>OFSAA AML Diagnostic Platform</p>
        </div>

        {/* Login Card */}
        <div style={styles.card}>
          <div style={styles.cardHeader}>
            <span style={styles.cardLabel}>SECURE ACCESS</span>
            <h2 style={styles.cardTitle}>Sign In</h2>
          </div>

          {/* Error */}
          {error && (
            <div className="alert alert-error animate-fade-in" style={{ marginBottom: 20 }}>
              <span>⚠</span>
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} style={styles.form}>

            {/* Username */}
            <div style={styles.field}>
              <label className="label">Username</label>
              <div style={styles.inputWrapper}>
                <span style={styles.inputIcon}>
                  <UserIcon />
                </span>
                <input
                  className="input"
                  style={styles.inputWithIcon}
                  type="text"
                  placeholder="Enter your username"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  autoComplete="username"
                  autoFocus
                  disabled={loading}
                />
              </div>
            </div>

            {/* Password */}
            <div style={styles.field}>
              <label className="label">Password</label>
              <div style={styles.inputWrapper}>
                <span style={styles.inputIcon}>
                  <LockIcon />
                </span>
                <input
                  className="input"
                  style={styles.inputWithIcon}
                  type={showPass ? "text" : "password"}
                  placeholder="Enter your password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoComplete="current-password"
                  disabled={loading}
                />
                <button
                  type="button"
                  style={styles.eyeBtn}
                  onClick={() => setShowPass(!showPass)}
                  tabIndex={-1}
                >
                  {showPass ? <EyeOffIcon /> : <EyeIcon />}
                </button>
              </div>
            </div>

            {/* Submit */}
            <button
              type="submit"
              className="btn btn-primary btn-lg w-full"
              style={{ marginTop: 8, justifyContent: "center" }}
              disabled={loading}
            >
              {loading ? (
                <>
                  <div className="spinner spinner-sm" />
                  Authenticating...
                </>
              ) : (
                <>
                  <LockIcon size={16} />
                  Sign In
                </>
              )}
            </button>

          </form>
        </div>

        {/* Footer */}
        <p style={styles.footer}>
          Internal tool — authorised personnel only
        </p>

      </div>
    </div>
  );
}

/* ------------------------------------------------------------------
   STYLES
   ------------------------------------------------------------------ */
const styles = {
  page: {
    minHeight:      "100vh",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    padding:        "24px",
    position:       "relative",
    overflow:       "hidden",
  },

  bgGlow: {
    position:     "fixed",
    top:          "30%",
    left:         "50%",
    transform:    "translate(-50%, -50%)",
    width:        "600px",
    height:       "600px",
    background:   "radial-gradient(circle, rgba(37,99,235,0.08) 0%, transparent 70%)",
    pointerEvents: "none",
    zIndex:       0,
  },

  container: {
    width:    "100%",
    maxWidth: "420px",
    position: "relative",
    zIndex:   1,
  },

  header: {
    textAlign:    "center",
    marginBottom: "32px",
  },

  logoMark: {
    display:        "inline-flex",
    alignItems:     "center",
    justifyContent: "center",
    width:          "64px",
    height:         "64px",
    background:     "var(--bg-surface)",
    border:         "1px solid var(--accent-dim)",
    borderRadius:   "var(--radius-lg)",
    marginBottom:   "16px",
    boxShadow:      "var(--shadow-accent)",
  },

  title: {
    fontFamily: "var(--font-display)",
    fontSize:   "1.6rem",
    fontWeight: 800,
    color:      "var(--text-primary)",
    marginBottom: "4px",
  },

  subtitle: {
    fontSize:   "0.8rem",
    color:      "var(--text-muted)",
    fontFamily: "var(--font-mono)",
    textTransform: "uppercase",
    letterSpacing: "0.1em",
  },

  card: {
    background:    "var(--bg-surface)",
    border:        "1px solid var(--border)",
    borderRadius:  "var(--radius-xl)",
    padding:       "32px",
    boxShadow:     "var(--shadow-lg)",
  },

  cardHeader: {
    marginBottom: "24px",
  },

  cardLabel: {
    fontSize:      "0.7rem",
    fontFamily:    "var(--font-mono)",
    color:         "var(--accent)",
    textTransform: "uppercase",
    letterSpacing: "0.15em",
    display:       "block",
    marginBottom:  "4px",
  },

  cardTitle: {
    fontSize:   "1.4rem",
    fontWeight: 700,
    color:      "var(--text-primary)",
  },

  form: {
    display:       "flex",
    flexDirection: "column",
    gap:           "20px",
  },

  field: {
    display:       "flex",
    flexDirection: "column",
  },

  inputWrapper: {
    position: "relative",
    display:  "flex",
    alignItems: "center",
  },

  inputIcon: {
    position:    "absolute",
    left:        "14px",
    color:       "var(--text-muted)",
    display:     "flex",
    alignItems:  "center",
    pointerEvents: "none",
    zIndex:      1,
  },

  inputWithIcon: {
    paddingLeft:  "42px",
    paddingRight: "42px",
  },

  eyeBtn: {
    position:   "absolute",
    right:      "12px",
    background: "none",
    border:     "none",
    color:      "var(--text-muted)",
    cursor:     "pointer",
    display:    "flex",
    alignItems: "center",
    padding:    "4px",
    transition: "var(--transition)",
  },

  footer: {
    textAlign:  "center",
    marginTop:  "24px",
    fontSize:   "0.75rem",
    color:      "var(--text-muted)",
    fontFamily: "var(--font-mono)",
  },
};

/* ------------------------------------------------------------------
   INLINE ICONS (no extra dependency needed)
   ------------------------------------------------------------------ */
const UserIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
    <circle cx="12" cy="7" r="4"/>
  </svg>
);

const LockIcon = ({ size = 16 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
    <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
  </svg>
);

const EyeIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/>
    <circle cx="12" cy="12" r="3"/>
  </svg>
);

const EyeOffIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94"/>
    <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19"/>
    <line x1="1" y1="1" x2="23" y2="23"/>
  </svg>
);
