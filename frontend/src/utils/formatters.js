export const titleCase = (value = "") =>
  value.toLowerCase().replaceAll("_", " ").replace(/\b\w/g, (c) => c.toUpperCase());

export const formatDate = (value) => {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-IN", { day: "2-digit", month: "short", year: "numeric" })
    .format(new Date(value));
};

export const statusClass = (value = "") =>
  value.toLowerCase().replaceAll("_", "-");