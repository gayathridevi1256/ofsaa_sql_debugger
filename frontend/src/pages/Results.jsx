/**
 * Results.jsx — Live pipeline tracker + CTE waterfall + Root cause card.
 *
 * ROUTE: /jobs/:jobId
 *
 * WHAT THIS PAGE DOES:
 *   1. Connects to WebSocket ws://<host>/ws/jobs/:jobId
 *   2. Streams live pipeline step events (step_started, step_completed, step_failed)
 *   3. On job_completed → shows CTE waterfall + root cause analysis
 *   4. On job_failed    → shows error state
 *
 * DATA FLOW FROM BACKEND (pipeline.py):
 *   WebSocket emits these event types:
 *     { event: "step_started",   job_id, step, message }
 *     { event: "step_completed", job_id, step, message, output }
 *     { event: "step_failed",    job_id, step, message, error  }
 *     { event: "job_completed",  job_id, alerts_generated, root_cause, results }
 *     { event: "job_failed",     job_id, message }
 *
 *   results[] from job_completed = [
 *     {
 *       cte_name:          string,
 *       failure_type:      string,
 *       likely_cause:      string,
 *       failure_condition: string,
 *       details:           any
 *     }
 *   ]
 *
 *   cte_results[] from job (fetched via REST on load) = [
 *     { name: string, rows: number, status: "ok" | "empty" }
 *   ]
 *
 * LAYMAN EXPLANATION:
 *   Think of this page like a flight tracker:
 *   - The pipeline steps are "legs" of the journey
 *   - Each CTE is a checkpoint — green = passed, red = empty
 *   - Root cause card is the final diagnosis report
 */

import React, { useState, useEffect, useRef, useCallback } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { jobsAPI, getErrorMessage } from "../api";

/* ─────────────────────────────────────────────────────────────────────────
   CONSTANTS
   ───────────────────────────────────────────────────────────────────────── */

const PIPELINE_STEPS = [
  { key: "log_reader",      label: "Log Reader",      desc: "Extract metadata & SQL" },
  { key: "set_batch_date",  label: "Set Batch Date",  desc: "SSH to OFSAA server"   },
  { key: "sql_executer",    label: "SQL Executer",    desc: "Run full scenario SQL"  },
  { key: "cte_parser",      label: "CTE Parser",      desc: "Split SQL into CTEs"    },
  { key: "cte_executer",    label: "CTE Executer",    desc: "Execute each CTE"       },
  { key: "sql_diagnostics", label: "SQL Diagnostics", desc: "Diagnose root cause"    },
];

const WS_BASE = (import.meta.env.VITE_API_URL || "http://localhost:8000")
  .replace(/^http/, "ws");

/* ─────────────────────────────────────────────────────────────────────────
   MAIN PAGE
   ───────────────────────────────────────────────────────────────────────── */

