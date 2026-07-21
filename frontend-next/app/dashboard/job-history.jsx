"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { jobsAPI } from "@/lib/api-client";

const STATUS_MAP = {
  pending: { label: "Pending", cls: "badge-muted" },
  running: { label: "Running", cls: "badge-warning" },
  completed: { label: "Completed", cls: "badge-success" },
  failed: { label: "Failed", cls: "badge-danger" },
};

export function JobHistory({ jobs, loading, error }) {
  const router = useRouter();
  const [exportingId, setExportingId] = useState(null);

  const handleExport = async (e, job) => {
    e.stopPropagation();
    setExportingId(job.job_id);
    try {
      await jobsAPI.downloadReport(job.job_id);
    } catch {
      alert("Failed to export PDF. Please try again.");
    } finally {
      setExportingId(null);
    }
  };

  if (loading) return <div style={{ textAlign: "center", padding: 40 }}><div className="spinner" style={{ margin: "0 auto" }} /></div>;
  if (error) return <div className="alert alert-error">{error}</div>;
  if (!jobs.length) return <div className="card" style={{ textAlign: "center", color: "var(--text-muted)" }}>No jobs yet. Upload a log file to get started.</div>;

  return (
    <div className="card animate-fade-in">
      <h2 style={{ fontSize: "1rem", fontWeight: 600, marginBottom: 16 }}>Recent Jobs</h2>
      <div style={{ overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: "0.82rem" }}>
          <thead>
            <tr style={{ borderBottom: "1px solid var(--border)" }}>
              {["Job ID", "Scenario", "Date", "Status", "Started", ""].map((h, i) => (
                <th key={i} style={{ textAlign: "left", padding: "8px 12px", color: "var(--text-muted)", fontWeight: 600, textTransform: "uppercase", fontSize: "0.7rem", letterSpacing: "0.05em" }}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {jobs.slice(0, 20).map((job) => (
              <tr key={job.job_id} style={{ borderBottom: "1px solid var(--border)", cursor: "pointer" }} onClick={() => router.push(`/jobs/${job.job_id}`)}>
                <td style={{ padding: "10px 12px", fontFamily: "var(--font-mono)", fontSize: "0.75rem", color: "var(--accent)" }}>{job.job_id?.slice(0, 8)}…</td>
                <td style={{ padding: "10px 12px" }}>{job.scenario_name || "—"}</td>
                <td style={{ padding: "10px 12px", fontFamily: "var(--font-mono)", fontSize: "0.75rem" }}>{job.batch_date || "—"}</td>
                <td style={{ padding: "10px 12px" }}><span className={`badge ${STATUS_MAP[job.status]?.cls}`}>{STATUS_MAP[job.status]?.label || job.status}</span></td>
                <td style={{ padding: "10px 12px", fontFamily: "var(--font-mono)", fontSize: "0.75rem" }}>{job.started_at ? new Date(job.started_at).toLocaleString() : "—"}</td>
                <td style={{ padding: "6px 12px" }}>
                  {job.status === "completed" && (
                    <button
                      className="btn btn-secondary btn-sm"
                      onClick={(e) => handleExport(e, job)}
                      disabled={exportingId === job.job_id}
                      style={{ whiteSpace: "nowrap" }}
                    >
                      {exportingId === job.job_id ? "…" : "PDF"}
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
