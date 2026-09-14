import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";

export default function Partners() {
  const [query, setQuery] = useState(""); const [status, setStatus] = useState(""); const [sector, setSector] = useState("");
  const [open, setOpen] = useState(false); const [saving, setSaving] = useState(false); const [message, setMessage] = useState("");
  const { data: partnersData, loading, error } = useApiData(() => api.getPartners(), []); const partners = partnersData ?? [];
  const sectors = useMemo(() => [...new Set(partners.map(p => p.sector).filter(Boolean))].sort(), [partners]);
  const filtered = partners.filter(p => `${p.name} ${p.sector}`.toLowerCase().includes(query.toLowerCase()) && (!status || p.status === status) && (!sector || p.sector === sector));
  async function save(e) { e.preventDefault(); setSaving(true); setMessage(""); const form=Object.fromEntries(new FormData(e.currentTarget).entries());
    try { await api.createPartner(form); setOpen(false); setMessage("Partner added successfully."); window.location.reload(); }
    catch(err){ setMessage(`Partner could not be added: ${err?.message || "Unknown error"}`); } finally { setSaving(false); }
  }
  const columns = [
    { key:"name", label:"Partner", render:p=><Link className="table-link" to={`/health?partner=${p.id}`}>{p.name}</Link> }, {key:"sector",label:"Sector"}, {key:"status",label:"Status",render:p=><StatusBadge value={p.status}/>},
    {key:"score",label:"Health score",render:p=>p.score==null?"—":<span className={`score-inline ${p.score>=80?"good":p.score>=60?"mid":"bad"}`}>{p.score}</span>}, {key:"mous",label:"Active MoUs"}, {key:"activities",label:"Activities · 12m"}, {key:"lastActivity",label:"Last activity",render:p=>p.lastActivity||"—"}
  ];
  return <>
    <PageHeader eyebrow="PARTNER REGISTER" title="Industry Partners" description="The authoritative partner register used by Agent 28 for MoUs, activities and engagement health." action={<button className="primary-button" onClick={()=>{setMessage("");setOpen(true)}}><span>+</span> Add partner</button>} />
    {message && <div className="success-message">{message}</div>}
    <div className="toolbar"><div className="filter-search"><span>⌕</span><input value={query} onChange={e=>setQuery(e.target.value)} placeholder="Search partner or sector..."/></div><select value={status} onChange={e=>setStatus(e.target.value)}><option value="">All statuses</option><option value="ACTIVE">Active</option><option value="DORMANT">Dormant</option><option value="PROSPECT">Prospect</option><option value="CONCLUDED">Concluded</option></select><select value={sector} onChange={e=>setSector(e.target.value)}><option value="">All sectors</option>{sectors.map(v=><option key={v}>{v}</option>)}</select></div>
    <div className="panel">{loading&&<LoadingState/>}{error&&<ErrorState message={`Backend connection failed: ${error}`}/>} {!loading&&!error&&<DataTable columns={columns} rows={filtered}/>}</div>
    {open&&<div className="modal-backdrop" onMouseDown={e=>e.target===e.currentTarget&&!saving&&setOpen(false)}><form className="upload-modal" onSubmit={save}><div className="modal-head"><div><h2>Add industry partner</h2><p>Create the institution's partner master record. Contact details stay on the partner record until a dedicated contact is added.</p></div><button type="button" className="icon-button small" onClick={()=>setOpen(false)} disabled={saving}>×</button></div><div className="upload-grid">
      <label className="upload-field"><span>Partner name *</span><input name="name" required placeholder="e.g. ABC Technologies Pvt Ltd"/></label><label className="upload-field"><span>Sector</span><input name="sector" placeholder="Cloud / Manufacturing / Finance"/></label><label className="upload-field"><span>Website</span><input name="website" type="url" placeholder="https://example.com"/></label><label className="upload-field"><span>Contact person</span><input name="contact_person" placeholder="Industry SPOC"/></label><label className="upload-field"><span>Contact email</span><input name="contact_email" type="email" placeholder="spoc@company.com"/></label><label className="upload-field"><span>Contact phone</span><input name="contact_phone" placeholder="+91..."/></label><label className="upload-field"><span>Status *</span><select name="status" defaultValue="ACTIVE"><option value="ACTIVE">Active</option><option value="PROSPECT">Prospect</option><option value="DORMANT">Dormant</option><option value="CONCLUDED">Concluded</option></select></label>
    </div><div className="upload-note">The system prevents duplicate partner names within the institution. The relationship owner can be assigned later when the responsible faculty member is known; no person/contact record is invented automatically.</div><div className="modal-actions"><button type="button" className="secondary-button" onClick={()=>setOpen(false)} disabled={saving}>Cancel</button><button className="primary-button" disabled={saving}>{saving?"Saving…":"Add partner"}</button></div></form></div>}
  </>;
}
