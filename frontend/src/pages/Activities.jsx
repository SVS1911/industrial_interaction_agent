import { useEffect, useMemo, useState } from "react";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

const TYPES = ["INDUSTRY_VISIT","GUEST_LECTURE","EXPERT_TALK","SPONSORED_PROJECT","INTERNSHIP_DRIVE","FACULTY_EXCHANGE","LAB_SUPPORT","CONSULTANCY"];
const MODES = ["OFFLINE","ONLINE","HYBRID"];

export default function Activities() {
  const { data: activitiesData, loading, error } = useApiData(() => api.getActivities(), []);
  const { data: partnersData } = useApiData(() => api.getPartners(), []);
  const { data: mousData } = useApiData(() => api.getMous(), []);
  const [agentRunning, setAgentRunning] = useState(false);
  const [agentMessage, setAgentMessage] = useState("");
  const [recordOpen, setRecordOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const activities = activitiesData ?? [];
  const partners = partnersData ?? [];
  const mous = mousData ?? [];
  const [selectedPartner, setSelectedPartner] = useState("");
  const [selectedMou, setSelectedMou] = useState("");

  async function runAgent2() {
    setAgentRunning(true); setAgentMessage("");
    try { const r = await api.runActivitiesOutcomes(); setAgentMessage(`Agent 2 completed: ${r.summary?.matched ?? 0} activity-to-deliverable links found, ${r.summary?.new_suggestions ?? 0} new suggestions.`); window.location.reload(); }
    catch (e) { setAgentMessage(`Agent 2 failed: ${e?.message || "Unknown error"}`); }
    finally { setAgentRunning(false); }
  }
  async function saveActivity(e) {
    e.preventDefault(); setSaving(true); setAgentMessage("");
    const form = new FormData(e.currentTarget); const payload = Object.fromEntries(form.entries());
    payload.industry_partner_id = payload.industry_partner_id || null; payload.mou_id = payload.mou_id || null; payload.end_date = payload.end_date || null; payload.mode = payload.mode || null;
    payload.participant_count = payload.participant_count ? Number(payload.participant_count) : null;
    try { await api.createActivity(payload); setRecordOpen(false); setAgentMessage("Activity recorded. Run Agent 2 to match it against MoU commitments."); window.location.reload(); }
    catch (err) { setAgentMessage(`Activity could not be recorded: ${err?.message || "Unknown error"}`); }
    finally { setSaving(false); }
  }
  const filteredMous = useMemo(() => mous.filter(m => !selectedPartner || m.partnerId === selectedPartner), [mous, selectedPartner]);
  const columns = [
    { key: "title", label: "Activity", render: a => <div><strong>{a.title}</strong><small className="table-sub">{a.partner}</small></div> },
    { key: "type", label: "Type", render: a => a.type?.replaceAll("_", " ") },
    { key: "date", label: "Date", render: a => formatDate(a.date) },
    { key: "department", label: "Department" },
    { key: "participants", label: "Participants" },
    { key: "mode", label: "Mode", render: a => a.mode?.replaceAll("_", " ") },
    { key: "status", label: "Status", render: a => <StatusBadge value={a.status} /> },
    { key: "evidence", label: "Evidence", render: a => a.evidence ? <span className="evidence-ok">● Linked</span> : <span className="evidence-missing">● Missing</span> }
  ];
  const conducted = activities.filter(a => a.status === "CONDUCTED");
  const participants = activities.reduce((sum, a) => sum + a.participants, 0);
  const evidenced = activities.filter(a => a.evidence).length;
  return <>
    <PageHeader eyebrow="AGENT 2 · ACTIVITIES / DO" title="Activities & Outcomes" description="Record what actually happened, connect it to the right partner and MoU, then match it to the promise it fulfils."
      action={<div className="header-actions"><button className="secondary-button" onClick={runAgent2} disabled={agentRunning}>{agentRunning ? "Running Agent 2…" : "Run Agent 2"}</button><button className="primary-button" onClick={() => setRecordOpen(true)}>+ Record activity</button></div>} />
    {agentMessage && <div className="success-message">{agentMessage}</div>}
    <div className="stats-strip"><div><strong>{activities.length}</strong><span>Activities shown</span></div><div><strong>{conducted.length}</strong><span>Conducted</span></div><div><strong>{participants.toLocaleString()}</strong><span>Participants</span></div><div><strong>{evidenced}/{activities.length}</strong><span>With evidence</span></div></div>
    <div className="callout"><div className="callout-icon">✓</div><div><strong>Agent 2 answers: “What did we actually do?”</strong><span>It prefers explicit partner/MoU links, matches activity types to MoU deliverables, and records new fulfilment links as SUGGESTED so a human can confirm them.</span></div></div>
    <div className="panel">{loading && <LoadingState />}{error && <ErrorState message={`Backend connection failed: ${error}`} />}{!loading && !error && <DataTable columns={columns} rows={activities} />}</div>
    {recordOpen && <div className="modal-backdrop" onMouseDown={e => e.target === e.currentTarget && !saving && setRecordOpen(false)}><form className="upload-modal" onSubmit={saveActivity}><div className="modal-head"><div><h2>Record industry activity</h2><p>Record the real-world interaction first; Agent 2 can then connect it to the promise.</p></div><button type="button" className="icon-button small" onClick={() => setRecordOpen(false)} disabled={saving}>×</button></div>
      <div className="upload-grid"><label className="upload-field"><span>Activity title *</span><input name="title" required placeholder="Guest lecture on cloud security" /></label><label className="upload-field"><span>Activity type *</span><select name="activity_type" defaultValue="GUEST_LECTURE">{TYPES.map(x => <option key={x}>{x}</option>)}</select></label><label className="upload-field"><span>Partner</span><select name="industry_partner_id" value={selectedPartner} onChange={e => { setSelectedPartner(e.target.value); setSelectedMou(""); }}><option value="">Select partner</option>{partners.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label className="upload-field"><span>MoU</span><select name="mou_id" value={selectedMou} onChange={e => setSelectedMou(e.target.value)}><option value="">Select MoU (optional)</option>{filteredMous.map(m => <option key={m.id} value={m.id}>{m.title} — {m.partner}</option>)}</select></label><label className="upload-field"><span>Activity date *</span><input name="activity_date" type="date" required /></label><label className="upload-field"><span>End date</span><input name="end_date" type="date" /></label><label className="upload-field"><span>Mode</span><select name="mode" defaultValue="OFFLINE"><option value="">Not specified</option>{MODES.map(x => <option key={x}>{x}</option>)}</select></label><label className="upload-field"><span>Participants</span><input name="participant_count" type="number" min="0" placeholder="50" /></label></div>
      <label className="upload-field"><span>Outcome / result</span><textarea name="outcome_summary" rows="3" placeholder="Students attended; practical demonstration completed..." /></label><div className="upload-note">Evidence can be linked later through the document/evidence workflow. Agent 2 will not invent evidence or silently confirm a fulfilment.</div><div className="modal-actions"><button type="button" className="secondary-button" onClick={() => setRecordOpen(false)} disabled={saving}>Cancel</button><button type="submit" className="primary-button" disabled={saving}>{saving ? "Saving…" : "Record activity"}</button></div>
    </form></div>}
  </>;
}
