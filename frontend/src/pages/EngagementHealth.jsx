import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { health } from "../data/mockData";
import { formatDate } from "../utils/formatters";

export default function EngagementHealth() {
  return <>
    <PageHeader eyebrow="AGENT 3 · ENGAGEMENT HEALTH" title="Engagement Health" description="Rule-based relationship health using recency, activity volume, outcomes, deliverables, feedback and renewal risk." />
    <div className="health-grid">
      {health.map(h => (
        <div className="health-card" key={h.partnerId}>
          <div className="health-card-top">
            <div className="partner-avatar">{h.partner.slice(0,2).toUpperCase()}</div>
            <div><h3>{h.partner}</h3><span>Last activity · {formatDate(h.lastActivity)}</span></div>
            <StatusBadge value={h.band} />
          </div>
          <div className="health-score-row">
            <div className={`ring ${h.band.toLowerCase()}`}><strong>{h.score}</strong><span>/100</span></div>
            <div className="health-description">{h.dormant ? "Relationship is dormant and requires re-engagement." : h.score >= 80 ? "Healthy relationship with consistent industry activity." : "Relationship is active but has areas that need attention."}</div>
          </div>
          <div className="health-metrics">
            <Metric label="Activities · 12m" value={h.activities12m} />
            <Metric label="Internships · 12m" value={h.internships12m} />
            <Metric label="Offers · 12m" value={h.offers12m} />
            <Metric label="Active MoUs" value={h.activeMou} />
            <Metric label="Deliverables" value={`${h.achieved}/${h.achieved+h.due}`} />
            <Metric label="Feedback" value={h.feedback ? h.feedback.toFixed(1) : "—"} />
          </div>
        </div>
      ))}
    </div>
  </>;
}
function Metric({label,value}) { return <div><span>{label}</span><strong>{value}</strong></div>; }