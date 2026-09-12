import { useState } from "react";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import Icon from "../components/Icons";

export default function Recommendations() {
  const [refreshKey, setRefreshKey] = useState(0);
  const { data: recommendationsData, loading, error } = useApiData(() => api.getRecommendations(), [refreshKey]);
  const recommendations = recommendationsData ?? [];
  const [selectedId, setSelectedId] = useState(null);
  const [running, setRunning] = useState(false);
  const [runError, setRunError] = useState("");

  async function runAgent() {
    setRunning(true);
    setRunError("");
    try {
      await api.runIntelligenceRecommendations();
      setRunning(false);
      setSelectedId(null);
      setRefreshKey((value) => value + 1);
    } catch (err) {
      setRunError(err?.message || "Unable to run Agent 4.");
      setRunning(false);
    }
  }
  const selected = recommendations.find((r) => r.id === selectedId) || recommendations[0];

  return <>
    <PageHeader eyebrow="AGENT 4 · INDUSTRY INTELLIGENCE" title="Recommendations" description="Review deterministic recommendations produced and stored by Agent 28. Human approval remains authoritative for consequential actions." />
    <div className="panel" style={{ marginBottom: 16, padding: 16 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 16 }}>
        <div><strong>Run Intelligence & Recommendations</strong><p style={{ margin: "4px 0 0" }}>Evaluate the current PostgreSQL data and create new pending recommendations.</p></div>
        <button className="primary-button" type="button" onClick={runAgent} disabled={running}>{running ? "Running…" : "Run Agent 4"}</button>
      </div>
      {runError && <div className="empty-state" style={{ marginTop: 12 }}>{runError}</div>}
    </div>
    {loading && <LoadingState message="Loading stored recommendations from the backend…" />}
    {error && <ErrorState message={`Backend connection failed: ${error}`} />}
    {!loading && !error && <div className="recommend-layout">
      <div className="panel">
        <div className="panel-head"><div><h2>Recommended actions</h2><p>{recommendations.length} stored agent recommendation{recommendations.length === 1 ? "" : "s"}</p></div></div>
        <div className="recommend-full-list">
          {recommendations.length === 0 && <div className="empty-state">No stored recommendation outputs were found.</div>}
          {recommendations.map(r => <button className={`recommend-card ${selected?.id === r.id ? "selected" : ""}`} onClick={() => setSelectedId(r.id)} key={r.id}>
            <div className="recommend-card-top"><StatusBadge value={r.status} /><span>{r.requiresApproval ? "Approval required" : "No approval required"}</span></div>
            <strong>{r.title}</strong>
            <p>{r.reason}</p>
            <small>{r.partner}</small>
          </button>)}
        </div>
      </div>
      <div className="panel recommendation-detail">
        {selected ? <>
          <div className="agent-badge"><Icon name="spark" size={18} /> Agent-generated recommendation</div>
          <StatusBadge value={selected.status} />
          <h2>{selected.title}</h2>
          <p className="detail-copy">{selected.reason}</p>
          <div className="action-box"><span>Suggested next action</span><strong>{selected.action}</strong></div>
          <div className="detail-footer"><span>Target</span><strong>{selected.partner}</strong><span>Confidence</span><strong>{selected.confidence == null ? "—" : `${Math.round(selected.confidence * 100)}%`}</strong></div>
        </> : <div className="empty-state">Select a recommendation to inspect it.</div>}
      </div>
    </div>}
  </>;
}
