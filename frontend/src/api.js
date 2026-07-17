/**
 * api.js — All API calls to the FastAPI backend in one place.
 *
 * LAYMAN'S EXPLANATION:
 *   Instead of writing fetch() calls scattered across every React component,
 *   we put ALL backend communication here.
 *
 *   Think of this as a "phone directory" — every component that needs
 *   to talk to the backend just calls a function from here instead of
 *   knowing the backend URL themselves.
 *
 *   Benefits:
 *     - Change the API URL in ONE place (VITE_API_URL in .env)
 *     - JWT token is attached automatically to every request
 *     - Errors are handled consistently everywhere
 *     - Easy to see all backend calls at a glance
 */

import axios from "axios";

// ----------------------------------------------------------------------
// BASE URL
// Read from Vite environment variable — set in frontend/.env
// Default to localhost:8000 for development
// ----------------------------------------------------------------------
const BASE_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

// ----------------------------------------------------------------------
// AXIOS INSTANCE
// A pre-configured version of axios with our base URL and defaults.
// LAYMAN: Like a pre-addressed envelope — you just add the content.
// ----------------------------------------------------------------------
const api = axios.create({
  baseURL: BASE_URL,
  timeout: 30000, // 30 seconds
  headers: {
    "Content-Type": "application/json",
  },
});

// ----------------------------------------------------------------------
// REQUEST INTERCEPTOR — attach JWT token to every request
// LAYMAN: Before every API call goes out, this automatically adds
// the "Authorization: Bearer <token>" header so you never forget it.
// ----------------------------------------------------------------------
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem("token");
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// ----------------------------------------------------------------------
// RESPONSE INTERCEPTOR — handle token expiry globally
// LAYMAN: If ANY request gets a 401 (unauthorized/expired token),
// automatically log the user out and redirect to login.
// ----------------------------------------------------------------------
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      // Token expired or invalid — clear storage and redirect to login
      localStorage.removeItem("token");
      localStorage.removeItem("user");
      window.location.href = "/login";
    }
    return Promise.reject(error);
  }
);

// ----------------------------------------------------------------------
// AUTH API
// ----------------------------------------------------------------------

export const authAPI = {
  /**
   * Login with username and password.
   * Returns { access_token, username, full_name, role, expires_in }
   *
   * IMPORTANT: FastAPI's OAuth2 expects form data, not JSON.
   * That's why we use URLSearchParams here.
   */
  login: async (username, password) => {
    const formData = new URLSearchParams();
    formData.append("username", username);
    formData.append("password", password);

    const response = await api.post("/api/auth/login", formData, {
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
    });
    return response.data;
  },

  /**
   * Get current logged-in user details.
   * Called on app load to verify token is still valid.
   */
  getMe: async () => {
    const response = await api.get("/api/auth/me");
    return response.data;
  },

  /**
   * Logout — just clears local storage.
   * No backend call needed since JWTs are stateless.
   */
  logout: () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
  },
};

// ----------------------------------------------------------------------
// FILES API
// ----------------------------------------------------------------------

export const filesAPI = {
  /**
   * Upload a log file.
   * Returns { filename, saved_as, file_path, size_bytes }
   *
   * LAYMAN: This sends the file to the backend using multipart/form-data
   * (same as a browser file upload form).
   * We also show upload progress via onUploadProgress callback.
   */
  uploadLog: async (file, onProgress) => {
    const formData = new FormData();
    formData.append("file", file);

    const response = await api.post("/api/upload", formData, {
      headers: { "Content-Type": "multipart/form-data" },
      onUploadProgress: (progressEvent) => {
        if (onProgress) {
          const percent = Math.round(
            (progressEvent.loaded * 100) / progressEvent.total
          );
          onProgress(percent);
        }
      },
    });
    return response.data;
  },
};

// ----------------------------------------------------------------------
// JOBS API
// ----------------------------------------------------------------------

export const jobsAPI = {
  /**
   * Start a pipeline run for an uploaded file.
   * Returns { job_id, status, message }
   */
  runPipeline: async (filePath, force = false) => {
    const params = new URLSearchParams({ file_path: filePath });
    if (force) params.append("force", "true");
    const response = await api.post(`/api/jobs/run?${params}`);
    return response.data;
  },

  /**
   * Get list of past jobs.
   * Returns { jobs: [...], count: n }
   */
  listJobs: async () => {
    const response = await api.get("/api/jobs");
    return response.data;
  },

  /**
   * Get full details of one job including all step statuses.
   * Returns full job object with steps array.
   */
  getJob: async (jobId) => {
    const response = await api.get(`/api/jobs/${jobId}`);
    return response.data;
  },

  /**
   * Re-run the pipeline for an existing job (same log file, new job ID).
   * Returns { job_id, status }
   */
  rerunJob: async (jobId, force = false) => {
    const qs = force ? "?force=true" : "";
    const response = await api.post(`/api/jobs/${jobId}/rerun${qs}`);
    return response.data;
  },

  /**
   * Start a SEQUENTIAL batch run for multiple uploaded file paths.
   * Backend runs them one-by-one to avoid set_batch_date conflicts.
   * Returns { jobs: [{job_id, filename}], count }
   */
  batchRun: async (filePaths) => {
    const response = await api.post("/api/jobs/batch", { file_paths: filePaths });
    return response.data;
  },
};

