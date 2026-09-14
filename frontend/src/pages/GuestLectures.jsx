import { useMemo, useState } from "react";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

const SPEAKER_TYPES = ["INDUSTRY_EXPERT", "ALUMNI", "ACADEMIC", "OTHER"];
const MODES = ["OFFLINE", "ONLINE", "HYBRID"];
const STATUSES = ["PLANNED", "CONFIRMED", "CONDUCTED", "POSTPONED", "CANCELLED"];

export default function GuestLectures() {
  const { data: lecturesData, loading, error } = useApiData(() => api.getGuestLectures(), []);
  const { data: partnersData } = useApiData(() => api.getPartners(), []);
  const { data: alumniData } = useApiData(() => api.getAlumni(), []);
  const { data: mousData } = useApiData(() => api.getMous(), []);
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState("");
  const [speakerType, setSpeakerType] = useState("INDUSTRY_EXPERT");
  const lectures = lecturesData ?? [];
  const partners = partnersData ?? [];
  const alumni = alumniData ?? [];
  const mous = mousData ?? [];

  const conducted = lectures.filter(l => l.status === "CONDUCTED");
  const independent = lectures.filter(l => !l.mouId).length;
  const evidenced = lectures.filter(l => l.evidence).length;
  const domains = useMemo(() => [...new Set(lectures.map(l => l.domain).filter(Boolean))].sort(), [lectures]);

  async function save(e) {
    e.preventDefault();
    setSaving(true); setMessage("");
    const form = Object.fromEntries(new FormData(e.currentTarget).entries());
    form.alumni_id = form.alumni_id || null;
    form.industry_partner_id = form.industry_partner_id || null;
    form.mou_id = form.mou_id || null;
    form.end_date = form.end_date || null;
    form.mode = form.mode || null;
    form.department_id = form.department_id || null;
    form.participant_count = form.participant_count ? Number(form.participant_count) : null;
    try {
      await api.createGuestLecture(form);
      setOpen(false);
      setMessage("Guest lecture recorded successfully.");
      window.location.reload();
    } catch (err) {
      setMessage(`Guest lecture could not be recorded: ${err?.message || "Unknown error"}`);
    } finally { setSaving(false); }
  }

  const columns = [
    { key: "title", label: "Lecture", render: l => <div><strong>{l.title}</strong><small className="table-sub">{l.speakerName} · {l.domain}</small></div> },
    { key: "speakerType", label: "Speaker", render: l => l.speakerType?.replaceAll("_", " ") },
    { key: "date", label: "Date", render: l => formatDate(l.date) },
    { key: "partner", label: "Partner", render: l => l.partner || "Independent" },
    { key: "mou", label: "MoU", render: l => l.mouTitle || "Not MoU-linked" },
    { key: "participants", label: "Participants" },
    { key: "status", label: "Status", render: l => <StatusBadge value={l.status} /> },
    { key: "evidence", label: "Evidence", render: l => l.evidence ? <span className="evidence-ok">● Linked</span> : <span className="evidence-missing">● Missing</span> }
  ];

  return <>
    <PageHeader eyebrow="GUEST LECTURE REGISTRY" title="Guest Lectures" description="Track guest lectures independently of MoUs, including alumni, industry experts, academics and other invited speakers. MoU linkage is optional." action={<button className="primary-button" onClick={() => { setMessage(""); setOpen(true); }}>+ Record guest lecture</button>} />
    {message && <div className="success-message">{message}</div>}
    <div className="stats-strip"><div><strong>{lectures.length}</strong><span>Lectures shown</span></div><div><strong>{conducted.length}</strong><span>Conducted</span></div><div><strong>{independent}</strong><span>Outside MoUs</span></div><div><strong>{evidenced}/{lectures.length}</strong><span>With evidence</span></div></div>
    <div className="callout"><div className="callout-icon">✓</div><div><strong>Guest lectures are not limited to MoU commitments.</strong><span>This dedicated registry captures domain-based lectures from alumni and any other invited expert. When a partner or MoU is known, it can still be recorded for traceability.</span></div></div>
    <div className="panel"><div className="panel-head"><div><h2>Guest lecture register</h2><p>{domains.length ? `${domains.length} domains represented` : "No guest lectures recorded yet"}</p></div><div className="table-count">{lectures.length} records</div></div>{loading && <LoadingState />}{error && <ErrorState message={`Backend connection failed: ${error}`} />}{!loading && !error && <DataTable columns={columns} rows={lectures} />}</div>
    {open && <div className="modal-backdrop" onMouseDown={e => e.target === e.currentTarget && !saving && setOpen(false)}><form className="upload-modal" onSubmit={save}>
      <div className="modal-head"><div><h2>Record guest lecture</h2><p>Record the lecture itself. A MoU is optional because lectures may come directly from alumni or independent experts.</p></div><button type="button" className="icon-button small" onClick={() => setOpen(false)} disabled={saving}>×</button></div>
      <div className="upload-grid">
        <label className="upload-field"><span>Speaker name *</span><input name="speaker_name" required placeholder="e.g. Dr. Priya Rao" /></label>
        <label className="upload-field"><span>Speaker type *</span><select name="speaker_type" value={speakerType} onChange={e => setSpeakerType(e.target.value)}>{SPEAKER_TYPES.map(x => <option key={x}>{x}</option>)}</select></label>
        <label className="upload-field"><span>Alumni link</span><select name="alumni_id" disabled={speakerType !== "ALUMNI"}><option value="">Not linked</option>{alumni.map(a => <option key={a.alumni_id} value={a.alumni_id}>{a.full_name || a.name || a.alumni_id}</option>)}</select></label>
        <label className="upload-field"><span>Domain *</span><input name="domain" required placeholder="Cloud computing / VLSI / AI" /></label>
        <label className="upload-field"><span>Lecture title *</span><input name="title" required placeholder="Guest lecture on practical AI deployment" /></label>
        <label className="upload-field"><span>Lecture date *</span><input name="lecture_date" type="date" required /></label>
        <label className="upload-field"><span>End date</span><input name="end_date" type="date" /></label>
        <label className="upload-field"><span>Mode</span><select name="mode" defaultValue="OFFLINE"><option value="">Not specified</option>{MODES.map(x => <option key={x}>{x}</option>)}</select></label>
        <label className="upload-field"><span>Industry partner</span><select name="industry_partner_id"><option value="">Independent / no partner</option>{partners.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
        <label className="upload-field"><span>MoU (optional)</span><select name="mou_id"><option value="">Not linked</option>{mous.map(m => <option key={m.id} value={m.id}>{m.title} — {m.partner}</option>)}</select></label>
        <label className="upload-field"><span>Participants</span><input name="participant_count" type="number" min="0" placeholder="80" /></label>
        <label className="upload-field"><span>Status *</span><select name="status" defaultValue="CONDUCTED">{STATUSES.map(x => <option key={x}>{x}</option>)}</select></label>
      </div>
      <label className="upload-field"><span>Outcome / result</span><textarea name="outcome_summary" rows="3" placeholder="Students learned current industry practices..." /></label>
      <div className="upload-note">No MoU is required. The lecture remains traceable to its speaker, domain, date and optional partner. Evidence can be linked through the existing evidence/document workflow.</div>
      <div className="modal-actions"><button type="button" className="secondary-button" onClick={() => setOpen(false)} disabled={saving}>Cancel</button><button className="primary-button" disabled={saving}>{saving ? "Saving…" : "Record guest lecture"}</button></div>
    </form></div>}
  </>;
}
