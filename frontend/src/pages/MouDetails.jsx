import { useMemo, useState } from "react";
import { Link, useParams } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

export default function MouDetails() {
  const { id } = useParams();
  const { data: mou, loading, error } = useApiData(() => api.getMou(id), [id]);
  const { data: reports, loading: reportsLoading } = useApiData(() => api.getMouIntelligenceReports(), []);
  const report = useMemo(() => reports?.find((r) => r.mouId === id) || null, [reports, id]);
  const [running, setRunning] = useState(false);
  const [message, setMessage] = useState("");

  if (loading) return <><div className="back-link"><Link to="/mous">← Back to MoUs</Link></div><LoadingState message="Loading MoU from the backend…" /></>;
  if (error) return <><div className="back-link"><Link to="/mous">← Back to MoUs</Link></div><ErrorState message={`Backend connection failed: ${error}`} /></>;
  if (!mou) return <><div className="back-link"><Link to="/mous">← Back to MoUs</Link></div><ErrorState message="MoU not found." /></>;

  const total = mou.deliverables || 0;
  const achieved = mou.achieved || 0;
  const pct = total > 0 ? Math.min(100, Math.round((achieved / total) * 100)) : 0;
  const extraction = report?.extraction || {};
  const validation = report?.validation || {};

  async function runAgent1() {
    setRunning(true); setMessage("");
    try {
      await api.runMouIntelligence(id);
      setMessage("Agent 1 completed. Refreshing the intelligence report…");
      window.location.reload();
    } catch (err) {
      setMessage(`Agent 1 failed: ${err?.message || "Unknown error"}`);
    } finally { setRunning(false); }
  }

  return <>
    <div className="back-link"><Link to="/mous">← Back to MoUs</Link></div>
    <PageHeader eyebrow="MOU INTELLIGENCE" title={mou.title} description={`${mou.partner} · ${mou.type} · ${mou.status}`}
      action={<button className="primary-button" onClick={runAgent1} disabled={running}>{running ? "Running…" : "Run Agent 1"}</button>} />
    {message && <div className="success-message">{message}</div>}

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
          <div><strong>{total}</strong><span>Total commitments</span></div><div><strong>{achieved}</strong><span>Achieved</span></div><div><strong>{Math.max(total - achieved, 0)}</strong><span>Open</span></div>
        </div>
      </div>
    </div>

    <div className="panel agent-report-panel">
      <div className="panel-head"><div><h2>Agent 1 intelligence report</h2><p>Gemini semantic extraction + deterministic database reconciliation</p></div>{report && <StatusBadge value={report.requiresReview ? "AT_RISK" : "STABLE"} />}</div>
      {reportsLoading && <LoadingState message="Checking for an Agent 1 report…" />}
      {!reportsLoading && !report && <div className="empty-state">No Agent 1 report exists for this MoU yet. Click <strong>Run Agent 1</strong> to analyze its source document.</div>}
      {!reportsLoading && report && <>
        <div className="report-summary"><div><span>Summary</span><p>{extraction.summary || "—"}</p></div><div className="confidence-box"><span>Confidence</span><strong>{report.confidence == null ? "—" : `${Math.round(report.confidence * 100)}%`}</strong><small>{report.approvalStatus === "PENDING" ? "Human review required" : "No review pending"}</small></div></div>
        <div className="report-grid">
          <ReportItem label="Parties" value={extraction.parties?.length ? extraction.parties.join(" · ") : "—"} />
          <ReportItem label="Scope found by Gemini" value={extraction.scope || "—"} />
          <ReportItem label="Mandatory commitments" value={extraction.mandatory_commitments_count ?? 0} />
          <ReportItem label="Conditional commitments" value={extraction.conditional_commitments_count ?? 0} />
          <ReportItem label="Renewal terms" value={extraction.renewal_terms?.summary || "Not identified"} />
          <ReportItem label="Review required" value={extraction.review_required ? "Yes" : "No"} />
        </div>
        {extraction.commitments?.length > 0 && <div className="report-section"><h3>Extracted commitments</h3>{extraction.commitments.map((c, i) => <div className="commitment-card" key={`${c.description}-${i}`}><div><strong>{c.description}</strong><span>{c.commitment_type} · {c.party || "Party not specified"} · {c.mandatory ? "Mandatory" : "Optional"}{c.conditional ? " · Conditional" : ""}</span></div><div className="commitment-meta">{c.target_count != null ? `Target: ${c.target_count}` : "No quantity"}<br />{c.due_date ? `Due: ${formatDate(c.due_date)}` : "No due date"}</div></div>)}</div>}
        <div className="report-section reconciliation"><h3>Database reconciliation</h3><div className="report-grid"><ReportItem label="DB valid from" value={formatDate(validation.db_valid_from)} /><ReportItem label="DB valid until" value={formatDate(validation.db_valid_until)} /><ReportItem label="DB deliverables" value={validation.db_deliverables?.length ?? 0} /><ReportItem label="Extracted deliverables" value={validation.extracted_deliverables_count ?? 0} /></div>{validation.discrepancies?.length > 0 ? <div className="warning-box">{validation.discrepancies.map((d, i) => <div key={i}>⚠ {d}</div>)}</div> : <div className="success-box">✓ No database reconciliation discrepancies were detected.</div>}</div>
        {report.citations?.length > 0 && <div className="report-section"><h3>Source citations</h3>{report.citations.map((c, i) => <div className="citation" key={i}>Page {c.page_no || "?"} · {c.heading_path || "Source chunk"}<p>{c.source_text}</p></div>)}</div>}
      </>}
    </div>

    <div className="panel">
      <div className="panel-head"><div><h2>Committed deliverables</h2><p>Authoritative fulfilment status from <code>engagement.v_deliverable_status</code></p></div></div>
      <div className="deliverable-list">
        {mou.deliverables.length === 0 && <div className="empty-state">No deliverables are recorded for this MoU.</div>}
        {mou.deliverables.map(d => <div className="deliverable" key={d.id}><div className="deliverable-check">{d.status === "ACHIEVED" ? "✓" : "•"}</div><div className="deliverable-main"><strong>{d.description}</strong><span>{d.type} · Due {formatDate(d.due)}</span></div><div className="deliverable-count">{d.achieved}/{d.target}</div><StatusBadge value={d.status} /></div>)}
      </div>
    </div>
  </>;
}

function Field({ label, value }) { return <div className="field"><span>{label}</span><strong>{value || "—"}</strong></div>; }
function ReportItem({ label, value }) { return <div className="report-item"><span>{label}</span><strong>{value || "—"}</strong></div>; }
