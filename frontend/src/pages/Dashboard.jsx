import { Link } from "react-router-dom";
import Icon from "../components/Icons";
import StatCard from "../components/StatCard";
import StatusBadge from "../components/StatusBadge";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

export default function Dashboard() {
  const { data, loading, error } = useApiData(() => api.getDashboard(), []);

  if (loading) {
    return <><div className="hero"> <div><div className="eyebrow light">AGENT 28 · COMMAND CENTER</div><h1>Industry Interaction Intelligence</h1><p>Turn MoU commitments into measurable activities, healthy partnerships and accreditation-ready evidence.</p></div></div><LoadingState message="Loading Agent 28 data from the backend…" /></>;
  }
  if (error) {
    return <><div className="hero"><div><div className="eyebrow light">AGENT 28 · COMMAND CENTER</div><h1>Industry Interaction Intelligence</h1><p>Turn MoU commitments into measurable activities, healthy partnerships and accreditation-ready evidence.</p></div></div><ErrorState message={`Backend connection failed: ${error}`} /></>;
  }

  const { partners, mous, activities, health, recommendations } = data;
  const activePartners = partners.filter((p) => p.status === "ACTIVE").length;
  const strong = health.filter((x) => x.band === "STRONG").length;
  const dormant = health.filter((x) => x.dormant).length;
  const avg = health.length ? Math.round(health.reduce((s, x) => s + x.score, 0) / health.length) : 0;
  const renewalRisks = mous.filter((m) => m.renewalRisk).length;
  const recentActivities = activities.slice(0, 5);
  const healthSnapshot = health.slice(0, 6);
  const trackedMous = [...mous].sort((a, b) => Number(b.renewalRisk) - Number(a.renewalRisk) || String(a.validUntil || "").localeCompare(String(b.validUntil || ""))).slice(0, 6);

  return (
    <>
      <div className="hero">
        <div>
          <div className="eyebrow light">AGENT 28 · COMMAND CENTER</div>
          <h1>Industry Interaction Intelligence</h1>
          <p>Turn MoU commitments into measurable activities, healthy partnerships and accreditation-ready evidence.</p>
          <div className="hero-chain">
            <span>Promise</span><i>→</i><span>Do</span><i>→</i><span>Check</span><i>→</i><span>Recommend</span><i>→</i><span>Prove</span>
          </div>
        </div>
        <div className="hero-orb"><Icon name="spark" size={48} /></div>
      </div>

      <div className="stats-grid">
        <StatCard label="Active industry partners" value={activePartners} meta={`${partners.length} total partners`} icon={<Icon name="building" size={20} />} tone="blue" />
        <StatCard label="Active MoUs" value={mous.filter(m => m.rawStatus === "ACTIVE").length} meta={`${renewalRisks} in renewal window without discussion`} icon={<Icon name="file" size={20} />} tone="purple" />
        <StatCard label="Engagement health" value={`${avg}/100`} meta={`${strong} strong`} icon={<Icon name="heart" size={20} />} tone="green" />
        <StatCard label="Recommendations" value={recommendations.length} meta={`${dormant} dormant partner${dormant === 1 ? "" : "s"}`} icon={<Icon name="spark" size={20} />} tone="orange" />
      </div>

      <div className="dashboard-grid">
        <div className="panel wide">
          <div className="panel-head">
            <div><h2>Recent industry activity</h2><p>Latest realised events across partners</p></div>
            <Link to="/activities" className="text-link">View all <Icon name="arrow" size={15} /></Link>
          </div>
          <div className="activity-list">
            {recentActivities.length === 0 && <div className="empty-state">No industry activities found.</div>}
            {recentActivities.map(a => (
              <div className="activity-row" key={a.id}>
                <div className="activity-icon"><Icon name="activity" size={18} /></div>
                <div className="activity-main">
                  <strong>{a.title}</strong>
                  <span>{a.partner} · {a.department} · {formatDate(a.date)}</span>
                </div>
                <div className="activity-right">
                  <span>{a.participants} participants</span>
                  <StatusBadge value={a.status} />
                </div>
              </div>
            ))}
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <div><h2>Health snapshot</h2><p>Current relationship status</p></div>
            <Link to="/health" className="text-link">Details</Link>
          </div>
          <div className="health-summary">
            {healthSnapshot.length === 0 && <div className="empty-state">No health snapshots found.</div>}
            {healthSnapshot.map(h => (
              <div className="health-line" key={h.partnerId}>
                <div className="mini-avatar">{h.partner.slice(0,1)}</div>
                <div className="health-name"><strong>{h.partner}</strong><span>{h.band === "DORMANT" ? "Needs re-engagement" : `${h.days ?? "—"} days since activity`}</span></div>
                <div className={`score ${h.band.toLowerCase()}`}>{h.score}</div>
              </div>
            ))}
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <div><h2>Priority actions</h2><p>Stored Agent 28 recommendations</p></div>
            <Link to="/recommendations" className="text-link">All</Link>
          </div>
          <div className="recommend-list">
            {recommendations.length === 0 && <div className="empty-state">No stored recommendations.</div>}
            {recommendations.slice(0, 3).map(r => (
              <div className="recommend-item" key={r.id}>
                <StatusBadge value={r.status} />
                <strong>{r.title}</strong>
                <span>{r.partner}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="panel wide">
          <div className="panel-head">
            <div><h2>MoU fulfilment</h2><p>Committed deliverables vs confirmed achievement</p></div>
            <Link to="/mous" className="text-link">Open tracker</Link>
          </div>
          <div className="mou-bars">
            {trackedMous.length === 0 && <div className="empty-state">No MoUs found.</div>}
            {trackedMous.map(m => {
              const pct = m.deliverables > 0 ? Math.min(100, Math.round((m.achieved / m.deliverables) * 100)) : 0;
              return <div className="mou-bar-row" key={m.id}>
                <div className="bar-label"><strong>{m.partner}</strong><span>{m.achieved}/{m.deliverables}</span></div>
                <div className="progress"><span style={{ width: `${pct}%` }} /></div>
                <span className="bar-pct">{pct}%</span>
              </div>;
            })}
          </div>
        </div>
      </div>
    </>
  );
}
