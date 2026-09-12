import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";
import Icon from "../components/Icons";

export default function MouDetails() {
  const { id } = useParams();
  const { data: mou, loading, error } = useApiData(() => api.getMou(id), [id]);

  if (loading) return <><div className="back-link"><Link to="/mous">← Back to MoUs</Link></div><LoadingState message="Loading MoU from the backend…" /></>;
  if (error) return <><div className="back-link"><Link to="/mous">← Back to MoUs</Link></div><ErrorState message={`Backend connection failed: ${error}`} /></>;
  if (!mou) return <><div className="back-link"><Link to="/mous">← Back to MoUs</Link></div><ErrorState message="MoU not found." /></>;

  const total = mou.deliverables || 0;
  const achieved = mou.achieved || 0;
  const pct = total > 0 ? Math.min(100, Math.round((achieved / total) * 100)) : 0;

  return <>
    <div className="back-link"><Link to="/mous">← Back to MoUs</Link></div>
    <PageHeader eyebrow="MOU INTELLIGENCE" title={mou.title} description={`${mou.partner} · ${mou.type} · ${mou.status}`}
      action={<button className="secondary-button" disabled title="Source-document viewing is not implemented in the current backend."><Icon name="file" size={16} /> View source document</button>} />

    <div className="detail-grid">
      <div className="panel">
        <div className="panel-head"><div><h2>Agreement profile</h2><p>Structured fields stored for the MoU</p></div><StatusBadge value={mou.status} /></div>
        <div className="field-grid">
          <Field label="Partner" value={mou.partner} />
          <Field label="Partner type" value={mou.type} />
          <Field label="Signed on" value={formatDate(mou.signedOn)} />
          <Field label="Valid from" value={formatDate(mou.validFrom)} />
          <Field label="Valid until" value={formatDate(mou.validUntil)} />
          <Field label="Renewal status" value={mou.renewal} />
        </div>
        <div className="scope-box"><strong>Scope</strong><p>{mou.scope}</p></div>
      </div>

      <div className="panel">
        <div className="panel-head"><div><h2>Commitment health</h2><p>Confirmed fulfilment only</p></div></div>
        <div className="big-progress">
          <div className="big-number">{pct}<small>%</small></div>
          <div className="progress large"><span style={{ width: `${pct}%` }} /></div>
          <span>{achieved} of {total} tracked commitments achieved</span>
        </div>
        <div className="mini-metrics">
          <div><strong>{total}</strong><span>Total commitments</span></div>
          <div><strong>{achieved}</strong><span>Achieved</span></div>
          <div><strong>{Math.max(total - achieved, 0)}</strong><span>Open</span></div>
        </div>
      </div>
    </div>

    <div className="panel">
      <div className="panel-head"><div><h2>Committed deliverables</h2><p>Authoritative fulfilment status from <code>engagement.v_deliverable_status</code></p></div></div>
      <div className="deliverable-list">
        {mou.deliverables.length === 0 && <div className="empty-state">No deliverables are recorded for this MoU.</div>}
        {mou.deliverables.map(d => <div className="deliverable" key={d.id}>
          <div className="deliverable-check">{d.status === "ACHIEVED" ? "✓" : "•"}</div>
          <div className="deliverable-main"><strong>{d.description}</strong><span>{d.type} · Due {formatDate(d.due)}</span></div>
          <div className="deliverable-count">{d.achieved}/{d.target}</div>
          <StatusBadge value={d.status} />
        </div>)}
      </div>
    </div>
  </>;
}
function Field({ label, value }) { return <div className="field"><span>{label}</span><strong>{value || "—"}</strong></div>; }