export default function Results() {
  const { jobId }  = useParams();
  const navigate   = useNavigate();

  /* ── Job metadata (fetched via REST on mount) ── */
  const [job,          setJob]          = useState(null);
  const [loadingJob,   setLoadingJob]   = useState(true);
  const [fetchError,   setFetchError]   = useState("");

  /* ── WebSocket / live progress state ── */
  const [stepStates,   setStepStates]   = useState({}); // { step_key: "idle"|"running"|"completed"|"failed" }
  const [stepOutputs,  setStepOutputs]  = useState({}); // { step_key: "output string" }
  const [currentStep,  setCurrentStep]  = useState(null);
  const [wsStatus,     setWsStatus]     = useState("connecting"); // connecting | live | closed | error

  /* ── Final results (populated on job_completed) ── */
  const [jobStatus,         setJobStatus]         = useState(null); // "completed" | "failed"
  const [alertsGenerated,   setAlertsGenerated]   = useState(null);
  const [rootCause,         setRootCause]          = useState(null);
  const [diagnosticResults, setDiagnosticResults] = useState([]);
  const [cteResults,        setCteResults]         = useState([]);

  /* ── UI state ── */
  const [expandedCTE,  setExpandedCTE]  = useState(null); // which CTE row is expanded
  const wsRef           = useRef(null);
  const reconnectTimer  = useRef(null);
  const reconnectCount  = useRef(0);
  const intentionalClose = useRef(false);

  /* Inject print CSS on mount */
  useEffect(() => {
    const style = document.createElement("style");
    style.id = "results-print-css";
    style.textContent = `
      @media print {
        .no-print { display: none !important; }
        body { background: #fff !important; color: #000 !important; font-size: 11pt; }
        .page-content { max-width: 100% !important; padding: 0 !important; }
        nav, .spinner { display: none !important; }
        .card { border: 1px solid #ccc !important; background: #fff !important;
                box-shadow: none !important; break-inside: avoid; margin-bottom: 12pt; }
        pre { white-space: pre-wrap !important; font-size: 8pt; }
        table { font-size: 9pt; }
        a { color: #000 !important; text-decoration: none; }
      }
    `;
    document.head.appendChild(style);
    return () => document.getElementById("results-print-css")?.remove();
  }, []);

  /* ────────────────────────────────────────────────────────────────────
     FETCH JOB FROM REST API ON MOUNT
     (handles page refresh — WebSocket may already be closed)
     ──────────────────────────────────────────────────────────────────── */
  useEffect(() => {
    const load = async () => {
      try {
        const data = await jobsAPI.getJob(jobId);
        setJob(data);

        // If job is already finished, populate results directly
        if (data.status === "completed" || data.status === "failed") {
          setJobStatus(data.status);
          setWsStatus("closed");

          if (data.status === "completed") {
            setAlertsGenerated(data.alerts_generated === 1);
            setRootCause(data.root_cause || null);

            // Parse stored result_json (array of diagnostic results)
            if (data.result_json) {
              try {
                const parsed = JSON.parse(data.result_json);
                setDiagnosticResults(Array.isArray(parsed) ? parsed : []);
              } catch {}
            }

            // Parse cte_results_json if backend stores it
            if (data.cte_results_json) {
              try {
                const parsed = JSON.parse(data.cte_results_json);
                setCteResults(Array.isArray(parsed) ? parsed : []);
              } catch {}
            }
          }

          // Reconstruct step states from job_steps data
          if (data.steps) {
            const states  = {};
            const outputs = {};
            data.steps.forEach((s) => {
              states[s.step_name]  = s.status;
              outputs[s.step_name] = s.output || "";
            });
            setStepStates(states);
            setStepOutputs(outputs);
          }
        }
      } catch (err) {
        setFetchError(getErrorMessage(err));
      } finally {
        setLoadingJob(false);
      }
    };
    load();
  }, [jobId]);

  /* ────────────────────────────────────────────────────────────────────
     WEBSOCKET — connect only if job not already done
     ──────────────────────────────────────────────────────────────────── */
  const connectWS = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const url = `${WS_BASE}/api/ws/${jobId}`;
    const ws  = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      setWsStatus("live");
      reconnectCount.current = 0; // reset on successful connect
    };

    ws.onmessage = (e) => {
      let msg;
      try { msg = JSON.parse(e.data); } catch { return; }

      const { event, step, output, error, results,
              alerts_generated, root_cause, cte_results, job } = msg;

      switch (event) {

        case "job_state":
          // Populate step states from job data when WebSocket first connects
          if (job && job.steps) {
            const states = {};
            const outputs = {};
            job.steps.forEach((s) => {
              states[s.step_name] = s.status;
              outputs[s.step_name] = s.output || "";
            });
            setStepStates(states);
            setStepOutputs(outputs);
          }
          break;

        case "step_started":
          setCurrentStep(step);
          setStepStates((prev) => ({ ...prev, [step]: "running" }));
          break;

        case "step_completed":
          setStepStates((prev) => ({ ...prev, [step]: "completed" }));
          if (output) setStepOutputs((prev) => ({ ...prev, [step]: output }));
          break;

        case "step_failed":
          setStepStates((prev) => ({ ...prev, [step]: "failed" }));
          if (error) setStepOutputs((prev) => ({ ...prev, [step]: error }));
          setJobStatus("failed");
          break;

        case "job_completed":
          setJobStatus("completed");
          setAlertsGenerated(!!alerts_generated);
          setRootCause(root_cause || null);
          if (results)     setDiagnosticResults(Array.isArray(results) ? results : []);
          if (cte_results) setCteResults(Array.isArray(cte_results) ? cte_results : []);
          // Delay close to ensure React renders the new state
          setTimeout(() => {
            intentionalClose.current = true;
            ws.close();
          }, 500);
          break;

        case "job_failed":
          setJobStatus("failed");
          intentionalClose.current = true;
          ws.close();
          break;

        default:
          break;
      }
    };

    ws.onerror = () => {
      // ws.onclose always fires after onerror — let onclose drive all state
      // transitions so we don't flash "WS Error" during a reconnect attempt.
      console.warn("[WS] error on job", jobId);
    };

    ws.onclose = () => {
      // If we closed it ourselves (job done / navigating away) → no retry
      if (intentionalClose.current) {
        intentionalClose.current = false;
        setWsStatus("closed");
        return;
      }
      // Unexpected close — try to reconnect (up to 5 times, 2 s apart)
      if (reconnectCount.current < 5) {
        reconnectCount.current += 1;
        const delay = reconnectCount.current * 2000; // 2s, 4s, 6s, 8s, 10s
        setWsStatus("connecting");
        reconnectTimer.current = setTimeout(connectWS, delay);
      } else {
        // All retries exhausted — give up and let the user decide
        setWsStatus("error");
      }
    };
  }, [jobId]);

  useEffect(() => {
    // Only open WebSocket if job isn't already finished
    if (!loadingJob && job && job.status !== "completed" && job.status !== "failed") {
      connectWS();
    }
    return () => {
      wsRef.current?.close();
      clearTimeout(reconnectTimer.current);
    };
  }, [loadingJob, job, connectWS]);

  /* ────────────────────────────────────────────────────────────────────
     RERUN + PDF HANDLERS
     ──────────────────────────────────────────────────────────────────── */

  const [rerunning,          setRerunning]          = useState(false);
  const [cachedRerun,        setCachedRerun]        = useState(null);
  const [showRerunCacheDialog, setShowRerunCacheDialog] = useState(false);

  const handleRerun = async (force = false) => {
    setRerunning(true);
    try {
      const result = await jobsAPI.rerunJob(jobId, force);
      if (result.cached) {
        setCachedRerun(result);
        setShowRerunCacheDialog(true);
        setRerunning(false);
      } else {
        navigate(`/jobs/${result.job_id}`);
      }
    } catch (err) {
      console.error("Rerun failed:", err);
      setRerunning(false);
    }
  };

  const handleDownloadPDF = () => {
    window.print();
  };

  /* ────────────────────────────────────────────────────────────────────
     RENDER
     ──────────────────────────────────────────────────────────────────── */

  if (loadingJob) return <LoadingScreen />;
  if (fetchError) return <ErrorScreen message={fetchError} onBack={() => navigate("/")} />;

  const isRunning   = jobStatus !== "completed" && jobStatus !== "failed";
  const hasCTEs     = cteResults.length > 0;
  const showResults = jobStatus === "completed" && !alertsGenerated;
  const showAlerts  = jobStatus === "completed" && alertsGenerated;

  return (
    <div className="page">

      {/* ── NAVBAR ── */}
      <nav style={S.navbar}>
        <div style={S.navInner}>
          <div style={S.navBrand}>
            <LogoIcon />
            <div>
              <span style={S.navTitle}>Scenario Debugger</span>
              <span style={S.navVersion}>OFSAA AML v1.0</span>
            </div>
          </div>
          <div style={S.navRight} className="no-print">
            {/* WS status pill + manual reconnect after retries exhausted */}
            <WsStatusPill status={wsStatus} />
            {wsStatus === "error" && (
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => {
                  reconnectCount.current = 0;
                  connectWS();
                }}
                title="Reconnect WebSocket"
              >
                Reconnect
              </button>
            )}
            {jobStatus === "completed" && (
              <>
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={handleDownloadPDF}
                  title="Download as PDF"
                >
                  <PdfIcon /> PDF
                </button>
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={handleRerun}
                  disabled={rerunning}
                >
                  {rerunning
                    ? <><div className="spinner spinner-sm" /> Rerunning…</>
                    : <><RerunIcon /> Rerun</>
                  }
                </button>
              </>
            )}
            <button
              className="btn btn-secondary btn-sm"
              onClick={() => navigate("/")}
            >
              <BackIcon /> Dashboard
            </button>
          </div>
        </div>
      </nav>

      <main className="page-content">

        {/* ── JOB HEADER ── */}
        <JobHeader job={job} jobStatus={jobStatus} />

        {/* ── PIPELINE TRACKER ── */}
        <section style={{ marginTop: 32 }} className="no-print">
          <SectionLabel text="Pipeline Execution" />
          <div style={S.trackerGrid}>
            {PIPELINE_STEPS.map((step, idx) => (
              <StepCard
                key={step.key}
                step={step}
                index={idx}
                status={stepStates[step.key] || "idle"}
                output={stepOutputs[step.key] || ""}
                isCurrent={currentStep === step.key}
              />
            ))}
          </div>
        </section>

        {/* ── ALERTS GENERATED (early exit) ── */}
        {showAlerts && (
          <section style={{ marginTop: 32 }} className="animate-fade-in">
            <div style={S.alertSuccessBox}>
              <div style={S.alertSuccessIcon}><CheckCircleIcon size={28} /></div>
              <div>
                <div style={S.alertSuccessTitle}>Alerts Generated Successfully</div>
                <div style={S.alertSuccessDesc}>
                  The scenario SQL executed and produced alerts as expected.
                  No CTE-level diagnosis was required.
                </div>
              </div>
            </div>
          </section>
        )}

        {/* ── RUNNING STATE hint ── */}
        {isRunning && (
          <section style={{ marginTop: 32 }} className="animate-fade-in">
            <div style={S.runningHint}>
              <div className="spinner spinner-sm" style={{ flexShrink: 0 }} />
              <span>
                Pipeline running — results will appear here automatically when
                execution completes.
              </span>
            </div>
          </section>
        )}

        {/* ── FAILED JOB state ── */}
        {jobStatus === "failed" && (
          <section style={{ marginTop: 32 }} className="animate-fade-in">
            <div className="alert alert-error">
              <span>✕</span>
              <div>
                <strong>Pipeline failed.</strong> Check the step that turned
                red above for the error detail. Review backend logs for the
                full traceback.
              </div>
            </div>
          </section>
        )}

        {/* ── CTE WATERFALL ── */}
        {showResults && hasCTEs && (
          <section style={{ marginTop: 40 }} className="animate-fade-in">
            <SectionLabel text="CTE Waterfall" />
            <p style={S.sectionDesc}>
              Each CTE was executed as an Oracle view in sequence.
              The first empty CTE is the failure point.
            </p>
            <div style={S.waterfall}>
              {cteResults.map((cte, idx) => (
                <CTERow
                  key={cte.name}
                  cte={cte}
                  index={idx}
                  isExpanded={expandedCTE === cte.name}
                  onToggle={() =>
                    setExpandedCTE(expandedCTE === cte.name ? null : cte.name)
                  }
                  isFailing={cte.status === "empty"}
                  isLast={idx === cteResults.length - 1}
                />
              ))}
            </div>
          </section>
        )}

        {/* ── ROOT CAUSE CARD ── */}
        {showResults && (
          <section style={{ marginTop: 40 }} className="animate-fade-in">
            <SectionLabel text="Root Cause Analysis" />
            <RootCauseCard
              rootCause={rootCause}
              diagnosticResults={diagnosticResults}
            />
          </section>
        )}

        {/* Bottom spacing */}
        <div style={{ height: 64 }} />

      </main>

      {/* ── RERUN CACHE DIALOG ── */}
      {showRerunCacheDialog && cachedRerun && (
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
                ["Scenario",   cachedRerun.scenario_name],
                ["Batch Date", cachedRerun.batch_date],
                ["Computed",   cachedRerun.cached_at
                  ? new Date(cachedRerun.cached_at).toLocaleString()
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
                  setShowRerunCacheDialog(false);
                  navigate(`/jobs/${cachedRerun.cached_job_id}`);
                }}
              >
                Use Previous Results
              </button>
              <button
                className="btn btn-secondary"
                style={{ flex: 1 }}
                onClick={() => {
                  setShowRerunCacheDialog(false);
                  setCachedRerun(null);
                  handleRerun(true);
                }}
              >
                Run Fresh Analysis
              </button>
            </div>

            <button
              className="btn btn-secondary btn-sm"
              style={{ alignSelf: "center", marginTop: -8 }}
              onClick={() => { setShowRerunCacheDialog(false); setCachedRerun(null); }}
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

/* ─────────────────────────────────────────────────────────────────────────
   SUB-COMPONENTS
   ───────────────────────────────────────────────────────────────────────── */

/* Job header strip */
function JobHeader({ job, jobStatus }) {
  if (!job) return null;
  return (
    <div style={S.jobHeader} className="animate-fade-in">
      <div style={S.jobMeta}>
        <span style={S.jobScenario}>
          {job.scenario_name || "Unknown Scenario"}
        </span>
        <span style={S.jobId}>
          Job&nbsp;
          <span style={{ color: "var(--accent)", fontFamily: "var(--font-mono)" }}>
            {job.job_id?.slice(0, 8)}…
          </span>
        </span>
      </div>
      <div style={S.jobTags}>
        {job.batch_date && (
          <span style={S.tag}>
            <CalendarIcon /> {job.batch_date}
          </span>
        )}
        {job.username && (
          <span style={S.tag}>
            <UserIcon /> {job.username}
          </span>
        )}
        <JobStatusBadge status={jobStatus || job.status} />
      </div>
    </div>
  );
}

/* Individual step card in the pipeline tracker */
function StepCard({ step, index, status, output, isCurrent }) {
  const cfg = STEP_STATUS_CONFIG[status] || STEP_STATUS_CONFIG.idle;
  return (
    <div
      style={{
        ...S.stepCard,
        ...(status === "running"   ? S.stepCardRunning   : {}),
        ...(status === "completed" ? S.stepCardCompleted : {}),
        ...(status === "failed"    ? S.stepCardFailed    : {}),
      }}
    >
      {/* Step number / status icon */}
      <div style={{ ...S.stepIcon, background: cfg.bg, borderColor: cfg.border, color: cfg.color }}>
        {status === "running"
          ? <div className="spinner spinner-sm" style={{ border: `2px solid ${cfg.border}`, borderTopColor: cfg.color }} />
          : cfg.icon
        }
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        {/* Step index + label */}
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 2 }}>
          <span style={S.stepIndex}>0{index + 1}</span>
          <span style={{ ...S.stepLabel, color: cfg.color }}>{step.label}</span>
        </div>
        <div style={S.stepDesc}>{step.desc}</div>

        {/* Output text when available */}
        {output && (
          <div style={S.stepOutput}>{output}</div>
        )}
      </div>

      {/* Right badge */}
      <div style={{ ...S.stepBadge, background: cfg.bg, color: cfg.color, borderColor: cfg.border }}>
        {cfg.label}
      </div>
    </div>
  );
}

