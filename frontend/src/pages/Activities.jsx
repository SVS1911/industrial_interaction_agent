import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { activities } from "../data/mockData";
import { formatDate, titleCase } from "../utils/formatters";

export default function Activities() {
  const columns = [
    { key: "title", label: "Activity", render: a => <div><strong>{a.title}</strong><small className="table-sub">{a.partner}</small></div> },
    { key: "type", label: "Type", render: a => titleCase(a.type) },
    { key: "date", label: "Date", render: a => formatDate(a.date) },
    { key: "department", label: "Department" },
    { key: "participants", label: "Participants" },
    { key: "mode", label: "Mode" },
    { key: "status", label: "Status", render: a => <StatusBadge value={a.status} /> },
    { key: "evidence", label: "Evidence", render: a => a.evidence ? <span className="evidence-ok">● Linked</span> : <span className="evidence-missing">● Missing</span> }
  ];
  return <>
    <PageHeader eyebrow="AGENT 2 · ACTIVITY & OUTCOME" title="Activities & Outcomes" description="Track what actually happened and connect activities to partners, MoUs, outcomes and evidence."
      action={<button className="primary-button">+ Record activity</button>} />
    <div className="stats-strip">
      <div><strong>{activities.length}</strong><span>Activities shown</span></div>
      <div><strong>{activities.filter(a => a.status === "CONDUCTED").length}</strong><span>Conducted</span></div>
      <div><strong>{activities.reduce((s,a) => s+a.participants,0).toLocaleString()}</strong><span>Participants</span></div>
      <div><strong>{activities.filter(a => a.evidence).length}/{activities.length}</strong><span>With evidence</span></div>
    </div>
    <div className="panel"><DataTable columns={columns} rows={activities} /></div>
  </>;
}