import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

export default function Mous() {
  const { data: mousData, loading, error } = useApiData(() => api.getMous(), []);
  const mous = mousData ?? [];
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
      action={<button className="primary-button" disabled title="MoU upload and AI extraction are not implemented in the current backend.">+ Upload MoU</button>} />
    <div className="callout">
      <div className="callout-icon">✦</div>
      <div><strong>Agent 1 answers: “What did we promise?”</strong><span>Current view shows MoUs already stored in the database. Upload and extraction will be connected when that backend workflow is implemented.</span></div>
    </div>
    <div className="panel">
      <div className="panel-head"><div><h2>MoU tracker</h2><p>Aligned with <code>engagement.v_mou_tracker</code></p></div><div className="table-count">{mous.length} records</div></div>
      {loading && <LoadingState />}
      {error && <ErrorState message={`Backend connection failed: ${error}`} />}
      {!loading && !error && <DataTable columns={columns} rows={mous} />}
    </div>
  </>;
}
