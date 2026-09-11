import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { mous } from "../data/mockData";
import { formatDate } from "../utils/formatters";

export default function Mous() {
  const columns = [
    { key: "title", label: "MoU", render: m => <div><Link className="table-link" to={`/mous/${m.id}`}>{m.title}</Link><small className="table-sub">{m.partner}</small></div> },
    { key: "validUntil", label: "Valid until", render: m => formatDate(m.validUntil) },
    { key: "status", label: "Status", render: m => <StatusBadge value={m.status} /> },
    { key: "deliverables", label: "Deliverables", render: m => `${m.achieved} / ${m.deliverables}` },
    { key: "renewal", label: "Renewal", render: m => <StatusBadge value={m.renewal === "No discussion" ? "AT_RISK" : "STABLE"} /> },
    { key: "scope", label: "Scope", render: m => <span className="truncate">{m.scope}</span> }
  ];

  return <>
    <PageHeader eyebrow="AGENT 1 · MOU INTELLIGENCE" title="MoU Intelligence" description="Digitised commitments, validity, deliverables and renewal risk from industry agreements."
      action={<button className="primary-button">+ Upload MoU</button>} />
    <div className="callout">
      <div className="callout-icon">✦</div>
      <div><strong>Agent 1 answers: “What did we promise?”</strong><span>Upload an agreement → extract structured commitments → track each commitment against confirmed evidence.</span></div>
    </div>
    <div className="panel">
      <div className="panel-head"><div><h2>MoU tracker</h2><p>Aligned with <code>engagement.v_mou_tracker</code></p></div><div className="table-count">{mous.length} records</div></div>
      <DataTable columns={columns} rows={mous} />
    </div>
  </>;
}