/* CTE waterfall row */
function CTERow({ cte, index, isExpanded, onToggle, isFailing, isLast }) {
  const isOk = cte.status === "ok";

  return (
    <div style={{ position: "relative" }}>
      {/* Connector line downward */}
      {!isLast && (
        <div style={{
          ...S.connectorLine,
          background: isOk ? "var(--success)" : "var(--danger)",
          opacity: isOk ? 0.3 : 0.5,
        }} />
      )}

      <div
        style={{
          ...S.cteRow,
          ...(isFailing ? S.cteRowFailing : {}),
          ...(isExpanded ? S.cteRowExpanded : {}),
        }}
        onClick={onToggle}
      >
        {/* Status indicator */}
        <div style={{
          ...S.cteDot,
          background: isOk ? "var(--success)" : "var(--danger)",
          boxShadow: isOk
            ? "0 0 8px rgba(16,185,129,0.4)"
            : "0 0 12px rgba(239,68,68,0.6)",
        }} />

        {/* CTE name */}
        <div style={S.cteName}>
          <span style={S.cteIndex}>CTE {index + 1}</span>
          <span style={{
            ...S.cteLabel,
            color: isOk ? "var(--text-primary)" : "var(--danger)",
          }}>
            {cte.name}
          </span>
        </div>

        {/* Row count */}
        <div style={S.cteRowCount}>
          <span style={{ color: "var(--text-muted)", fontSize: "0.7rem", fontFamily: "var(--font-mono)" }}>
            ROWS
          </span>
          <span style={{
            fontSize: "1.1rem",
            fontWeight: 700,
            fontFamily: "var(--font-mono)",
            color: isOk ? "var(--success)" : "var(--danger)",
          }}>
            {cte.rows?.toLocaleString() ?? "—"}
          </span>
        </div>

        {/* Pass/Fail badge */}
        <span className={`badge ${isOk ? "badge-success" : "badge-danger"}`}>
          {isOk ? <><CheckSmIcon /> PASS</> : <><XSmIcon /> EMPTY</>}
        </span>

        {/* Expand toggle */}
        {cte.sql && (
          <button style={S.cteExpandBtn} onClick={(e) => { e.stopPropagation(); onToggle(); }}>
            <ChevronIcon up={isExpanded} />
          </button>
        )}
      </div>

      {/* Expanded SQL panel */}
      {isExpanded && cte.sql && (
        <div style={S.cteExpandPanel} className="animate-fade-in">
          <div style={S.cteExpandLabel}>SQL</div>
          <pre style={S.cteSql}>{cte.sql}</pre>
        </div>
      )}
    </div>
  );
}

