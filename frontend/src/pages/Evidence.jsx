import { useState } from "react";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

export default function Evidence() {
  const { data: evidenceData, loading, error } = useApiData(() => api.getEvidence(), []);
  const { data: reportsData } = useApiData(() => api.getAccreditationEvidenceReports(), []);
  const [running, setRunning] = useState(false); const [exporting, setExporting] = useState(false); const [message, setMessage] = useState("");
  const evidence=evidenceData??[], reports=reportsData??[]; const latest=reports[0]?.payload;
  async function runAgent5(){setRunning(true);setMessage("");try{const r=await api.runAccreditationEvidence();setMessage(`Agent 5 completed: ${r.summary?.available??0} criteria have evidence support; ${r.summary?.missing_or_incomplete??0} are missing or incomplete.`);window.location.reload()}catch(e){setMessage(`Agent 5 failed: ${e?.message||"Unknown error"}`)}finally{setRunning(false)}}
  async function exportReport(){setExporting(true);setMessage("");try{await api.downloadAccreditationEvidenceReport();setMessage("Agent 5 report exported successfully.")}catch(e){setMessage(`Report export failed: ${e?.message||"Unknown error"}`)}finally{setExporting(false)}}
  const approved=evidence.filter(e=>e.approved).length, pending=evidence.length-approved;
  return <>
    <PageHeader eyebrow="AGENT 5 · ACCREDITATION EVIDENCE / PROVE" title="Accreditation Evidence" description="Prove what the institution actually did by mapping authoritative MoUs, activities, outcomes, documents and feedback to accreditation criteria." action={<div className="header-actions"><button className="secondary-button" onClick={exportReport} disabled={exporting || !latest}>{exporting?"Exporting…":"Export report"}</button><button className="primary-button" onClick={runAgent5} disabled={running}>{running?"Running Agent 5…":"Run Agent 5"}</button></div>} />
    {message&&<div className="success-message">{message}</div>}
    <div className="callout"><div className="callout-icon">✓</div><div><strong>Agent 5 answers: “Can we prove what we did?”</strong><span>It reports which accreditation criteria have supporting records, where evidence exists, and where proof is missing or incomplete. It does not fabricate evidence.</span></div></div>
    <div className="evidence-overview"><div className="evidence-score"><div className="evidence-number">{evidence.length}</div><div><strong>Evidence records</strong><span>Retrieved from the authoritative Agent 28 evidence view</span></div></div><div className="evidence-kpi"><strong>{approved}</strong><span>Approved</span></div><div className="evidence-kpi"><strong>{pending}</strong><span>Pending approval</span></div><div className="evidence-kpi"><strong>{new Set(evidence.map(e=>e.criterion).filter(Boolean)).size}</strong><span>Criteria represented</span></div></div>
    {latest?.criteria?.length>0&&<div className="panel agent-report-panel"><div className="panel-head"><div><h2>Latest Agent 5 evidence assessment</h2><p>{latest.as_of_date} · {latest.model_version}</p></div></div><div className="evidence-criteria-grid">{latest.criteria.map(c=><div className="report-item" key={c.criterion}><span>{c.criterion}</span><strong>{c.title}</strong><StatusBadge value={c.status}/><p>{c.source_support}</p><small>Existing evidence records: {c.evidence_records}</small></div>)}</div></div>}
    <div className="panel"><div className="panel-head"><div><h2>Evidence mapping</h2><p>Generated from authoritative Agent 28 sources</p></div></div>{loading&&<LoadingState/>}{error&&<ErrorState message={`Backend connection failed: ${error}`}/>} {!loading&&!error&&<div className="evidence-table">{evidence.length===0&&<div className="empty-state">No evidence records found.</div>}{evidence.map(e=><div className="evidence-row" key={e.id}><div className="criterion">{e.criterion}</div><div className="evidence-title"><strong>{e.title}</strong><span>{e.source} · {e.period}</span></div><div className="coverage"><span>{e.evidenceType}</span></div><StatusBadge value={e.approved?"APPROVED":"IN_REVIEW"}/><span className="table-sub">{e.approvedAt?formatDate(e.approvedAt):"Pending"}</span></div>)}</div>}</div>
  </>;
}
