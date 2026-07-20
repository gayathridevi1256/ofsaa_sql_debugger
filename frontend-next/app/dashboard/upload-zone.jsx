"use client";

import { useState, useRef } from "react";
import { filesAPI, jobsAPI, getErrorMessage } from "@/lib/api-client";

export function UploadZone({ onJobStarted }) {
  const [dragging, setDragging] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);
  const [error, setError] = useState("");
  const fileRef = useRef(null);

  const handleFile = async (file) => {
    if (!file) return;
    setUploading(true);
    setError("");
    setProgress(0);
    try {
      const uploaded = await filesAPI.uploadLog(file, setProgress);
      const result = await jobsAPI.runPipeline(uploaded.file_path);
      if (result.cached) {
        window.location.href = `/jobs/${result.cached_job_id}`;
      } else {
        window.location.href = `/jobs/${result.job_id}`;
      }
      onJobStarted?.();
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setUploading(false);
    }
  };

  const handleDrop = (e) => {
    e.preventDefault();
    setDragging(false);
    handleFile(e.dataTransfer.files[0]);
  };

  return (
    <div className="card animate-fade-in" style={{ marginBottom: 32 }}>
      <h2 style={{ fontSize: "1rem", fontWeight: 600, marginBottom: 12 }}>Upload Log File</h2>
      {error && <div className="alert alert-error" style={{ marginBottom: 12 }}>{error}</div>}
      <div
        onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
        onDragLeave={() => setDragging(false)}
        onDrop={handleDrop}
        style={{
          border: `2px dashed ${dragging ? "var(--accent)" : "var(--border)"}`,
          borderRadius: "var(--radius-md)", padding: 32, textAlign: "center",
          background: dragging ? "var(--accent-subtle)" : "var(--bg-elevated)",
          cursor: "pointer", transition: "all 0.15s",
        }}
        onClick={() => fileRef.current?.click()}
      >
        <input ref={fileRef} type="file" accept=".log,.txt" style={{ display: "none" }} onChange={(e) => handleFile(e.target.files[0])} />
        {uploading ? (
          <div>
            <div className="spinner" style={{ margin: "0 auto 12px" }} />
            <div style={{ fontSize: "0.875rem", color: "var(--text-muted)" }}>Uploading… {progress}%</div>
            <div style={{ width: "100%", height: 4, background: "var(--border)", borderRadius: 2, marginTop: 8 }}>
              <div style={{ width: `${progress}%`, height: "100%", background: "var(--accent)", borderRadius: 2, transition: "width 0.2s" }} />
            </div>
          </div>
        ) : (
          <>
            <div style={{ fontSize: "2rem", marginBottom: 8 }}>📄</div>
            <div style={{ fontWeight: 600 }}>Drop your .log file here or click to browse</div>
            <div style={{ fontSize: "0.75rem", color: "var(--text-muted)", marginTop: 4 }}>Max 50MB</div>
          </>
        )}
      </div>
    </div>
  );
}
