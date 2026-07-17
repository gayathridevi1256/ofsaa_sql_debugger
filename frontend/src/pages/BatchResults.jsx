/**
 * BatchResults.jsx — Summary page for a batch of pipeline jobs.
 *
 * Receives job IDs via React Router navigation state ({ jobs: [{job_id, filename}] }).
 * Polls each job every 5 seconds until all are finished.
 * Shows a live summary: how many uploaded / generated alerts / have issues.
 */

import React, { useState, useEffect, useRef } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { jobsAPI } from "../api";

export default function BatchResults() {
  const navigate   = useNavigate();
  const location   = useLocation();
  const initJobs   = (location.state?.jobs || []).map(j => ({
    job_id:          j.job_id,
    filename:        j.filename,
    status:          "running",
    alerts_generated: null,
    scenario_name:   null,
    batch_date:      null,
    root_cause:      null,
  }));

  const [jobs,    setJobs]    = useState(initJobs);
  const [stopped, setStopped] = useState(false);
  const timerRef              = useRef(null);

  const fetchAll = async (current) => {
    const updated = await Promise.all(
      current.map(async (j) => {
        if (j.status === "completed" || j.status === "failed") return j;
        try {
          const data = await jobsAPI.getJob(j.job_id);
          return { ...j, ...data };
        } catch {
          return j;
        }
      })
    );
    setJobs(updated);
    if (updated.every(j => j.status === "completed" || j.status === "failed")) {
      setStopped(true);
    }
    return updated;
  };

  useEffect(() => {
    if (!initJobs.length) return;
    let current = initJobs;
    const tick = async () => {
      current = await fetchAll(current);
    };
    tick();
    timerRef.current = setInterval(tick, 5000);
    return () => clearInterval(timerRef.current);
  }, []);

  useEffect(() => {
    if (stopped) clearInterval(timerRef.current);
  }, [stopped]);

  // Summary counters
  const total     = jobs.length;
  const completed = jobs.filter(j => j.status === "completed").length;
  const failed    = jobs.filter(j => j.status === "failed").length;
  const running   = jobs.filter(j => j.status === "running" || j.status === "pending").length;
  const withAlert = jobs.filter(j => j.alerts_generated === 1).length;
  const issues    = jobs.filter(j => j.status === "completed" && j.alerts_generated !== 1).length;

  if (!total) {
    return (
      <div className="page" style={{ display: "flex", alignItems: "center",
        justifyContent: "center", height: "80vh" }}>
        <div style={{ textAlign: "center" }}>
          <p style={{ color: "var(--text-muted)" }}>No batch jobs found.</p>
          <button className="btn btn-primary" style={{ marginTop: 16 }}
            onClick={() => navigate("/")}>
            Back to Dashboard
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="page">
      {/* Navbar */}
      <nav style={S.navbar}>
        <div style={S.navInner}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <button className="btn btn-secondary btn-sm" onClick={() => navigate("/")}>
              ← Dashboard
            </button>
            <span style={{ fontWeight: 700, fontSize: "1rem" }}>
              Batch <span style={{ color: "var(--accent)" }}>Results</span>
            </span>
          </div>
          {!stopped && (
            <div style={{ display: "flex", alignItems: "center", gap: 8,
              color: "var(--text-muted)", fontSize: "0.8rem" }}>
              <div className="spinner spinner-sm" />
              Polling…
            </div>
          )}
        </div>
      </nav>

      <main className="page-content stagger">
        {/* Summary cards */}
        <div style={S.summaryRow}>
          <SummaryCard label="Uploaded"        value={total}     color="var(--accent)" />
          <SummaryCard label="Completed"       value={completed} color="var(--success)" />
          <SummaryCard label="Running"         value={running}   color="var(--text-muted)" />
          <SummaryCard label="Alerts Generated" value={withAlert} color="var(--success)" />
          <SummaryCard label="Issues / No Alert" value={issues}  color="var(--danger)" />
          {failed > 0 && <SummaryCard label="Failed" value={failed} color="var(--danger)" />}
        </div>

        {/* Jobs table */}
        <div className="card" style={{ marginTop: 24, padding: 0, overflow: "hidden" }}>
          <table style={S.table}>
            <thead>
              <tr style={S.thead}>
                {["#", "File", "Scenario", "Batch Date", "Status", "Alerts", "Actions"]
                  .map(h => <th key={h} style={S.th}>{h}</th>)}
              </tr>
            </thead>
            <tbody>
              {jobs.map((job, idx) => (
                <tr key={job.job_id} style={{
                  ...S.tr,
                  background: idx % 2 === 0 ? "transparent" : "rgba(255,255,255,0.01)"
                }}>
                  <td style={{ ...S.td, color: "var(--text-muted)", fontFamily: "var(--font-mono)" }}>
                    {idx + 1}
                  </td>
                  <td style={S.td}>
                    <span style={{ fontFamily: "var(--font-mono)", fontSize: "0.8rem",
                      color: "var(--text-primary)" }}>
                      {job.filename || job.log_filename || "—"}
                    </span>
                  </td>
                  <td style={S.td}>
                    <span style={{ fontFamily: "var(--font-mono)", fontSize: "0.8rem",
                      color: "var(--text-secondary)" }}>
                      {job.scenario_name || "—"}
                    </span>
                  </td>
                  <td style={S.td}>
                    <span style={{ fontFamily: "var(--font-mono)", fontSize: "0.8rem",
                      color: "var(--text-muted)" }}>
                      {job.batch_date || "—"}
                    </span>
                  </td>
                  <td style={S.td}>
                    <StatusBadge status={job.status} queuePos={
                      job.status === "pending"
                        ? jobs.filter(j => j.status === "running").length > 0
                          ? `Queued (#${idx + 1})`
                          : "Queued"
                        : null
                    } />
                  </td>
                  <td style={S.td}>
                    {job.alerts_generated === 1
                      ? <span className="badge badge-success">✓ Yes</span>
                      : job.status === "completed"
                      ? <span className="badge badge-danger">✗ No</span>
                      : <span className="badge badge-muted">—</span>
                    }
                  </td>
                  <td style={S.td}>
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

        {stopped && (
          <div style={{ textAlign: "center", marginTop: 24, color: "var(--text-muted)",
            fontSize: "0.85rem" }}>
            All jobs finished.
          </div>
        )}
      </main>
    </div>
  );
}

function SummaryCard({ label, value, color }) {
  return (
    <div className="card" style={{ flex: 1, textAlign: "center", padding: "20px 16px" }}>
      <div style={{ fontSize: "2rem", fontWeight: 700, color, fontFamily: "var(--font-mono)",
        lineHeight: 1 }}>
        {value}
      </div>
      <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: 6,
        textTransform: "uppercase", letterSpacing: "0.06em", fontFamily: "var(--font-mono)" }}>
        {label}
      </div>
    </div>
  );
}

function StatusBadge({ status, queuePos }) {
  if (queuePos) {
    return (
      <span style={{ display: "inline-flex", alignItems: "center", gap: 4,
        fontSize: "0.75rem", color: "var(--text-muted)" }}>
        <span style={{ width: 6, height: 6, borderRadius: "50%",
          background: "var(--text-muted)", flexShrink: 0 }} />
        {queuePos}
      </span>
    );
  }
  const map = {
    pending:   { cls: "badge-muted",   label: "Pending"   },
    running:   { cls: "badge-info",    label: "Running"   },
    completed: { cls: "badge-success", label: "Completed" },
    failed:    { cls: "badge-danger",  label: "Failed"    },
  };
  const { cls, label } = map[status] || { cls: "badge-muted", label: status };
  return <span className={`badge ${cls}`}>{label}</span>;
}

const S = {
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
  summaryRow: {
    display: "flex",
    gap:     "16px",
    flexWrap: "wrap",
  },
  table: {
    width:          "100%",
    borderCollapse: "collapse",
    fontFamily:     "var(--font-body)",
  },
  thead: {
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
  },
  td: {
    padding:       "14px 16px",
    fontSize:      "0.9rem",
    color:         "var(--text-secondary)",
    verticalAlign: "middle",
  },
};