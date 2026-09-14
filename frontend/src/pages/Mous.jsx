import { useMemo, useRef, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

const TYPES = ["INDUSTRY", "UNIVERSITY", "RESEARCH_LAB", "NGO", "GOVERNMENT", "INTERNATIONAL"];

export default function Mous() {
  const { data: mousData, loading, error } = useApiData(() => api.getMous(), []);
  const { data: reportsData, loading: reportsLoading } = useApiData(() => api.getMouIntelligenceReports(), []);
  const [runningId, setRunningId] = useState("");
  const [message, setMessage] = useState("");
  const [uploadOpen, setUploadOpen] = useState(false);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef(null);
  const mous = mousData ?? [];
  const reports = reportsData ?? [];
  const reportByMou = useMemo(() => new Map(reports.map((r) => [r.mouId, r])), [reports]);

  async function runAgent1(mouId) {
    setRunningId(mouId);
    setMessage("");
    try {
      const result = await api.runMouIntelligence(mouId);
      setMessage(result.reports_created > 0 ? "Agent 1 completed. The MoU intelligence report is ready." : "Agent 1 finished without creating a report.");
      if (result.reports_created > 0) window.location.reload();
    } catch (err) {
      setMessage(`Agent 1 failed: ${err?.message || "Unknown error"}`);
    } finally {
      setRunningId("");
    }
  }

  async function uploadMou(event) {
    event.preventDefault();
    setUploading(true);
    setMessage("");
    const form = new FormData(event.currentTarget);
    const file = fileRef.current?.files?.[0];
    if (!file) {
      setMessage("Please choose a PDF MoU first.");
      setUploading(false);
      return;
    }
    form.set("file", file);
    try {
      const result = await api.uploadMou(form);
      const agent = result.agent_1 || {};
      if (agent.reports_created > 0) {
        setMessage(`MoU uploaded and Agent 1 extracted its intelligence successfully.`);
      } else {
        setMessage(`MoU uploaded, but Agent 1 could not create the report: ${agent.failures?.[0]?.error || "unknown error"}`);
      }
      setUploadOpen(false);
      event.currentTarget.reset();
      if (agent.reports_created > 0) window.location.reload();
    } catch (err) {
      setMessage(`Upload failed: ${err?.message || "Unknown error"}`);
    } finally {
      setUploading(false);
    }
  }

  const columns = [
    { key: "title", label: "MoU", render: m => <div><Link className="table-link" to={`/mous/${m.id}`}>{m.title}</Link><small className="table-sub">{m.partner}</small></div> },
    { key: "validUntil", label: "Valid until", render: m => formatDate(m.validUntil) },
    { key: "status", label: "Status", render: m => <StatusBadge value={m.status} /> },
    { key: "deliverables", label: "Deliverables", render: m => `${m.achieved} / ${m.deliverables}` },
    { key: "renewal", label: "Renewal", render: m => <StatusBadge value={m.renewal === "No discussion" ? "AT_RISK" : "STABLE"} /> },
    { key: "agent1", label: "Agent 1", render: m => reportByMou.has(m.id) ? <span className="agent-ready">Report ready</span> : <span className="agent-not-run">Not run</span> },
    { key: "action", label: "Action", render: m => <button className="secondary-button table-action" onClick={() => runAgent1(m.id)} disabled={runningId === m.id}>{runningId === m.id ? "Running…" : reportByMou.has(m.id) ? "Run again" : "Run Agent 1"}</button> },
  ];

  return <>
    <PageHeader eyebrow="AGENT 1 · MOU INTELLIGENCE" title="MoU Intelligence" description="Upload MoUs, understand their commitments with Gemini, and reconcile the result against authoritative university data."
      action={<button className="primary-button" onClick={() => setUploadOpen(true)}>+ Upload MoU</button>} />
    {message && <div className="success-message">{message}</div>}
    <div className="callout">
      <div className="callout-icon">✦</div>
      <div><strong>Agent 1 answers: “What did we promise?”</strong><span>Upload a PDF and provide the basic agreement metadata. The backend stores the document and source chunks, creates the MoU record, then runs Gemini MoU Intelligence and stores the report in AgentOps.</span></div>
    </div>
    <div className="panel">
      <div className="panel-head"><div><h2>MoU tracker</h2><p>Aligned with <code>engagement.v_mou_tracker</code></p></div><div className="table-count">{mous.length} records · {reportsLoading ? "checking reports…" : `${reports.length} Agent 1 reports`}</div></div>
      {loading && <LoadingState />}
      {error && <ErrorState message={`Backend connection failed: ${error}`} />}
      {!loading && !error && <DataTable columns={columns} rows={mous} />}
    </div>

    {uploadOpen && <div className="modal-backdrop" onMouseDown={(e) => e.target === e.currentTarget && !uploading && setUploadOpen(false)}>
      <form className="upload-modal" onSubmit={uploadMou}>
        <div className="modal-head"><div><h2>Upload a new MoU</h2><p>PDF only. Agent 1 will run automatically after the MoU is stored.</p></div><button type="button" className="icon-button small" onClick={() => setUploadOpen(false)} disabled={uploading}>×</button></div>
        <label className="upload-field"><span>MoU PDF *</span><input ref={fileRef} name="file" type="file" accept="application/pdf,.pdf" required disabled={uploading} /></label>
        <div className="upload-grid">
          <label className="upload-field"><span>Partner name *</span><input name="partner_name" required placeholder="e.g. Nimbus CloudWorks Pvt Ltd" disabled={uploading} /></label>
          <label className="upload-field"><span>MoU title *</span><input name="title" required placeholder="e.g. Industry-Academia Collaboration" disabled={uploading} /></label>
          <label className="upload-field"><span>Partner type *</span><select name="partner_type" defaultValue="INDUSTRY" disabled={uploading}>{TYPES.map(t => <option key={t} value={t}>{t.replaceAll("_", " ")}</option>)}</select></label>
          <label className="upload-field"><span>Signed on *</span><input name="signed_on" type="date" required disabled={uploading} /></label>
          <label className="upload-field"><span>Valid from</span><input name="valid_from" type="date" disabled={uploading} /></label>
          <label className="upload-field"><span>Valid until</span><input name="valid_until" type="date" disabled={uploading} /></label>
          <label className="upload-field"><span>Renewal alert days</span><input name="renewal_alert_days" type="number" min="0" max="730" defaultValue="90" disabled={uploading} /></label>
        </div>
        <div className="upload-note">The basic dates are requested because the current <code>engagement.mou</code> table treats the signed date as authoritative. Agent 1 then extracts the semantic commitments and renewal clauses from the uploaded document.</div>
        <div className="modal-actions"><button type="button" className="secondary-button" onClick={() => setUploadOpen(false)} disabled={uploading}>Cancel</button><button type="submit" className="primary-button" disabled={uploading}>{uploading ? "Uploading & extracting…" : "Upload & run Agent 1"}</button></div>
      </form>
    </div>}
  </>;
}
