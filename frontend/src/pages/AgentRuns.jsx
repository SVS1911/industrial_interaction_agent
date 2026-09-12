import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import DataTable from "../components/DataTable";
import { api } from "../services/api";
import useApiData, { ErrorState, LoadingState } from "../hooks/useApiData";
import { formatDate } from "../utils/formatters";

export default function AgentRuns() {
  const { data: agentRunsData, loading, error } = useApiData(() => api.getAgentRuns(), []);
  const agentRuns = agentRunsData ?? [];
  const columns = [
    { key: "id", label: "Run ID" },
    { key: "agent", label: "Agent" },
    { key: "started", label: "Started", render: r => formatDate(r.started) },
    { key: "records", label: "Records" },
    { key: "version", label: "Model / version" },
    { key: "status", label: "Status", render: r => <StatusBadge value={r.status} /> }
  ];
  return <>
    <PageHeader eyebrow="AGENTOPS" title="Agent Runs" description="Traceable execution history for Agent 28 processing and recommendation runs." />
    <div className="panel">
      {loading && <LoadingState message="Loading agent runs from the backend…" />}
      {error && <ErrorState message={`Backend connection failed: ${error}`} />}
      {!loading && !error && <DataTable columns={columns} rows={agentRuns} />}
    </div>
  </>;
}
