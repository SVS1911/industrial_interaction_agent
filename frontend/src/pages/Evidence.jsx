import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

export default function Evidence() {
  const { data: evidenceData, loading, error } = useApiData(() => api.getEvidence(), []);
  const evidence = evidenceData ?? [];
  const approved = evidence.filter((e) => e.approved).length;
  const pending = evidence.length - approved;
  return <>
    <PageHeader eyebrow="AGENT 5 · ACCREDITATION EVIDENCE" title="Accreditation Evidence" description="Map industry-interaction records to accreditation criteria and identify missing or incomplete evidence." action={<button className="secondary-button" disabled title="Report export is not implemented in the current backend.">Export report</button>} />
    <div className="evidence-overview">
      <div className="evidence-score"><div className="evidence-number">{evidence.length}</div><div><strong>Evidence records</strong><span>Retrieved from the authoritative Agent 28 evidence view</span></div></div>
      <div className="evidence-kpi"><strong>{approved}</strong><span>Approved</span></div>
      <div className="evidence-kpi"><strong>{pending}</strong><span>Pending approval</span></div>
      <div className="evidence-kpi"><strong>{new Set(evidence.map(e => e.criterion).filter(Boolean)).size}</strong><span>Criteria represented</span></div>
    </div>
    <div className="panel">
      <div className="panel-head"><div><h2>Evidence mapping</h2><p>Generated from authoritative Agent 28 sources</p></div></div>
      {loading && <LoadingState />}
      {error && <ErrorState message={`Backend connection failed: ${error}`} />}
      {!loading && !error && <div className="evidence-table">
        {evidence.length === 0 && <div className="empty-state">No evidence records found.</div>}
        {evidence.map(e => <div className="evidence-row" key={e.id}>
          <div className="criterion">{e.criterion}</div>
          <div className="evidence-title"><strong>{e.title}</strong><span>{e.source} · {e.period}</span></div>
          <div className="coverage"><span>{e.evidenceType}</span></div>
          <StatusBadge value={e.approved ? "APPROVED" : "IN_REVIEW"} />
          <span className="table-sub">{e.approvedAt ? formatDate(e.approvedAt) : "Pending"}</span>
        </div>)}
      </div>}
    </div>
  </>;
}
