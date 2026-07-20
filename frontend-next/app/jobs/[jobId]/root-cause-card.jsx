"use client";

export function RootCauseCard({ rootCause, results }) {
  const primary = results?.[0];
  if (!primary && !rootCause) return null;

  return (
    <div className="card" style={{ marginTop: 24, borderLeft: "4px solid var(--danger)" }}>
      <h2 style={{ fontSize: "1rem", fontWeight: 700, marginBottom: 12, display: "flex", alignItems: "center", gap: 8 }}>
        <span style={{ color: "var(--danger)" }}>⚠</span> Root Cause Analysis
      </h2>
      {primary && (
        <>
          <div style={{ padding: 12, background: "var(--danger-dim)", borderRadius: "var(--radius-sm)", marginBottom: 16, fontSize: "0.875rem" }}>
            CTE &quot;{primary.cte_name}&quot; returns 0 rows
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 16 }}>
            {primary.failure_type && (
              <div style={{ display: "flex", gap: 8, fontSize: "0.82rem" }}>
                <span style={{ color: "var(--text-muted)", minWidth: 100 }}>Failure Type</span>
                <span style={{ fontFamily: "var(--font-mono)", color: "var(--danger)", fontWeight: 600 }}>{primary.failure_type}</span>
              </div>
            )}
            {primary.likely_cause && (
              <div style={{ display: "flex", gap: 8, fontSize: "0.82rem" }}>
                <span style={{ color: "var(--text-muted)", minWidth: 100 }}>Likely Cause</span>
                <span>{primary.likely_cause}</span>
              </div>
            )}
            {primary.failure_condition && (
              <div style={{ display: "flex", gap: 8, fontSize: "0.82rem" }}>
                <span style={{ color: "var(--text-muted)", minWidth: 100 }}>Condition</span>
                <pre style={{ fontFamily: "var(--font-mono)", fontSize: "0.72rem", whiteSpace: "pre-wrap", flex: 1 }}>{primary.failure_condition}</pre>
              </div>
            )}
          </div>
        </>
      )}
      {results?.length > 1 && (
        <div>
          <div style={{ fontSize: "0.75rem", fontWeight: 700, color: "var(--text-muted)", textTransform: "uppercase", marginBottom: 8 }}>All Diagnosed CTEs</div>
          {results.map((r, i) => (
            <div key={i} style={{ padding: 8, marginBottom: 4, background: "var(--bg-elevated)", borderRadius: "var(--radius-sm)", fontSize: "0.8rem" }}>
              <span style={{ fontFamily: "var(--font-mono)", color: "var(--accent)", fontWeight: 600 }}>{r.cte_name}</span>
              <span style={{ marginLeft: 12, color: "var(--text-muted)" }}>{r.failure_type}</span>
              {r.likely_cause && <span style={{ marginLeft: 12 }}>{r.likely_cause.slice(0, 100)}...</span>}
            </div>
          ))}
        </div>
      )}
      {!primary && rootCause && <div style={{ fontSize: "0.875rem", fontFamily: "var(--font-mono)" }}>{rootCause}</div>}
    </div>
  );
}
