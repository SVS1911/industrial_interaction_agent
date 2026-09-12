import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate, titleCase } from "../utils/formatters";

export default function Activities() {
  const { data: activitiesData, loading, error } = useApiData(() => api.getActivities(), []);
  const activities = activitiesData ?? [];
  const columns = [
    { key: "title", label: "Activity", render: a => <div><strong>{a.title}</strong><small className="table-sub">{a.partner}</small></div> },
    { key: "type", label: "Type", render: a => titleCase(a.type) },
    { key: "date", label: "Date", render: a => formatDate(a.date) },
    { key: "department", label: "Department" },
    { key: "participants", label: "Participants" },
    { key: "mode", label: "Mode", render: a => titleCase(a.mode) },
    { key: "status", label: "Status", render: a => <StatusBadge value={a.status} /> },
    { key: "evidence", label: "Evidence", render: a => a.evidence ? <span className="evidence-ok">● Linked</span> : <span className="evidence-missing">● Missing</span> }
  ];
  const conducted = activities.filter(a => a.status === "CONDUCTED");
  const participants = activities.reduce((sum, a) => sum + a.participants, 0);
  const evidenced = activities.filter(a => a.evidence).length;

  return <>
    <PageHeader eyebrow="AGENT 2 · ACTIVITY & OUTCOME" title="Activities & Outcomes" description="Track what actually happened and connect activities to partners, MoUs, outcomes and evidence."
      action={<button className="primary-button" disabled title="Activity creation API is not implemented yet.">+ Record activity</button>} />
    <div className="stats-strip">
      <div><strong>{activities.length}</strong><span>Activities shown</span></div>
      <div><strong>{conducted.length}</strong><span>Conducted</span></div>
      <div><strong>{participants.toLocaleString()}</strong><span>Participants</span></div>
      <div><strong>{evidenced}/{activities.length}</strong><span>With evidence</span></div>
    </div>
    <div className="panel">
      {loading && <LoadingState />}
      {error && <ErrorState message={`Backend connection failed: ${error}`} />}
      {!loading && !error && <DataTable columns={columns} rows={activities} />}
    </div>
  </>;
}
