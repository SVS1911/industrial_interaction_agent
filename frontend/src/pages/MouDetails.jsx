import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { deliverables, mous, partners } from "../data/mockData";
import { formatDate } from "../utils/formatters";
import Icon from "../components/Icons";

export default function MouDetails() {
  const { id } = useParams();
  const mou = mous.find(m => m.id === id) || mous[0];
  const partner = partners.find(p => p.id === mou.partnerId);
  const rows = deliverables.filter(d => d.mouId === mou.id);
  return <>
    <div className="back-link"><Link to="/mous">← Back to MoUs</Link></div>
    <PageHeader eyebrow="MOU INTELLIGENCE" title={mou.title} description={`${mou.partner} · ${mou.type} · ${mou.status}`}
      action={<button className="secondary-button"><Icon name="file" size={16} /> View source document</button>} />

    <div className="detail-grid">
      <div className="panel">
        <div className="panel-head"><div><h2>Agreement profile</h2><p>Structured fields extracted from the MoU</p></div><StatusBadge value={mou.status} /></div>
        <div className="field-grid">
          <Field label="Partner" value={partner?.name || mou.partner} />
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
          <div className="big-number">{Math.round(mou.achieved / mou.deliverables * 100)}<small>%</small></div>
          <div className="progress large"><span style={{ width: `${mou.achieved / mou.deliverables * 100}%` }} /></div>
          <span>{mou.achieved} of {mou.deliverables} tracked commitments achieved</span>
        </div>
        <div className="mini-metrics">
          <div><strong>{mou.deliverables}</strong><span>Total commitments</span></div>
          <div><strong>{mou.achieved}</strong><span>Achieved</span></div>
          <div><strong>{mou.deliverables - mou.achieved}</strong><span>Open</span></div>
        </div>
      </div>
    </div>

    <div className="panel">
      <div className="panel-head"><div><h2>Committed deliverables</h2><p>Each item maps to <code>engagement.mou_deliverable</code></p></div></div>
      <div className="deliverable-list">
        {rows.map(d => <div className="deliverable" key={d.id}>
          <div className="deliverable-check">{d.status === "ACHIEVED" ? "✓" : "•"}</div>
          <div className="deliverable-main"><strong>{d.description}</strong><span>{d.type} · Due {formatDate(d.due)}</span></div>
          <div className="deliverable-count">{d.achieved}/{d.target}</div>
          <StatusBadge value={d.status} />
        </div>)}
      </div>
    </div>
  </>;
}
function Field({ label, value }) { return <div className="field"><span>{label}</span><strong>{value}</strong></div>; }