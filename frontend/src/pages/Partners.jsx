import { useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { partners } from "../data/mockData";

export default function Partners() {
  const [query, setQuery] = useState("");
  const filtered = partners.filter(p => `${p.name} ${p.sector}`.toLowerCase().includes(query.toLowerCase()));
  const columns = [
    { key: "name", label: "Partner", render: p => <Link className="table-link" to={`/health?partner=${p.id}`}>{p.name}</Link> },
    { key: "sector", label: "Sector" },
    { key: "status", label: "Status", render: p => <StatusBadge value={p.status} /> },
    { key: "score", label: "Health score", render: p => <span className={`score-inline ${p.score >= 80 ? "good" : p.score >= 60 ? "mid" : "bad"}`}>{p.score}</span> },
    { key: "mous", label: "Active MoUs" },
    { key: "activities", label: "Activities · 12m" },
    { key: "lastActivity", label: "Last activity" }
  ];

  return <>
    <PageHeader eyebrow="PARTNER REGISTER" title="Industry Partners" description="The authoritative partner register used by Agent 28 for MoUs, activities and engagement health."
      action={<button className="primary-button"><span>+</span> Add partner</button>} />
    <div className="toolbar">
      <div className="filter-search"><span>⌕</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search partner or sector..." /></div>
      <select><option>All statuses</option><option>Active</option><option>Dormant</option></select>
      <select><option>All sectors</option><option>IT Services</option><option>Consulting</option><option>Industrial Automation</option></select>
    </div>
    <div className="panel">
      <DataTable columns={columns} rows={filtered} />
    </div>
  </>;
}