/* Root cause card */
function RootCauseCard({ rootCause, diagnosticResults }) {
  const primary = diagnosticResults?.[0];

  return (
    <div style={S.rootCard}>
      {/* Header */}
      <div style={S.rootHeader}>
        <div style={S.rootHeaderIcon}><AlertTriangleIcon /></div>
        <div>
          <div style={S.rootHeaderLabel}>Root Cause Analysis</div>
          <div style={S.rootHeaderTitle}>
            {primary?.cte_name
              ? `CTE "${primary.cte_name}" returns 0 rows`
              : "Diagnosis Complete"}
          </div>
        </div>
      </div>

      {(primary?.likely_cause || rootCause) && (
        <div style={S.rootCauseSummary}>
          {primary?.likely_cause || rootCause}
        </div>
      )}

      {primary && (
        <>
          <div style={S.rootGrid}>
            {(() => {
              const rows = [];
              if (primary.failure_type) {
                rows.push({
                  label: "Failure Type",
                  content: (
                    <span style={{
                      fontFamily: "var(--font-mono)", color: "var(--danger)",
                      textTransform: "uppercase", fontSize: "0.8rem", fontWeight: 700,
                    }}>
                      {primary.failure_type}
                    </span>
                  ),
                });
              }
              if (primary.likely_cause) {
                rows.push({ label: "Likely Cause", content: primary.likely_cause });
              }
              if (primary.condition_line_number) {
                rows.push({
                  label: "Dataset Query Line",
                  content: (
                    <span style={{
                      fontFamily: "var(--font-mono)", color: "var(--accent)",
                      fontSize: "0.85rem", fontWeight: 700,
                    }}>
                      Line {primary.condition_line_number}
                    </span>
                  ),
                });
              }
              if (primary.failure_condition) {
                rows.push({
                  label: "Failing Condition",
                  content: <pre style={S.conditionPre}>{primary.failure_condition}</pre>,
                });
              }
              return rows.map((row, i) => (
                <div key={i} style={{ ...S.detailRow, borderBottom: i === rows.length - 1 ? "none" : S.detailRow.borderBottom }}>
                  <div style={S.detailLabel}>{row.label}</div>
                  <div style={S.detailValue}>{row.content}</div>
                </div>
              ));
            })()}
          </div>

          {/* ── Threshold Suggestions ── */}
          {primary.threshold_suggestions?.length > 0 && (
            <ThresholdSuggestions suggestions={primary.threshold_suggestions} />
          )}

          {/* ── Data Availability (UNKNOWN case) ── */}
          {primary.data_availability && Object.keys(primary.data_availability).length > 0 && (
            <DataAvailabilityPanel da={primary.data_availability} />
          )}
        </>
      )}

      {!primary && !rootCause && (
        <p style={{ color: "var(--text-muted)", fontFamily: "var(--font-mono)", fontSize: "0.85rem" }}>
          Diagnosis inconclusive — could not pinpoint root cause.
          Check the CTE waterfall above for the first empty CTE.
        </p>
      )}

      {diagnosticResults.length > 1 && (
        <div style={{ marginTop: 24 }}>
          <div style={S.extraResultsLabel}>All Diagnosed CTEs</div>
          {diagnosticResults.map((r, i) => (
            <div key={i} style={S.extraResultRow}>
              <span style={{ fontFamily: "var(--font-mono)", color: "var(--accent)", fontSize: "0.8rem" }}>
                {r.cte_name}
              </span>
              <span style={{ color: "var(--text-muted)", fontSize: "0.8rem" }}>
                {r.failure_type && <span style={S.failureTypePill}>{r.failure_type}</span>}
                {r.condition_line_number && (
                  <span style={{ fontFamily: "var(--font-mono)", color: "var(--warning)", fontWeight: 600 }}>
                    Line {r.condition_line_number}
                  </span>
                )}
                {r.likely_cause}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

/* ── Threshold Suggestions Panel ── */
function ThresholdSuggestions({ suggestions }) {
  return (
    <div style={S.suggestionsPanel}>
      <div style={S.suggestionsPanelHeader}>
        <span style={S.suggestionsPanelIcon}>📊</span>
        <span style={S.suggestionsPanelTitle}>Threshold Suggestions</span>
        <span style={{ ...S.failureTypePill, background: "var(--warning-dim)", color: "var(--warning)" }}>
          {suggestions.length} column{suggestions.length > 1 ? "s" : ""} analysed
        </span>
      </div>

      {suggestions.map((s, i) => (
        <div key={i} style={S.suggestionRow}>
          {/* Column name + param names */}
          <div style={S.suggestionColHeader}>
            <span style={S.suggestionColName}>
              {s.column}
              {(s.param_min || s.param_max) && (
                <span style={S.suggestionParam}>
                  {" ("}
                  {[s.param_min, s.param_max].filter(Boolean).join(" / ")}
                  {")"}
                </span>
              )}
            </span>
          </div>

          {/* Current vs Actual */}
          <div style={S.suggestionGrid}>
            <div style={S.suggestionBox}>
              <div style={S.suggestionBoxLabel}>Current Threshold</div>
              <div style={S.suggestionBoxValue}>
                {s.current_min != null ? `≥ ${fmt(s.current_min)}` : "—"}
                {s.current_min != null && s.current_max != null && "  ·  "}
                {s.current_max != null ? `≤ ${fmt(s.current_max)}` : ""}
              </div>
            </div>

            {s.data_min != null && (
              <div style={{ ...S.suggestionBox, background: "var(--success-dim)", borderColor: "#6ee7b7" }}>
                <div style={S.suggestionBoxLabel}>Actual Data Range</div>
                <div style={{ ...S.suggestionBoxValue, color: "var(--success)" }}>
                  {fmt(s.data_min)} → {fmt(s.data_max)}
                </div>
                {s.data_p25 != null && (
                  <div style={{ fontSize: "0.72rem", color: "var(--text-muted)", marginTop: 4 }}>
                    P25: {fmt(s.data_p25)}  ·  P75: {fmt(s.data_p75)}
                    {s.data_total_rows != null && `  ·  ${s.data_total_rows.toLocaleString()} rows`}
                  </div>
                )}
              </div>
            )}

            {(s.tshld_min != null || s.tshld_max != null || s.tshld_curr != null) && (
              <div style={{ ...S.suggestionBox, background: "var(--warning-dim)", borderColor: "var(--warning)" }}>
                <div style={S.suggestionBoxLabel}>Allowed Range (KDD_TSHLD)</div>
                <div style={{ display: "flex", gap: 12, marginTop: 4 }}>
                  {[
                    { label: "Minimum", val: s.tshld_min, color: "var(--warning)" },
                    { label: "Maximum", val: s.tshld_max, color: "var(--warning)" },
                    { label: "Current", val: s.tshld_curr, color: "var(--text-secondary)" },
                  ].map(({ label, val, color }) => (
                    <div key={label}>
                      <div style={{ fontSize: "0.68rem", color: "var(--text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>{label}</div>
                      <div style={{ fontSize: "0.95rem", fontWeight: 600, color: val != null ? color : "var(--text-muted)" }}>
                        {val != null ? fmt(val) : "—"}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>


          {/* Suggestion text — strip the KDD_TSHLD range line (now shown in the visual box above) */}
          {s.suggestion && (() => {
            const text = s.suggestion
              .split('\n')
              .filter(l => !l.trimStart().startsWith('Allowed range (KDD_TSHLD)'))
              .join('\n')
              .trim();
            return text ? (
              <div style={S.suggestionText}>
                <pre style={{ fontFamily: "var(--font-body)", whiteSpace: "pre-wrap",
                  fontSize: "0.82rem", color: "var(--text-secondary)", margin: 0 }}>
                  {text}
                </pre>
              </div>
            ) : null;
          })()}
        </div>
      ))}
    </div>
  );
}

/* ── Data Availability Panel (UNKNOWN case) ── */
function DataAvailabilityPanel({ da }) {
  if (!da || Object.keys(da).length === 0) return null;

  return (
    <div style={S.dataAvailPanel}>
      <div style={S.dataAvailHeader}>
        <span style={S.suggestionsPanelIcon}>🔍</span>
        <span style={S.suggestionsPanelTitle}>Data Availability Analysis</span>
      </div>

      {da.explanation && (
        <div style={S.dataAvailExplanation}>{da.explanation}</div>
      )}

      {/* Inner HAVING drill */}
      {da.having_drill?.length > 0 && (
        <div style={{ marginTop: 12 }}>
          <div style={{ fontSize: "0.75rem", fontWeight: 700, color: "var(--text-muted)",
            textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 8 }}>
            Inner HAVING Conditions
          </div>
          {da.having_drill.map((h, i) => (
            <div key={i} style={{
              ...S.havingRow,
              borderLeft: `3px solid ${h.kills_rows ? "var(--danger)" : "var(--success)"}`,
              background: h.kills_rows ? "var(--danger-dim)" : "var(--success-dim)",
            }}>
              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <span style={{ fontSize: "0.85rem" }}>{h.kills_rows ? "❌" : "✅"}</span>
                <pre style={{ fontFamily: "var(--font-mono)", fontSize: "0.75rem",
                  whiteSpace: "pre-wrap", margin: 0, flex: 1,
                  color: h.kills_rows ? "var(--danger)" : "var(--success)" }}>
                  {h.condition}
                </pre>
                <span style={{ fontSize: "0.72rem", color: "var(--text-muted)", whiteSpace: "nowrap" }}>
                  {h.rows_before?.toLocaleString()} → {h.rows_after?.toLocaleString()}
                </span>
              </div>
              {h.kills_rows && h.likely_cause && (
                <div style={{ marginTop: 6, paddingLeft: 28, fontSize: "0.8rem",
                  color: "var(--danger)", fontStyle: "italic" }}>
                  {h.likely_cause}
                </div>
              )}
              {h.threshold_suggestions?.length > 0 && (
                <div style={{ marginTop: 8, paddingLeft: 28 }}>
                  <ThresholdSuggestions suggestions={h.threshold_suggestions} />
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Column stats for UNKNOWN combination case */}
      {da.column_stats?.length > 0 && (
        <div style={{ marginTop: 12 }}>
          <div style={{ fontSize: "0.75rem", fontWeight: 700, color: "var(--text-muted)",
            textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 8 }}>
            Column Distribution (base data)
          </div>
          <table style={S.statsTable}>
            <thead>
              <tr>
                {["Column", "Rows", "Min", "Max", "P25", "P75"].map(h => (
                  <th key={h} style={S.statsTh}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {da.column_stats.map((s, i) => (
                <tr key={i} style={{ background: i % 2 === 0 ? "transparent" : "var(--bg-elevated)" }}>
                  <td style={{ ...S.statsTd, fontFamily: "var(--font-mono)", color: "var(--accent)" }}>{s.column}</td>
                  <td style={S.statsTd}>{s.total_rows?.toLocaleString()}</td>
                  <td style={S.statsTd}>{fmt(s.min_val)}</td>
                  <td style={S.statsTd}>{fmt(s.max_val)}</td>
                  <td style={S.statsTd}>{fmt(s.p25)}</td>
                  <td style={S.statsTd}>{fmt(s.p75)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* UNION ALL branch row counts */}
      {da.union_all_branch_counts?.length > 0 && (
        <div style={{ marginTop: 14 }}>
          <div style={{ fontSize: "0.75rem", fontWeight: 700, color: "var(--text-muted)",
            textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 8 }}>
            UNION ALL Branch Analysis
          </div>
          {da.union_all_branch_counts.map((b, i) => (
            <div key={i} style={{
              marginBottom: 6,
              border: `1px solid ${b.row_count === 0 ? "var(--danger)" : "var(--border)"}`,
              borderRadius: 6,
              overflow: "hidden",
            }}>
              {/* Branch header row */}
              <div style={{
                display: "flex", alignItems: "center", gap: 10,
                padding: "6px 10px",
                background: b.row_count === 0 ? "var(--danger-dim)" : "var(--bg-elevated)",
              }}>
                <span style={{ fontSize: "0.75rem", color: "var(--text-muted)", minWidth: 50 }}>
                  Branch #{b.branch_num}
                </span>
                <span style={{ fontSize: "0.78rem", flex: 1, display: "flex",
                  flexDirection: "column", gap: 1 }}>
                  {b.branch_label && (
                    <span style={{ color: "var(--text-primary)", fontWeight: 600 }}>
                      {b.branch_label}
                    </span>
                  )}
                  <span style={{ fontFamily: "var(--font-mono)",
                    color: "var(--accent)", fontSize: "0.73rem" }}>
                    {b.from_table}
                  </span>
                </span>
                <span style={{ fontWeight: 700, fontSize: "0.82rem",
                  color: b.row_count === 0 ? "var(--danger)" : "var(--success)" }}>
                  {b.row_count === 0 ? "0 rows ❌" : `${b.row_count.toLocaleString()} rows ✅`}
                </span>
              </div>

              {/* Failure detail for zero-count branches */}
              {b.row_count === 0 && b.failure_analysis && (
                <div style={{ padding: "8px 12px", borderTop: "1px solid var(--border)" }}>

                  {/* Source table counts */}
                  {b.failure_analysis.source_counts?.length > 0 && (
                    <div style={{ marginBottom: 8 }}>
                      <div style={{ fontSize: "0.72rem", fontWeight: 600,
                        color: "var(--text-muted)", marginBottom: 4 }}>
                        Source table row counts
                      </div>
                      <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
                        {b.failure_analysis.source_counts.map((s, si) => (
                          <span key={si} style={{
                            fontFamily: "var(--font-mono)", fontSize: "0.75rem",
                            padding: "2px 8px", borderRadius: 4,
                            background: s.row_count === 0 ? "var(--danger-dim)" : "var(--bg-card)",
                            color: s.row_count === 0 ? "var(--danger)" : "var(--text-primary)",
                            border: `1px solid ${s.row_count === 0 ? "var(--danger)" : "var(--border)"}`,
                          }}>
                            {s.table}: {s.row_count == null ? "?" : s.row_count.toLocaleString()}
                            {s.row_count === 0 ? " ❌" : ""}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Explanation */}
                  {b.failure_analysis.explanation && (
                    <div style={{ fontSize: "0.8rem", color: "var(--danger)",
                      fontStyle: "italic", marginBottom: 6 }}>
                      {b.failure_analysis.explanation}
                    </div>
                  )}

                  {/* WHERE condition drill */}
                  {b.failure_analysis.where_analysis?.length > 0 && (
                    <div>
                      <div style={{ fontSize: "0.72rem", fontWeight: 600,
                        color: "var(--text-muted)", marginBottom: 4 }}>
                        WHERE condition analysis
                        {b.failure_analysis.where_analysis[0]?.rows_without_this_cond !== undefined
                          ? " (rows when this condition is removed)"
                          : " (rows before → after each condition)"}
                      </div>
                      {b.failure_analysis.where_analysis.map((w, wi) => (
                        <div key={wi} style={{
                          display: "flex", alignItems: "flex-start", gap: 8,
                          padding: "3px 0",
                          borderLeft: `3px solid ${w.kills_rows ? "var(--danger)" : "var(--success)"}`,
                          paddingLeft: 8, marginBottom: 3,
                          background: w.kills_rows ? "var(--danger-dim)" : "transparent",
                          borderRadius: "0 4px 4px 0",
                        }}>
                          <span style={{ fontSize: "0.8rem", flexShrink: 0 }}>
                            {w.kills_rows ? "❌" : "✅"}
                          </span>
                          <pre style={{
                            margin: 0, flex: 1, fontFamily: "var(--font-mono)",
                            fontSize: "0.72rem", whiteSpace: "pre-wrap",
                            color: w.kills_rows ? "var(--danger)" : "var(--text-secondary)",
                          }}>
                            {w.condition}
                          </pre>
                          <span style={{ fontSize: "0.7rem", color: "var(--text-muted)",
                            whiteSpace: "nowrap", flexShrink: 0 }}>
                            {w.rows_without_this_cond !== undefined
                              ? `without: ${w.rows_without_this_cond?.toLocaleString()} rows`
                              : w.rows_after?.toLocaleString() != null
                                ? `→ ${w.rows_after.toLocaleString()}`
                                : ""}
                          </span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Source view / calendar info */}
      {da.source_view_info?.length > 0 && (
        <div style={{ marginTop: 14 }}>
          <div style={{ fontSize: "0.75rem", fontWeight: 700, color: "var(--text-muted)",
            textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 8 }}>
            Source Table / View Row Counts
          </div>
          <table style={S.statsTable}>
            <thead>
              <tr>
                {["Table / View", "Rows"].map(h => (
                  <th key={h} style={S.statsTh}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {da.source_view_info.map((v, i) => (
                <React.Fragment key={i}>
                  <tr style={{ background: i % 2 === 0 ? "transparent" : "var(--bg-elevated)" }}>
                    <td style={{ ...S.statsTd, fontFamily: "var(--font-mono)", color: "var(--accent)" }}>
                      {v.name}
                    </td>
                    <td style={{
                      ...S.statsTd, fontWeight: 600, textAlign: "right",
                      color: v.row_count === 0 ? "var(--danger)" : "var(--text-primary)"
                    }}>
                      {v.row_count == null
                        ? <span style={{ color: "var(--text-muted)" }}>error</span>
                        : v.row_count === 0
                          ? "0 ❌"
                          : v.row_count.toLocaleString()}
                    </td>
                  </tr>
                  {v.clndr_data && (
                    <tr style={{ background: "var(--bg-elevated)" }}>
                      <td colSpan={2} style={{ ...S.statsTd, paddingLeft: 24 }}>
                        {Object.entries(v.clndr_data).map(([k, val]) => (
                          <span key={k} style={{ marginRight: 16, fontSize: "0.8rem" }}>
                            <strong style={{ color: "var(--text-muted)" }}>{k}:</strong>{" "}
                            <span style={{ fontFamily: "var(--font-mono)" }}>{val ?? "—"}</span>
                          </span>
                        ))}
                      </td>
                    </tr>
                  )}
                </React.Fragment>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Join data availability */}
      {da.joined_table && (
        <div style={S.dataAvailExplanation}>
          <strong>Joined table:</strong> {da.joined_table}
          {da.total_rows != null && ` — ${da.total_rows.toLocaleString()} total rows`}
          {da.date_message && <div style={{ marginTop: 4 }}>{da.date_message}</div>}
        </div>
      )}
    </div>
  );
}

function fmt(v) {
  if (v == null) return "—";
  const n = Number(v);
  if (Number.isNaN(n)) return String(v);
  if (Number.isInteger(n)) return n.toLocaleString();
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

/* Detail row inside root cause card */
function DetailRow({ label, children }) {
  return (
    <div style={S.detailRow}>
      <div style={S.detailLabel}>{label}</div>
      <div style={S.detailValue}>{children}</div>
    </div>
  );
}

/* WebSocket status pill */
function WsStatusPill({ status }) {
  const cfg = {
    connecting: { color: "var(--info)",    bg: "var(--info-dim)",    dot: true,  label: "Connecting" },
    live:       { color: "var(--success)", bg: "var(--success-dim)", dot: true,  label: "Live"       },
    closed:     { color: "var(--text-muted)", bg: "var(--bg-overlay)", dot: false, label: "Closed"  },
    error:      { color: "var(--danger)",  bg: "var(--danger-dim)",  dot: false, label: "WS Error"   },
  }[status] || {};

  return (
    <div style={{
      display: "flex", alignItems: "center", gap: 6,
      padding: "4px 10px", borderRadius: "100px",
      background: cfg.bg, border: `1px solid ${cfg.color}22`,
      fontSize: "0.7rem", fontFamily: "var(--font-mono)",
      color: cfg.color, textTransform: "uppercase", letterSpacing: "0.05em",
    }}>
      {cfg.dot && (
        <span style={{
          width: 6, height: 6, borderRadius: "50%",
          background: cfg.color,
          animation: status === "live" ? "pulse 2s ease-in-out infinite" : "none",
        }} />
      )}
      {cfg.label}
    </div>
  );
}

/* Section label */
function SectionLabel({ text }) {
  return (
    <div style={S.sectionLabel}>{text}</div>
  );
}

/* Job status badge */
function JobStatusBadge({ status }) {
  const map = {
    pending:   { cls: "badge-muted",   label: "Pending"   },
    running:   { cls: "badge-info",    label: "Running"   },
    completed: { cls: "badge-success", label: "Completed" },
    failed:    { cls: "badge-danger",  label: "Failed"    },
  };
  const { cls, label } = map[status] || { cls: "badge-muted", label: status };
  return <span className={`badge ${cls}`}>{label}</span>;
}

/* Full-page loading */
function LoadingScreen() {
  return (
    <div style={{ minHeight: "100vh", display: "flex", alignItems: "center",
      justifyContent: "center", flexDirection: "column", gap: 16 }}>
      <div className="spinner" />
      <p style={{ color: "var(--text-muted)", fontFamily: "var(--font-mono)", fontSize: "0.85rem" }}>
        Loading job…
      </p>
    </div>
  );
}

/* Full-page error */
function ErrorScreen({ message, onBack }) {
  return (
    <div style={{ minHeight: "100vh", display: "flex", alignItems: "center",
      justifyContent: "center", flexDirection: "column", gap: 16, padding: 24 }}>
      <div className="alert alert-error" style={{ maxWidth: 480 }}>
        <span>✕</span><span>{message}</span>
      </div>
      <button className="btn btn-secondary" onClick={onBack}>
        <BackIcon /> Back to Dashboard
      </button>
    </div>
  );
}

// STEP_STATUS_CONFIG is defined after the icon components below (avoids TDZ error)

/* ─────────────────────────────────────────────────────────────────────────
   STYLES
   ───────────────────────────────────────────────────────────────────────── */
const S = {
  /* Navbar */
  navbar: {
    background: "var(--bg-surface)",
    borderBottom: "1px solid var(--border)",
    position: "sticky",
    top: 0,
    zIndex: 100,
    backdropFilter: "blur(12px)",
  },
  navInner: {
    maxWidth: "1200px",
    margin: "0 auto",
    padding: "0 24px",
    height: "64px",
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
  },
  navBrand: { display: "flex", alignItems: "center", gap: "12px" },
  navTitle: {
    fontFamily: "var(--font-display)",
    fontWeight: 700,
    fontSize: "1rem",
    display: "block",
    lineHeight: 1.2,
  },
  navVersion: {
    fontSize: "0.65rem",
    color: "var(--text-muted)",
    fontFamily: "var(--font-mono)",
    textTransform: "uppercase",
    letterSpacing: "0.08em",
    display: "block",
  },
  navRight: { display: "flex", alignItems: "center", gap: "12px" },

  /* Job header */
  jobHeader: {
    display: "flex",
    alignItems: "flex-start",
    justifyContent: "space-between",
    flexWrap: "wrap",
    gap: "12px",
    padding: "20px 24px",
    background: "var(--bg-surface)",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-lg)",
    marginTop: 0,
  },
  jobMeta: { display: "flex", flexDirection: "column", gap: 4 },
  jobScenario: {
    fontFamily: "var(--font-display)",
    fontSize: "1.3rem",
    fontWeight: 700,
    color: "var(--text-primary)",
  },
  jobId: { fontSize: "0.75rem", color: "var(--text-muted)", fontFamily: "var(--font-mono)" },
  jobTags: { display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" },
  tag: {
    display: "inline-flex",
    alignItems: "center",
    gap: 5,
    padding: "4px 10px",
    background: "var(--bg-overlay)",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-sm)",
    fontSize: "0.75rem",
    color: "var(--text-secondary)",
    fontFamily: "var(--font-mono)",
  },

  /* Section label */
  sectionLabel: {
    fontSize: "0.7rem",
    fontFamily: "var(--font-mono)",
    textTransform: "uppercase",
    letterSpacing: "0.12em",
    color: "var(--accent)",
    marginBottom: "12px",
    display: "flex",
    alignItems: "center",
    gap: "8px",
  },
  sectionDesc: {
    fontSize: "0.85rem",
    color: "var(--text-muted)",
    marginBottom: "16px",
    fontFamily: "var(--font-mono)",
  },

  /* Pipeline tracker grid */
  trackerGrid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))",
    gap: "12px",
  },

  /* Step card */
  stepCard: {
    display: "flex",
    alignItems: "flex-start",
    gap: "14px",
    padding: "16px",
    background: "var(--bg-surface)",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-md)",
    transition: "var(--transition)",
  },
  stepCardRunning: {
    borderColor: "var(--info)",
    background: "var(--info-dim)",
    boxShadow: "0 0 0 1px var(--info)",
  },
  stepCardCompleted: {
    borderColor: "var(--success)",
  },
  stepCardFailed: {
    borderColor: "var(--danger)",
    background: "var(--danger-dim)",
  },
  stepIcon: {
    width: "34px",
    height: "34px",
    borderRadius: "var(--radius-sm)",
    border: "1px solid",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    flexShrink: 0,
  },
  stepIndex: {
    fontSize: "0.65rem",
    fontFamily: "var(--font-mono)",
    color: "var(--text-muted)",
    letterSpacing: "0.05em",
  },
  stepLabel: {
    fontSize: "0.85rem",
    fontWeight: 600,
  },
  stepDesc: {
    fontSize: "0.75rem",
    color: "var(--text-muted)",
    marginTop: "2px",
  },
  stepOutput: {
    marginTop: "8px",
    padding: "6px 10px",
    background: "var(--bg-overlay)",
    borderRadius: "var(--radius-sm)",
    fontFamily: "var(--font-mono)",
    fontSize: "0.72rem",
    color: "var(--text-secondary)",
    borderLeft: "2px solid var(--accent-dim)",
    wordBreak: "break-word",
  },
  stepBadge: {
    padding: "2px 8px",
    borderRadius: "100px",
    fontSize: "0.65rem",
    fontFamily: "var(--font-mono)",
    textTransform: "uppercase",
    letterSpacing: "0.05em",
    fontWeight: 600,
    border: "1px solid",
    whiteSpace: "nowrap",
    flexShrink: 0,
  },

  /* CTE waterfall */
  waterfall: {
    display: "flex",
    flexDirection: "column",
    gap: 0,
    background: "var(--bg-surface)",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-lg)",
    overflow: "hidden",
  },
  connectorLine: {
    position: "absolute",
    left: "32px",
    top: "100%",
    width: "2px",
    height: "0",   // purely decorative — row gap takes care of spacing
    zIndex: 1,
  },
  cteRow: {
    display: "flex",
    alignItems: "center",
    gap: "16px",
    padding: "14px 20px",
    borderBottom: "1px solid var(--border)",
    cursor: "pointer",
    transition: "var(--transition)",
    userSelect: "none",
  },
  cteRowFailing: {
    background: "rgba(239,68,68,0.04)",
    borderLeftColor: "var(--danger)",
  },
  cteRowExpanded: {
    background: "var(--bg-elevated)",
  },
  cteDot: {
    width: "10px",
    height: "10px",
    borderRadius: "50%",
    flexShrink: 0,
  },
  cteName: {
    flex: 1,
    display: "flex",
    flexDirection: "column",
    gap: "2px",
    minWidth: 0,
  },
  cteIndex: {
    fontSize: "0.65rem",
    fontFamily: "var(--font-mono)",
    color: "var(--text-muted)",
    letterSpacing: "0.05em",
  },
  cteLabel: {
    fontFamily: "var(--font-mono)",
    fontSize: "0.85rem",
    fontWeight: 600,
    overflow: "hidden",
    textOverflow: "ellipsis",
    whiteSpace: "nowrap",
  },
  cteRowCount: {
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-end",
    gap: "1px",
    minWidth: "60px",
  },
  cteExpandBtn: {
    background: "none",
    border: "none",
    color: "var(--text-muted)",
    cursor: "pointer",
    display: "flex",
    alignItems: "center",
    padding: "4px",
    transition: "var(--transition)",
  },
  cteExpandPanel: {
    padding: "0 20px 16px 46px",
    background: "var(--bg-overlay)",
    borderBottom: "1px solid var(--border)",
  },
  cteExpandLabel: {
    fontSize: "0.65rem",
    fontFamily: "var(--font-mono)",
    color: "var(--text-muted)",
    textTransform: "uppercase",
    letterSpacing: "0.1em",
    padding: "10px 0 6px",
  },
  cteSql: {
    fontFamily: "var(--font-mono)",
    fontSize: "0.78rem",
    color: "var(--text-secondary)",
    background: "var(--bg-surface)",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-sm)",
    padding: "12px",
    overflowX: "auto",
    whiteSpace: "pre-wrap",
    wordBreak: "break-all",
    lineHeight: 1.7,
    margin: 0,
  },

  /* Root cause card */
  rootCard: {
    background: "var(--bg-surface)",
    border: "1px solid var(--danger)",
    borderRadius: "var(--radius-lg)",
    padding: "24px",
    boxShadow: "0 0 32px rgba(239,68,68,0.08)",
  },
  rootHeader: {
    display: "flex",
    alignItems: "flex-start",
    gap: "16px",
  },
  rootHeaderIcon: {
    width: "44px",
    height: "44px",
    borderRadius: "var(--radius-md)",
    background: "var(--danger-dim)",
    border: "1px solid var(--danger)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    color: "var(--danger)",
    flexShrink: 0,
  },
  rootHeaderLabel: {
    fontSize: "0.7rem",
    fontFamily: "var(--font-mono)",
    color: "var(--danger)",
    textTransform: "uppercase",
    letterSpacing: "0.1em",
    marginBottom: "4px",
  },
  rootHeaderTitle: {
    fontFamily: "var(--font-display)",
    fontSize: "1.2rem",
    fontWeight: 700,
    color: "var(--text-primary)",
  },
  rootCauseSummary: {
    fontSize: "0.9rem",
    color: "var(--text-secondary)",
    lineHeight: 1.6,
    marginTop: "16px",
    marginBottom: "20px",
    padding: "14px 16px",
    background: "var(--bg-overlay)",
    borderRadius: "var(--radius-md)",
    fontFamily: "var(--font-mono)",
  },
  rootSummary: {
    fontSize: "0.9rem",
    color: "var(--text-secondary)",
    lineHeight: 1.7,
    marginBottom: "20px",
    padding: "14px 16px",
    background: "var(--bg-overlay)",
    borderRadius: "var(--radius-md)",
    borderLeft: "3px solid var(--danger)",
    fontFamily: "var(--font-mono)",
  },
  rootGrid: {
    display: "flex",
    flexDirection: "column",
    gap: "0",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-md)",
    overflow: "hidden",
  },
  detailRow: {
    display: "grid",
    gridTemplateColumns: "160px 1fr",
    gap: "16px",
    padding: "14px 16px",
    borderBottom: "1px solid var(--border)",
    alignItems: "flex-start",
  },
  detailLabel: {
    fontSize: "0.75rem",
    fontFamily: "var(--font-mono)",
    color: "var(--text-muted)",
    textTransform: "uppercase",
    letterSpacing: "0.08em",
    paddingTop: "2px",
  },
  detailValue: {
    fontSize: "0.875rem",
    color: "var(--text-secondary)",
    lineHeight: 1.6,
  },
  conditionPre: {
    margin: 0,
    fontFamily: "var(--font-mono)",
    fontSize: "0.78rem",
    color: "var(--text-secondary)",
    background: "var(--bg-overlay)",
    border: "1px solid var(--border)",
    borderRadius: "var(--radius-sm)",
    padding: "10px 12px",
    overflowX: "auto",
    whiteSpace: "pre-wrap",
    wordBreak: "break-all",
    lineHeight: 1.6,
  },
  extraResultsLabel: {
    fontSize: "0.7rem",
    fontFamily: "var(--font-mono)",
    color: "var(--text-muted)",
    textTransform: "uppercase",
    letterSpacing: "0.1em",
    marginBottom: "8px",
  },
  extraResultRow: {
    display: "flex",
    flexDirection: "column",
    gap: "4px",
    padding: "10px 0",
    borderBottom: "1px solid var(--border)",
  },
  failureTypePill: {
    display: "inline-block",
    padding: "1px 7px",
    background: "var(--danger-dim)",
    color: "var(--danger)",
    borderRadius: "4px",
    fontSize: "0.7rem",
    fontFamily: "var(--font-mono)",
    fontWeight: 700,
    textTransform: "uppercase",
    marginRight: "8px",
  },

  /* Threshold Suggestions panel */
  suggestionsPanel: {
    marginTop: 24,
    border: "1px solid #fcd34d",
    borderRadius: "var(--radius-md)",
    overflow: "hidden",
  },
  suggestionsPanelHeader: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    padding: "10px 16px",
    background: "var(--warning-dim)",
    borderBottom: "1px solid #fcd34d",
  },
  suggestionsPanelIcon: { fontSize: "1rem" },
  suggestionsPanelTitle: {
    fontWeight: 700,
    fontSize: "0.85rem",
    color: "var(--text-primary)",
    flex: 1,
  },
  suggestionRow: {
    padding: "12px 16px",
    borderBottom: "1px solid var(--border)",
  },
  suggestionColHeader: {
    display: "flex",
    alignItems: "center",
    gap: 10,
    marginBottom: 8,
  },
  suggestionColName: {
    fontFamily: "var(--font-mono)",
    fontWeight: 700,
    fontSize: "0.9rem",
    color: "var(--accent)",
  },
  suggestionParam: {
    fontFamily: "var(--font-mono)",
    fontSize: "0.72rem",
    color: "var(--text-muted)",
    background: "var(--bg-overlay)",
    padding: "2px 8px",
    borderRadius: "4px",
  },
  suggestionGrid: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: 8,
    marginBottom: 8,
  },
  suggestionBox: {
    padding: "8px 12px",
    background: "var(--danger-dim)",
    border: "1px solid #fca5a5",
    borderRadius: "var(--radius-sm)",
  },
  suggestionBoxLabel: {
    fontSize: "0.68rem",
    fontWeight: 700,
    color: "var(--text-muted)",
    textTransform: "uppercase",
    letterSpacing: "0.06em",
    marginBottom: 3,
  },
  suggestionBoxValue: {
    fontFamily: "var(--font-mono)",
    fontSize: "0.85rem",
    fontWeight: 700,
    color: "var(--danger)",
  },
  suggestionText: {
    padding: "8px 10px",
    background: "var(--bg-overlay)",
    borderRadius: "var(--radius-sm)",
    border: "1px solid var(--border)",
  },

  /* Data Availability panel */
  dataAvailPanel: {
    marginTop: 20,
    border: "1px solid #7dd3fc",
    borderRadius: "var(--radius-md)",
    overflow: "hidden",
  },
  dataAvailHeader: {
    display: "flex",
    alignItems: "center",
    gap: 8,
    padding: "10px 16px",
    background: "var(--info-dim)",
    borderBottom: "1px solid #7dd3fc",
  },
  dataAvailExplanation: {
    padding: "10px 16px",
    fontSize: "0.85rem",
    color: "var(--text-secondary)",
    lineHeight: 1.6,
  },
  havingRow: {
    margin: "0 16px 8px",
    padding: "8px 12px",
    borderRadius: "var(--radius-sm)",
  },

  /* Stats table */
  statsTable: {
    width: "100%",
    borderCollapse: "collapse",
    fontSize: "0.8rem",
    margin: "0 0 8px",
  },
  statsTh: {
    textAlign: "left",
    padding: "6px 12px",
    background: "var(--bg-overlay)",
    color: "var(--text-muted)",
    fontWeight: 700,
    fontSize: "0.7rem",
    textTransform: "uppercase",
    letterSpacing: "0.05em",
    borderBottom: "1px solid var(--border)",
  },
  statsTd: {
    padding: "6px 12px",
    color: "var(--text-secondary)",
    fontFamily: "var(--font-mono)",
    fontSize: "0.78rem",
    borderBottom: "1px solid var(--border)",
  },

  /* Alert success box */
  alertSuccessBox: {
    display: "flex",
    alignItems: "flex-start",
    gap: "20px",
    padding: "24px",
    background: "var(--success-dim)",
    border: "1px solid var(--success)",
    borderRadius: "var(--radius-lg)",
  },
  alertSuccessIcon: {
    color: "var(--success)",
    flexShrink: 0,
  },
  alertSuccessTitle: {
    fontFamily: "var(--font-display)",
    fontSize: "1.1rem",
    fontWeight: 700,
    color: "var(--success)",
    marginBottom: "6px",
  },
  alertSuccessDesc: {
    fontSize: "0.875rem",
    color: "var(--text-secondary)",
    lineHeight: 1.6,
  },

  /* Running hint */
  runningHint: {
    display: "flex",
    alignItems: "center",
    gap: "12px",
    padding: "14px 18px",
    background: "var(--info-dim)",
    border: "1px solid var(--info)",
    borderRadius: "var(--radius-md)",
    fontSize: "0.875rem",
    color: "var(--info)",
    fontFamily: "var(--font-mono)",
  },
};

/* ─────────────────────────────────────────────────────────────────────────
   ICONS
   ───────────────────────────────────────────────────────────────────────── */
const LogoIcon = () => (
  <svg width="28" height="28" viewBox="0 0 32 32" fill="none">
    <path d="M4 8h24M4 16h16M4 24h20" stroke="#2563eb" strokeWidth="2.5" strokeLinecap="round"/>
    <circle cx="26" cy="24" r="4" fill="#2563eb" opacity="0.25" stroke="#2563eb" strokeWidth="1.5"/>
  </svg>
);

const BackIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <polyline points="15 18 9 12 15 6"/>
  </svg>
);

const RerunIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <polyline points="1 4 1 10 7 10"/>
    <path d="M3.51 15a9 9 0 1 0 .49-3.51"/>
  </svg>
);

const PdfIcon = () => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
    <polyline points="14 2 14 8 20 8"/>
    <line x1="9" y1="13" x2="15" y2="13"/><line x1="9" y1="17" x2="12" y2="17"/>
  </svg>
);

const CalendarIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/>
    <line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
  </svg>
);

const UserIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/>
    <circle cx="12" cy="7" r="4"/>
  </svg>
);

const CheckSmIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="3" strokeLinecap="round">
    <polyline points="20 6 9 17 4 12"/>
  </svg>
);

const XSmIcon = () => (
  <svg width="12" height="12" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="3" strokeLinecap="round">
    <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
  </svg>
);

const DotIcon = () => (
  <svg width="8" height="8" viewBox="0 0 8 8">
    <circle cx="4" cy="4" r="3" fill="currentColor"/>
  </svg>
);

const ChevronIcon = ({ up }) => (
  <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round"
    style={{ transform: up ? "rotate(180deg)" : "none", transition: "var(--transition)" }}>
    <polyline points="6 9 12 15 18 9"/>
  </svg>
);

const AlertTriangleIcon = () => (
  <svg width="22" height="22" viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
    <line x1="12" y1="9" x2="12" y2="13"/>
    <line x1="12" y1="17" x2="12.01" y2="17"/>
  </svg>
);

const CheckCircleIcon = ({ size = 20 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
    stroke="currentColor" strokeWidth="2" strokeLinecap="round">
    <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
    <polyline points="22 4 12 14.01 9 11.01"/>
  </svg>
);

/* ─────────────────────────────────────────────────────────────────────────
   STEP STATUS CONFIG
   Defined here (after icons) to avoid TDZ — const arrow functions are not
   hoisted, so referencing them before definition crashes at runtime.
   ───────────────────────────────────────────────────────────────────────── */
const STEP_STATUS_CONFIG = {
  idle: {
    color: "var(--text-muted)",
    bg: "var(--bg-overlay)",
    border: "var(--border)",
    label: "Waiting",
    icon: <DotIcon />,
  },
  running: {
    color: "var(--info)",
    bg: "var(--info-dim)",
    border: "var(--info)",
    label: "Running",
    icon: null,
  },
  completed: {
    color: "var(--success)",
    bg: "var(--success-dim)",
    border: "var(--success)",
    label: "Done",
    icon: <CheckSmIcon />,
  },
  failed: {
    color: "var(--danger)",
    bg: "var(--danger-dim)",
    border: "var(--danger)",
    label: "Failed",
    icon: <XSmIcon />,
  },
};
