import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";

export default function Partners() {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [sector, setSector] = useState("");
  const { data: partnersData, loading, error } = useApiData(() => api.getPartners(), []);
  const partners = partnersData ?? [];

  const sectors = useMemo(() => [...new Set(partners.map((p) => p.sector).filter(Boolean))].sort(), [partners]);
  const filtered = partners.filter((p) => {
    const matchesQuery = `${p.name} ${p.sector}`.toLowerCase().includes(query.toLowerCase());
    const matchesStatus = !status || p.status === status;
    const matchesSector = !sector || p.sector === sector;
    return matchesQuery && matchesStatus && matchesSector;
  });

  const columns = [
    { key: "name", label: "Partner", render: p => <Link className="table-link" to={`/health?partner=${p.id}`}>{p.name}</Link> },
    { key: "sector", label: "Sector" },
    { key: "status", label: "Status", render: p => <StatusBadge value={p.status} /> },
    { key: "score", label: "Health score", render: p => p.score == null ? "—" : <span className={`score-inline ${p.score >= 80 ? "good" : p.score >= 60 ? "mid" : "bad"}`}>{p.score}</span> },
    { key: "mous", label: "Active MoUs" },
    { key: "activities", label: "Activities · 12m" },
    { key: "lastActivity", label: "Last activity", render: p => p.lastActivity || "—" }
  ];

  return <>
    <PageHeader eyebrow="PARTNER REGISTER" title="Industry Partners" description="The authoritative partner register used by Agent 28 for MoUs, activities and engagement health."
      action={<button className="primary-button" disabled title="Partner creation API is not implemented yet."><span>+</span> Add partner</button>} />
    <div className="toolbar">
      <div className="filter-search"><span>⌕</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search partner or sector..." /></div>
      <select value={status} onChange={(e) => setStatus(e.target.value)}>
        <option value="">All statuses</option>
        <option value="ACTIVE">Active</option>
        <option value="DORMANT">Dormant</option>
        <option value="PROSPECT">Prospect</option>
        <option value="CONCLUDED">Concluded</option>
      </select>
      <select value={sector} onChange={(e) => setSector(e.target.value)}>
        <option value="">All sectors</option>
        {sectors.map((value) => <option key={value} value={value}>{value}</option>)}
      </select>
    </div>
    <div className="panel">
      {loading && <LoadingState />}
      {error && <ErrorState message={`Backend connection failed: ${error}`} />}
      {!loading && !error && <DataTable columns={columns} rows={filtered} />}
    </div>
  </>;
}
