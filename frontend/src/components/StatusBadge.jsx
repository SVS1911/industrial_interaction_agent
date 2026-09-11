import { titleCase, statusClass } from "../utils/formatters";

export default function StatusBadge({ value }) {
  return <span className={`status-badge ${statusClass(value)}`}>{titleCase(value)}</span>;
}