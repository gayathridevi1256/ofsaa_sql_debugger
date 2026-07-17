/**
 * App.jsx — Root component with routing and auth context.
 *
 * LAYMAN'S EXPLANATION:
 *   This file does two things:
 *
 *   1. ROUTING — decides which page to show based on the URL:
 *      /login      → Login page
 *      /           → Dashboard (upload + run)
 *      /jobs/:id   → Results page for a specific job
 *      /admin      → Admin panel
 *
 *   2. AUTH CONTEXT — shares the logged-in user across all pages.
 *      Instead of passing "who is logged in" as a prop to every
 *      component, we put it in a "context" (like a global variable)
 *      that any component can read.
 *
 *   ProtectedRoute — wraps pages that require login.
 *   If not logged in, redirects to /login automatically.
 */

import React, { createContext, useContext, useState, useEffect } from "react";
import {
  BrowserRouter,
  Routes,
  Route,
  Navigate,
  useLocation,
} from "react-router-dom";
import { authAPI } from "./api";
import Login from "./pages/Login";
import Dashboard from "./pages/Dashboard";
import Results from "./pages/Results";
import BatchResults from "./pages/BatchResults";

// ----------------------------------------------------------------------
// AUTH CONTEXT
// Global state for the logged-in user.
// Any component can call useAuth() to get the current user.
// ----------------------------------------------------------------------
export const AuthContext = createContext(null);

export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
  return ctx;
};

function AuthProvider({ children }) {
  const [user, setUser]       = useState(null);
  const [loading, setLoading] = useState(true);

  // On app load — check if there's a stored token and verify it
  useEffect(() => {
    const checkAuth = async () => {
      const token = localStorage.getItem("token");
      if (!token) {
        setLoading(false);
        return;
      }
      try {
        const me = await authAPI.getMe();
        setUser(me);
      } catch {
        // Token invalid or expired — clear it
        localStorage.removeItem("token");
        localStorage.removeItem("user");
      } finally {
        setLoading(false);
      }
    };
    checkAuth();
  }, []);

  const login = (tokenData) => {
    localStorage.setItem("token", tokenData.access_token);
    localStorage.setItem("user", JSON.stringify(tokenData));
    setUser({
      username:  tokenData.username,
      full_name: tokenData.full_name,
      role:      tokenData.role,
    });
  };

  const logout = () => {
    authAPI.logout();
    setUser(null);
  };

  if (loading) {
    return (
      <div style={{
        display: "flex", alignItems: "center", justifyContent: "center",
        height: "100vh", background: "var(--bg-base)", color: "var(--text-primary)"
      }}>
        <div style={{ textAlign: "center" }}>
          <div className="spinner" />
          <p style={{ marginTop: 16, fontFamily: "var(--font-body)", color: "var(--text-muted)" }}>
            Initialising...
          </p>
        </div>
      </div>
    );
  }

  return (
    <AuthContext.Provider value={{ user, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

// ----------------------------------------------------------------------
// PROTECTED ROUTE
// Wraps pages that need login. Redirects to /login if not authenticated.
// ----------------------------------------------------------------------
function ProtectedRoute({ children, adminOnly = false }) {
  const { user } = useAuth();
  const location = useLocation();

  if (!user) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if (adminOnly && user.role !== "admin") {
    return <Navigate to="/" replace />;
  }

  return children;
}

// ----------------------------------------------------------------------
// APP — Routes
// ----------------------------------------------------------------------
export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Routes>
          {/* Public */}
          <Route path="/login" element={<PublicRoute><Login /></PublicRoute>} />

          {/* Protected */}
          <Route path="/" element={
            <ProtectedRoute><Dashboard /></ProtectedRoute>
          } />
          <Route path="/jobs/:jobId" element={
            <ProtectedRoute><Results /></ProtectedRoute>
          } />
          <Route path="/batch" element={
            <ProtectedRoute><BatchResults /></ProtectedRoute>
          } />

          {/* Fallback */}
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </AuthProvider>
    </BrowserRouter>
  );
}

// Redirect to dashboard if already logged in
function PublicRoute({ children }) {
  const { user } = useAuth();
  if (user) return <Navigate to="/" replace />;
  return children;
}
