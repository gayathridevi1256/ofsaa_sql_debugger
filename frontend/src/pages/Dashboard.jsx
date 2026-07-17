/**
 * Dashboard.jsx — Main page for uploading log files and running the pipeline.
 *
 * SECTIONS:
 *   1. Top navbar with user info + logout
 *   2. Upload zone — drag & drop or click to upload .log/.txt files
 *   3. Run button — triggers the pipeline after upload
 *   4. Job history — table of past runs with status and links to results
 *
 * FLOW:
 *   User drops log file → upload to backend → click Run → pipeline starts
 *   → job_id returned → navigate to /jobs/:jobId for live progress
 */

import React, { useState, useEffect, useRef, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../App";
import { filesAPI, jobsAPI, getErrorMessage } from "../api";

export default function Dashboard() {
  const { user, logout }   = useAuth();
  const navigate           = useNavigate();

  // Upload state
  const [dragging,      setDragging]      = useState(false);
  const [uploadedFiles, setUploadedFiles] = useState([]); // [{ filename, file_path, size_bytes, origName }]
  const [uploading,     setUploading]     = useState(false);
  const [uploadingIdx,  setUploadingIdx]  = useState(null); // index currently uploading
  const [uploadError,   setUploadError]   = useState("");

  // Pipeline state
  const [running,         setRunning]         = useState(false);
  const [runError,        setRunError]        = useState("");
  const [cachedResult,    setCachedResult]    = useState(null);
  const [showCacheDialog, setShowCacheDialog] = useState(false);

  // Job history
  const [jobs,          setJobs]          = useState([]);
  const [loadingJobs,   setLoadingJobs]   = useState(true);

  const fileInputRef = useRef(null);

  // Load job history on mount
  useEffect(() => {
    loadJobs();
  }, []);

  const loadJobs = async () => {
    try {
      const data = await jobsAPI.listJobs();
      setJobs(data.jobs || []);
    } catch (err) {
      console.error("Failed to load jobs:", err);
    } finally {
      setLoadingJobs(false);
    }
  };

  // ------------------------------------------------------------------
  // DRAG AND DROP HANDLERS
  // ------------------------------------------------------------------
  const handleDragOver = useCallback((e) => {
    e.preventDefault();
    setDragging(true);
  }, []);

  const handleDragLeave = useCallback((e) => {
    e.preventDefault();
    setDragging(false);
  }, []);

  const handleDrop = useCallback((e) => {
    e.preventDefault();
    setDragging(false);
    const files = Array.from(e.dataTransfer.files);
    if (files.length) handleFilesSelect(files);
  }, []);

  const handleFileInputChange = (e) => {
    const files = Array.from(e.target.files);
    if (files.length) handleFilesSelect(files);
    e.target.value = "";
  };

  // ------------------------------------------------------------------
  // FILE UPLOAD (single or batch)
  // ------------------------------------------------------------------
  const handleFilesSelect = async (files) => {
    const valid = files.filter(f => f.name.endsWith(".log") || f.name.endsWith(".txt"));
    if (!valid.length) {
      setUploadError("Only .log and .txt files are accepted");
      return;
    }
    if (valid.length < files.length) {
      setUploadError(`${files.length - valid.length} file(s) skipped — only .log/.txt accepted`);
    } else {
      setUploadError("");
    }

    setUploading(true);
    setUploadedFiles([]);

    const results = [];
    for (let i = 0; i < valid.length; i++) {
      setUploadingIdx(i);
      try {
        const result = await filesAPI.uploadLog(valid[i], () => {});
        results.push({ ...result, origName: valid[i].name });
      } catch (err) {
        results.push({ origName: valid[i].name, error: getErrorMessage(err) });
      }
    }
    setUploadedFiles(results);
    setUploadingIdx(null);
    setUploading(false);
  };

  const removeFile = (idx) => {
    setUploadedFiles(prev => prev.filter((_, i) => i !== idx));
  };

  // ------------------------------------------------------------------
  // RUN PIPELINE (single or batch)
  // ------------------------------------------------------------------
  const handleRun = async (force = false) => {
    const ready = uploadedFiles.filter(f => f.file_path);
    if (!ready.length) return;

    setRunning(true);
    setRunError("");

    if (ready.length === 1) {
      try {
        const result = await jobsAPI.runPipeline(ready[0].file_path, force);
        if (result.cached) {
          setCachedResult(result);
          setShowCacheDialog(true);
          setRunning(false);
        } else {
          navigate(`/jobs/${result.job_id}`);
        }
      } catch (err) {
        setRunError(getErrorMessage(err));
        setRunning(false);
      }
    } else {
      // Batch: single backend call that runs all jobs SEQUENTIALLY to avoid
      // set_batch_date conflicts (only one batch date can run at a time)
      try {
        const filePaths = ready.map(f => f.file_path);
        const result    = await jobsAPI.batchRun(filePaths);
        navigate("/batch", { state: { jobs: result.jobs } });
      } catch (err) {
        setRunError(getErrorMessage(err));
        setRunning(false);
      }
    }
  };

  // ------------------------------------------------------------------
  // LOGOUT
  // ------------------------------------------------------------------
  const handleLogout = () => {
    logout();
    navigate("/login");
  };

  // ------------------------------------------------------------------
  // RENDER
  // ------------------------------------------------------------------
  return (
    <div className="page">

      {/* ── NAVBAR ── */}
      <nav style={styles.navbar}>
        <div style={styles.navInner}>
          <div style={styles.navBrand}>
            <LogoIcon />
            <div>
              <span style={styles.navTitle}>Scenario Debugger</span>
              <span style={styles.navVersion}>OFSAA AML v1.0</span>
            </div>
          </div>

          <div style={styles.navRight}>
            <div style={styles.userChip}>
              <div style={styles.userAvatar}>
                {user?.username?.[0]?.toUpperCase()}
              </div>
              <div>
                <div style={styles.userName}>{user?.full_name || user?.username}</div>
                <div style={styles.userRole}>{user?.role}</div>
              </div>
            </div>
            <button className="btn btn-secondary btn-sm" onClick={handleLogout}>
              <LogoutIcon /> Sign Out
            </button>
          </div>
        </div>
      </nav>

      {/* ── MAIN CONTENT ── */}
      <main className="page-content stagger">

        {/* Page heading */}
        <div style={{ marginBottom: 32 }}>
          <h1 style={{ marginBottom: 6 }}>
            Diagnostic <span style={{ color: "var(--accent)" }}>Pipeline</span>
          </h1>
          <p style={{ color: "var(--text-muted)", fontFamily: "var(--font-mono)", fontSize: "0.85rem" }}>
            Upload an OFSAA batch log file to begin scenario analysis
          </p>
        </div>

        {/* ── TOP ROW: Upload + Info ── */}
        <div style={styles.topRow}>

          {/* Upload Zone */}
          <div style={{ flex: 2 }}>
            <input
              ref={fileInputRef}
              type="file"
              accept=".log,.txt"
              multiple
              style={{ display: "none" }}
              onChange={handleFileInputChange}
            />

            {/* Drop zone — shown when no files staged yet */}
            {!uploading && uploadedFiles.length === 0 && (
              <div
                style={{
                  ...styles.dropzone,
                  ...(dragging ? styles.dropzoneDragging : {}),
                }}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
                onClick={() => fileInputRef.current?.click()}
              >
                <div style={styles.dropzoneContent}>
                  <div style={styles.dropzoneIcon}><UploadIcon /></div>
                  <p style={styles.dropzoneText}>
                    {dragging ? "Drop files here" : "Drag & drop OFSAA log files"}
                  </p>
                  <p style={styles.dropzoneHint}>
                    or click to browse &nbsp;·&nbsp; .log / .txt &nbsp;·&nbsp;
                    <strong style={{ color: "var(--accent)" }}>multiple files supported</strong>
                  </p>
                </div>
              </div>
            )}

            {/* Uploading spinner */}
            {uploading && (
              <div style={{ ...styles.dropzone, cursor: "default" }}>
                <div style={styles.dropzoneContent}>
                  <div className="spinner" style={{ marginBottom: 16 }} />
                  <p style={styles.dropzoneText}>
                    Uploading file {(uploadingIdx ?? 0) + 1}…
                  </p>
                </div>
              </div>
            )}

            {/* Staged files list */}
            {!uploading && uploadedFiles.length > 0 && (
              <div style={styles.fileList}>
                <div style={styles.fileListHeader}>
                  <span style={{ fontWeight: 600, fontSize: "0.85rem" }}>
                    {uploadedFiles.length} file{uploadedFiles.length > 1 ? "s" : ""} ready
                  </span>
                  <button
                    className="btn btn-secondary btn-sm"
                    onClick={() => fileInputRef.current?.click()}
                  >
                    <UploadIcon /> Add More
                  </button>
                </div>
                {uploadedFiles.map((f, idx) => (
                  <div key={idx} style={{
                    ...styles.fileRow,
                    background: f.error ? "var(--danger-dim)" : "var(--bg-elevated)",
                    borderColor: f.error ? "var(--danger)" : "var(--border)",
                  }}>
                    <span style={{ fontSize: "1rem" }}>{f.error ? "❌" : "✅"}</span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontFamily: "var(--font-mono)", fontSize: "0.8rem",
                        color: "var(--text-primary)", overflow: "hidden",
                        textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                        {f.origName}
                      </div>
                      {f.size_bytes && (
                        <div style={{ fontSize: "0.72rem", color: "var(--text-muted)" }}>
                          {(f.size_bytes / 1024).toFixed(1)} KB
                        </div>
                      )}
                      {f.error && (
                        <div style={{ fontSize: "0.72rem", color: "var(--danger)" }}>
                          {f.error}
                        </div>
                      )}
                    </div>
                    <button
                      style={styles.removeBtn}
                      onClick={() => removeFile(idx)}
                      title="Remove"
                    >
                      ✕
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* Upload error */}
            {uploadError && (
              <div className="alert alert-error animate-fade-in" style={{ marginTop: 12 }}>
                <span>⚠</span><span>{uploadError}</span>
              </div>
            )}

            {/* Run error */}
            {runError && (
              <div className="alert alert-error animate-fade-in" style={{ marginTop: 12 }}>
                <span>⚠</span><span>{runError}</span>
              </div>
            )}

            {/* Run Button */}
            {(() => {
              const ready = uploadedFiles.filter(f => f.file_path);
              const isBatch = ready.length > 1;
              return (
                <button
                  className="btn btn-primary btn-lg w-full"
                  style={{ marginTop: 16, justifyContent: "center" }}
                  onClick={handleRun}
                  disabled={ready.length === 0 || running || uploading}
                >
                  {running ? (
                    <><div className="spinner spinner-sm" /> Starting{isBatch ? " Batch" : ""}...</>
                  ) : isBatch ? (
                    <><PlayIcon /> Run All ({ready.length} Files)</>
                  ) : (
                    <><PlayIcon /> Run Diagnostic Pipeline</>
                  )}
                </button>
              );
            })()}
          </div>

          {/* Pipeline Steps Info Card */}
          <div style={{ flex: 1 }}>
            <div className="card" style={{ height: "100%" }}>
              <h3 style={{ marginBottom: 16, fontSize: "0.9rem",
                color: "var(--text-secondary)", textTransform: "uppercase",
                letterSpacing: "0.08em", fontFamily: "var(--font-mono)" }}>
                Pipeline Steps
              </h3>
              <div style={styles.stepsList}>
                {PIPELINE_STEPS.map((step, i) => (
                  <div key={step.name} style={styles.stepItem}>
                    <div style={styles.stepNum}>{i + 1}</div>
                    <div>
                      <div style={styles.stepName}>{step.label}</div>
                      <div style={styles.stepDesc}>{step.desc}</div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>

        </div>

        {/* ── JOB HISTORY ── */}
        <div style={{ marginTop: 40 }}>
          <div style={{ display: "flex", alignItems: "center",
            justifyContent: "space-between", marginBottom: 16 }}>
            <h2 style={{ fontSize: "1.2rem" }}>Recent Runs</h2>
            <button className="btn btn-secondary btn-sm" onClick={loadJobs}>
              <RefreshIcon /> Refresh
            </button>
          </div>

          {loadingJobs ? (
            <div style={{ textAlign: "center", padding: 40 }}>
              <div className="spinner" />
            </div>
          ) : jobs.length === 0 ? (
            <div className="card" style={{ textAlign: "center", padding: 48 }}>
              <p style={{ color: "var(--text-muted)" }}>
                No runs yet — upload a log file and run the pipeline
              </p>
            </div>
          ) : (
            <div className="card" style={{ padding: 0, overflow: "hidden" }}>
              <table style={styles.table}>
                <thead>
                  <tr style={styles.tableHead}>
                    <th style={styles.th}>Scenario</th>
                    <th style={styles.th}>Batch Date</th>
                    <th style={styles.th}>Status</th>
                    <th style={styles.th}>Alerts</th>
                    <th style={styles.th}>Started</th>
                    <th style={styles.th}>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {jobs.map((job, idx) => (
                    <tr
                      key={job.job_id}
                      style={{
                        ...styles.tr,
                        background: idx % 2 === 0
                          ? "transparent"
                          : "rgba(255,255,255,0.01)"
                      }}
                    >
                      <td style={styles.td}>
                        <span style={{ fontFamily: "var(--font-mono)",
                          fontSize: "0.85rem", color: "var(--text-primary)" }}>
                          {job.scenario_name || "—"}
                        </span>
                      </td>
                      <td style={styles.td}>
                        <span style={{ fontFamily: "var(--font-mono)",
                          fontSize: "0.8rem", color: "var(--text-secondary)" }}>
                          {job.batch_date || "—"}
                        </span>
                      </td>
                      <td style={styles.td}>
                        <StatusBadge status={job.status} />
                      </td>
                      <td style={styles.td}>
                        {job.alerts_generated === 1
                          ? <span className="badge badge-success">✓ Yes</span>
                          : job.alerts_generated === 0 && job.status === "completed"
                          ? <span className="badge badge-danger">✗ No</span>
                          : <span className="badge badge-muted">—</span>
                        }
                      </td>
                      <td style={styles.td}>
                        <span style={{ fontSize: "0.8rem",
                          color: "var(--text-muted)", fontFamily: "var(--font-mono)" }}>
                          {formatDate(job.started_at)}
                        </span>
                      </td>
                      <td style={styles.td}>
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => navigate(`/jobs/${job.job_id}`)}
                        >
                          View
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>

      </main>

      {/* ── CACHE DIALOG ── */}
      {showCacheDialog && cachedResult && (
        <div style={{
          position: "fixed", inset: 0,
          background: "rgba(0,0,0,0.6)", backdropFilter: "blur(4px)",
          display: "flex", alignItems: "center", justifyContent: "center",
          zIndex: 1000,
        }}>
          <div className="card" style={{
            maxWidth: 440, width: "90%", padding: "28px 32px",
            display: "flex", flexDirection: "column", gap: 20,
          }}>
            <div>
              <div style={{ fontSize: "1rem", fontWeight: 700, marginBottom: 6 }}>
                Previous Results Found
              </div>
              <div style={{ fontSize: "0.82rem", color: "var(--text-muted)", lineHeight: 1.6 }}>
                Cached results already exist for this scenario and batch date.
              </div>
            </div>

            <div style={{
              background: "var(--bg-elevated)", borderRadius: 8,
              padding: "12px 16px", display: "flex", flexDirection: "column", gap: 8,
            }}>
              {[
                ["Scenario",  cachedResult.scenario_name],
                ["Batch Date", cachedResult.batch_date],
                ["Computed",  cachedResult.cached_at
                  ? new Date(cachedResult.cached_at).toLocaleString()
                  : "—"],
              ].map(([label, value]) => (
                <div key={label} style={{ display: "flex", gap: 12, fontSize: "0.82rem" }}>
                  <span style={{ color: "var(--text-muted)", minWidth: 80, fontFamily: "var(--font-mono)" }}>
                    {label}
                  </span>
                  <span style={{ color: "var(--text-primary)", fontFamily: "var(--font-mono)", fontWeight: 600 }}>
                    {value || "—"}
                  </span>
                </div>
              ))}
            </div>

            <div style={{ display: "flex", gap: 10 }}>
              <button
                className="btn btn-primary"
                style={{ flex: 1 }}
                onClick={() => {
                  setShowCacheDialog(false);
                  navigate(`/jobs/${cachedResult.cached_job_id}`);
                }}
              >
                Use Previous Results
              </button>
              <button
                className="btn btn-secondary"
                style={{ flex: 1 }}
                onClick={() => {
                  setShowCacheDialog(false);
                  setCachedResult(null);
                  handleRun(true);
                }}
              >
                Run Fresh Analysis
              </button>
            </div>

            <button
              className="btn btn-secondary btn-sm"
              style={{ alignSelf: "center", marginTop: -8 }}
              onClick={() => { setShowCacheDialog(false); setCachedResult(null); }}
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------
   SUB-COMPONENTS
   ------------------------------------------------------------------ */

function StatusBadge({ status }) {
  const map = {
    pending:   { cls: "badge-muted",    label: "Pending"   },
    running:   { cls: "badge-info",     label: "Running"   },
    completed: { cls: "badge-success",  label: "Completed" },
    failed:    { cls: "badge-danger",   label: "Failed"    },
  };
  const { cls, label } = map[status] || { cls: "badge-muted", label: status };
  return <span className={`badge ${cls}`}>{label}</span>;
}

/* ------------------------------------------------------------------
   CONSTANTS
   ------------------------------------------------------------------ */
const PIPELINE_STEPS = [
  { name: "log_reader",     label: "Log Reader",      desc: "Extract metadata & SQL from log"   },
  { name: "set_batch_date", label: "Set Batch Date",  desc: "SSH to OFSAA server, set date"     },
  { name: "sql_executer",   label: "SQL Executer",    desc: "Run full scenario, check alerts"   },
  { name: "cte_parser",     label: "CTE Parser",      desc: "Split SQL into individual CTEs"    },
  { name: "cte_executer",   label: "CTE Executer",    desc: "Execute each CTE, find empty one"  },
  { name: "sql_diagnostics",label: "SQL Diagnostics", desc: "Diagnose root cause of 0 rows"     },
];

/* ------------------------------------------------------------------
   HELPERS
   ------------------------------------------------------------------ */
const formatDate = (iso) => {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString("en-GB", {
      day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit"
    });
  } catch { return iso; }
};

/* ------------------------------------------------------------------
   STYLES
   ------------------------------------------------------------------ */
const styles = {
  navbar: {
    background:   "var(--bg-surface)",
    borderBottom: "1px solid var(--border)",
    position:     "sticky",
    top:          0,
    zIndex:       100,
    backdropFilter: "blur(12px)",
  },
  navInner: {
    maxWidth:       "1200px",
    margin:         "0 auto",
    padding:        "0 24px",
    height:         "64px",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "space-between",
  },
  navBrand: {
    display:    "flex",
    alignItems: "center",
    gap:        "12px",
  },
  navTitle: {
    fontFamily:  "var(--font-display)",
    fontWeight:  700,
    fontSize:    "1rem",
    display:     "block",
    lineHeight:  1.2,
  },
  navVersion: {
    fontSize:      "0.65rem",
    color:         "var(--text-muted)",
    fontFamily:    "var(--font-mono)",
    textTransform: "uppercase",
    letterSpacing: "0.08em",
    display:       "block",
  },
  navRight: {
    display:    "flex",
    alignItems: "center",
    gap:        "16px",
  },
  userChip: {
    display:       "flex",
    alignItems:    "center",
    gap:           "10px",
    padding:       "6px 12px",
    background:    "var(--bg-overlay)",
    borderRadius:  "var(--radius-md)",
    border:        "1px solid var(--border)",
  },
  userAvatar: {
    width:          "28px",
    height:         "28px",
    borderRadius:   "50%",
    background:     "var(--accent-dim)",
    color:          "var(--accent)",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    fontSize:       "0.75rem",
    fontWeight:     700,
    fontFamily:     "var(--font-mono)",
  },
  userName: {
    fontSize:   "0.85rem",
    fontWeight: 500,
    lineHeight: 1.2,
  },
  userRole: {
    fontSize:      "0.65rem",
    color:         "var(--text-muted)",
    fontFamily:    "var(--font-mono)",
    textTransform: "uppercase",
  },
  topRow: {
    display: "flex",
    gap:     "24px",
    alignItems: "stretch",
  },
  dropzone: {
    border:        "2px dashed var(--border-bright)",
    borderRadius:  "var(--radius-lg)",
    padding:       "48px 32px",
    textAlign:     "center",
    cursor:        "pointer",
    transition:    "var(--transition)",
    background:    "var(--bg-surface)",
    minHeight:     "240px",
    display:       "flex",
    alignItems:    "center",
    justifyContent:"center",
  },
  dropzoneDragging: {
    borderColor: "var(--accent)",
    background:  "var(--accent-subtle)",
    boxShadow:   "var(--shadow-accent)",
  },
  dropzoneDone: {
    borderColor: "var(--success)",
    borderStyle: "solid",
    background:  "rgba(16,185,129,0.04)",
  },
  dropzoneContent: {
    display:       "flex",
    flexDirection: "column",
    alignItems:    "center",
    gap:           "8px",
  },
  dropzoneIcon: {
    width:          "56px",
    height:         "56px",
    borderRadius:   "var(--radius-lg)",
    background:     "var(--accent-subtle)",
    border:         "1px solid var(--accent-dim)",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    color:          "var(--accent)",
    marginBottom:   "8px",
  },
  successIcon: {
    width:          "56px",
    height:         "56px",
    borderRadius:   "50%",
    background:     "var(--success-dim)",
    border:         "1px solid var(--success)",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    color:          "var(--success)",
    marginBottom:   "8px",
  },
  dropzoneText: {
    fontSize:   "1rem",
    fontWeight: 600,
    color:      "var(--text-primary)",
  },
  dropzoneHint: {
    fontSize:   "0.8rem",
    color:      "var(--text-muted)",
    fontFamily: "var(--font-mono)",
  },
  progressBar: {
    width:         "200px",
    height:        "4px",
    background:    "var(--bg-overlay)",
    borderRadius:  "2px",
    overflow:      "hidden",
    marginTop:     "8px",
  },
  progressFill: {
    height:     "100%",
    background: "linear-gradient(90deg, var(--accent-dim), var(--accent))",
    borderRadius: "2px",
    transition: "width 0.3s ease",
  },
  stepsList: {
    display:       "flex",
    flexDirection: "column",
    gap:           "12px",
  },
  stepItem: {
    display:    "flex",
    alignItems: "flex-start",
    gap:        "12px",
  },
  stepNum: {
    width:          "22px",
    height:         "22px",
    borderRadius:   "50%",
    background:     "var(--accent-subtle)",
    border:         "1px solid var(--accent-dim)",
    color:          "var(--accent)",
    fontSize:       "0.7rem",
    fontWeight:     700,
    fontFamily:     "var(--font-mono)",
    display:        "flex",
    alignItems:     "center",
    justifyContent: "center",
    flexShrink:     0,
    marginTop:      "2px",
  },
  stepName: {
    fontSize:   "0.85rem",
    fontWeight: 600,
    color:      "var(--text-primary)",
    lineHeight: 1.3,
  },
  stepDesc: {
    fontSize:   "0.75rem",
    color:      "var(--text-muted)",
    marginTop:  "2px",
  },
  fileList: {
    border:        "1px solid var(--border)",
    borderRadius:  "var(--radius-lg)",
    overflow:      "hidden",
    background:    "var(--bg-surface)",
  },
  fileListHeader: {
    display:        "flex",
    alignItems:     "center",
    justifyContent: "space-between",
    padding:        "10px 14px",
    borderBottom:   "1px solid var(--border)",
    background:     "var(--bg-elevated)",
  },
  fileRow: {
    display:    "flex",
    alignItems: "center",
    gap:        "10px",
    padding:    "10px 14px",
    borderBottom: "1px solid var(--border)",
    border:     "1px solid transparent",
  },
  removeBtn: {
    background: "none",
    border:     "none",
    color:      "var(--text-muted)",
    cursor:     "pointer",
    fontSize:   "0.85rem",
    padding:    "2px 6px",
    borderRadius: 4,
    lineHeight: 1,
  },
  table: {
    width:           "100%",
    borderCollapse:  "collapse",
    fontFamily:      "var(--font-body)",
  },
  tableHead: {
    borderBottom: "1px solid var(--border)",
    background:   "var(--bg-elevated)",
  },
  th: {
    padding:       "12px 16px",
    textAlign:     "left",
    fontSize:      "0.7rem",
    fontWeight:    600,
    color:         "var(--text-muted)",
    textTransform: "uppercase",
    letterSpacing: "0.08em",
    fontFamily:    "var(--font-mono)",
  },
  tr: {
    borderBottom: "1px solid var(--border)",
    transition:   "var(--transition)",
    cursor:       "pointer",
  },
  td: {
    padding:   "14px 16px",
    fontSize:  "0.9rem",
    color:     "var(--text-secondary)",
    verticalAlign: "middle",
  },
};

/* ------------------------------------------------------------------
   ICONS
   ------------------------------------------------------------------ */
const LogoIcon = () => (
  <svg width="28" height="28" viewBox="0 0 32 32" fill="none">
    <path d="M4 8h24M4 16h16M4 24h20" stroke="#2563eb"
      strokeWidth="2.5" strokeLinecap="round"/>
    <circle cx="26" cy="24" r="4" fill="#2563eb" opacity="0.25"
      stroke="#2563eb" strokeWidth="1.5"/>
  </svg>
);
const UploadIcon = () => (
  <svg width="24" height="24" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
    <polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
  </svg>
);
const CheckIcon = () => (
  <svg width="24" height="24" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
    <polyline points="20 6 9 17 4 12"/>
  </svg>
);
const PlayIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
    <polygon points="5 3 19 12 5 21 5 3"/>
  </svg>
);
const LogoutIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>
    <polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>
  </svg>
);
const RefreshIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <polyline points="23 4 23 10 17 10"/>
    <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
  </svg>
);
