import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { evidence } from "../data/mockData";

export default function Evidence() {
  const average = Math.round(evidence.reduce((s,e) => s+e.coverage,0)/evidence.length);
  return <>
    <PageHeader eyebrow="AGENT 5 · ACCREDITATION EVIDENCE" title="Accreditation Evidence" description="Map industry-interaction records to accreditation criteria and identify missing or incomplete evidence." action={<button className="secondary-button">Export report</button>} />
    <div className="evidence-overview">
      <div className="evidence-score"><div className="evidence-number">{average}%</div><div><strong>Evidence coverage</strong><span>Across current industry-interaction criteria</span></div></div>
      <div className="evidence-kpi"><strong>{evidence.filter(e => e.status === "READY").length}</strong><span>Ready</span></div>
      <div className="evidence-kpi"><strong>{evidence.filter(e => e.status === "PARTIAL").length}</strong><span>Partial</span></div>
      <div className="evidence-kpi"><strong>{evidence.filter(e => e.status === "IN_REVIEW").length}</strong><span>In review</span></div>
    </div>
    <div className="panel">
      <div className="panel-head"><div><h2>Evidence mapping</h2><p>Generated from authoritative Agent 28 sources</p></div></div>
      <div className="evidence-table">
        {evidence.map(e => <div className="evidence-row" key={e.id}>
          <div className="criterion">{e.criterion}</div>
          <div className="evidence-title"><strong>{e.title}</strong><span>{e.source} · {e.period}</span></div>
          <div className="coverage"><div className="progress"><span style={{width:`${e.coverage}%`}} /></div><strong>{e.coverage}%</strong></div>
          <StatusBadge value={e.status} />
          <button className="icon-button small">→</button>
        </div>)}
      </div>
    </div>
  </>;
}