// ----------------------------------------------------------------------
// WEBSOCKET — Live pipeline progress
// ----------------------------------------------------------------------

export const createProgressWebSocket = (jobId, handlers) => {
  /**
   * Opens a WebSocket connection to stream live pipeline progress.
   *
   * LAYMAN: A WebSocket is like a phone call that stays open.
   * Unlike normal API calls (dial → answer → hang up),
   * WebSocket stays connected and the server keeps sending updates.
   *
   * PARAMETERS:
   *   jobId    — which job to watch
   *   handlers — object with callback functions:
   *     onStepStarted(step, message)
   *     onStepCompleted(step, message, output)
   *     onStepFailed(step, message, error)
   *     onJobCompleted(data)
   *     onJobFailed(message)
   *     onJobState(job)   — called immediately with current state on connect
   *     onError(error)
   *
   * RETURNS the WebSocket instance so you can close it when done.
   *
   * USAGE in React:
   *   useEffect(() => {
   *     const ws = createProgressWebSocket(jobId, { onStepCompleted: ... });
   *     return () => ws.close();  // cleanup when component unmounts
   *   }, [jobId]);
   */
  const wsUrl = BASE_URL.replace("http", "ws") + `/api/ws/${jobId}`;
  const ws = new WebSocket(wsUrl);

  ws.onopen = () => {
    console.log(`WebSocket connected for job: ${jobId}`);
  };

  ws.onmessage = (event) => {
    try {
      const message = JSON.parse(event.data);
      const { event: eventType, ...data } = message;

      switch (eventType) {
        case "step_started":
          handlers.onStepStarted?.(data.step, data.message);
          break;
        case "step_completed":
          handlers.onStepCompleted?.(data.step, data.message, data.output);
          break;
        case "step_failed":
          handlers.onStepFailed?.(data.step, data.message, data.error);
          break;
        case "job_completed":
          handlers.onJobCompleted?.(data);
          break;
        case "job_failed":
          handlers.onJobFailed?.(data.message);
          break;
        case "job_state":
          handlers.onJobState?.(data.job);
          break;
        case "ping":
          ws.send("pong"); // keep-alive response
          break;
        default:
          console.log("Unknown WS event:", eventType, data);
      }
    } catch (err) {
      console.error("WebSocket message parse error:", err);
    }
  };

  ws.onerror = (error) => {
    console.error("WebSocket error:", error);
    handlers.onError?.(error);
  };

  ws.onclose = () => {
    console.log(`WebSocket closed for job: ${jobId}`);
  };

  return ws;
};

// ----------------------------------------------------------------------
// ADMIN API
// ----------------------------------------------------------------------

export const adminAPI = {
  /** List all users. Admin only. */
  listUsers: async () => {
    const response = await api.get("/api/admin/users");
    return response.data;
  },

  /** Create a new user. Admin only. */
  createUser: async (userData) => {
    const response = await api.post("/api/admin/users", userData);
    return response.data;
  },

  /** Deactivate a user. Admin only. */
  deactivateUser: async (userId) => {
    const response = await api.delete(`/api/admin/users/${userId}`);
    return response.data;
  },

  /** Get audit log. Admin only. */
  getAuditLog: async (limit = 100) => {
    const response = await api.get(`/api/admin/audit?limit=${limit}`);
    return response.data;
  },
};

// ----------------------------------------------------------------------
// HELPER — extract error message from axios error
// ----------------------------------------------------------------------

export const getErrorMessage = (error) => {
  /**
   * Extracts a clean error message from an axios error.
   *
   * FastAPI returns errors as { detail: "message" }
   * This helper handles all cases so components don't need to.
   */
  if (error.response?.data?.detail) {
    return error.response.data.detail;
  }
  if (error.response?.data?.message) {
    return error.response.data.message;
  }
  if (error.message) {
    return error.message;
  }
  return "An unexpected error occurred";
};

export default api;
