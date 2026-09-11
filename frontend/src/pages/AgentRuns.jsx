import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { agentRuns } from "../data/mockData";

export default function AgentRuns() {
  const columns = [
    { key: "id", label: "Run ID" },
    { key: "agent", label: "Agent" },
    { key: "started", label: "Started" },
    { key: "records", label: "Records" },
    { key: "version", label: "Model / version" },
    { key: "status", label: "Status", render: r => <StatusBadge value={r.status} /> }
  ];
  return <>
    <PageHeader eyebrow="AGENTOPS" title="Agent Runs" description="Traceable execution history for Agent 28 processing and recommendation runs." />
    <div className="panel"><DataTable columns={columns} rows={agentRuns} /></div>
  </>;
}