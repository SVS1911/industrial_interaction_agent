const paths = {
  grid: "M4 4h6v6H4z M14 4h6v6h-6z M4 14h6v6H4z M14 14h6v6h-6z",
  building: "M4 20V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v15 M8 7h4 M8 11h4 M8 15h4 M16 9h4v11",
  file: "M6 2h8l4 4v16H6z M14 2v5h5 M9 12h6 M9 16h6",
  activity: "M3 12h4l2-7 4 14 2-7h6",
  heart: "M20.8 8.5c0 5.5-8.8 10.5-8.8 10.5S3.2 14 3.2 8.5A5.1 5.1 0 0 1 12 5a5.1 5.1 0 0 1 8.8 3.5Z",
  spark: "M12 2l1.8 6.2L20 10l-6.2 1.8L12 18l-1.8-6.2L4 10l6.2-1.8L12 2Z M19 16l.7 2.3L22 19l-2.3.7L19 22l-.7-2.3L16 19l2.3-.7L19 16Z",
  shield: "M12 3l7 3v5c0 4.7-3 8.3-7 10-4-1.7-7-5.3-7-10V6l7-3Z M9 12l2 2 4-4",
  upload: "M12 16V4 M8 8l4-4 4 4 M4 16v4h16v-4",
  search: "M11 19a8 8 0 1 1 5.7-2.3L21 21",
  bell: "M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9 M10 21h4",
  chevron: "M9 18l6-6-6-6",
  arrow: "M5 12h14 M13 6l6 6-6 6",
  menu: "M4 6h16 M4 12h16 M4 18h16",
  plus: "M12 5v14 M5 12h14"
};

export default function Icon({ name, size = 20, strokeWidth = 1.8 }) {
  const d = paths[name] || paths.grid;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke="currentColor" strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"
      aria-hidden="true">
      {d.split(" M").map((segment, i) => <path key={i} d={(i ? "M" : "") + segment} />)}
    </svg>
  );
}