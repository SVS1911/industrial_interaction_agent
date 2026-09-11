import { useState } from "react";
import PageHeader from "../components/PageHeader";
import StatusBadge from "../components/StatusBadge";
import { recommendations } from "../data/mockData";
import Icon from "../components/Icons";

export default function Recommendations() {
  const [selected, setSelected] = useState(recommendations[0]);
  return <>
    <PageHeader eyebrow="AGENT 4 · INDUSTRY INTELLIGENCE" title="Recommendations" description="Turn engagement signals and industry context into prioritised actions for the relationship team." />
    <div className="recommend-layout">
      <div className="panel">
        <div className="panel-head"><div><h2>Recommended actions</h2><p>Prioritised by urgency and impact</p></div></div>
        <div className="recommend-full-list">
          {recommendations.map(r => <button className={`recommend-card ${selected.id === r.id ? "selected" : ""}`} onClick={() => setSelected(r)} key={r.id}>
            <div className="recommend-card-top"><StatusBadge value={r.priority} /><span>{r.status}</span></div>
            <strong>{r.title}</strong>
            <p>{r.reason}</p>
            <small>{r.partner}</small>
          </button>)}
        </div>
      </div>
      <div className="panel recommendation-detail">
        <div className="agent-badge"><Icon name="spark" size={18} /> Agent-generated recommendation</div>
        <StatusBadge value={selected.priority} />
        <h2>{selected.title}</h2>
        <p className="detail-copy">{selected.reason}</p>
        <div className="action-box"><span>Suggested next action</span><strong>{selected.action}</strong></div>
        <div className="detail-footer"><span>Partner</span><strong>{selected.partner}</strong><button className="primary-button">Create action item</button></div>
      </div>
    </div>
  </>;
}