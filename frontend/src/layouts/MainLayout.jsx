import { NavLink, Outlet, useLocation } from "react-router-dom";
import Icon from "../components/Icons";

const nav = [
  { to: "/", label: "Overview", icon: "grid" },
  { to: "/partners", label: "Industry Partners", icon: "building" },
  { to: "/mous", label: "MoU Intelligence", icon: "file" },
  { to: "/activities", label: "Activities & Outcomes", icon: "activity" },
  { to: "/health", label: "Engagement Health", icon: "heart" },
  { to: "/recommendations", label: "Recommendations", icon: "spark" },
  { to: "/evidence", label: "Accreditation Evidence", icon: "shield" }
];

export default function MainLayout() {
  const location = useLocation();
  const current = nav.find((item) => item.to !== "/" && location.pathname.startsWith(item.to)) || nav[0];

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brand-mark">V</div>
          <div>
            <div className="brand-name">VIGNAN'S</div>
            <div className="brand-sub">INDUSTRY INTERACTION</div>
          </div>
        </div>

        <div className="agent-chip">
          <span className="agent-dot" />
          <div>
            <strong>Agent 28</strong>
            <span>Industry Interaction</span>
          </div>
        </div>

        <nav className="nav-list">
          {nav.map((item) => (
            <NavLink key={item.to} to={item.to} end={item.to === "/"} className={({ isActive }) => isActive ? "nav-item active" : "nav-item"}>
              <Icon name={item.icon} size={19} />
              <span>{item.label}</span>
            </NavLink>
          ))}
        </nav>

        <div className="sidebar-bottom">
          <NavLink to="/agent-runs" className={({ isActive }) => isActive ? "nav-item active" : "nav-item"}>
            <Icon name="activity" size={19} />
            <span>Agent Runs</span>
          </NavLink>
          <div className="system-card">
            <div className="system-status"><span className="live-dot" /> System healthy</div>
            <small>Last sync · 12:30 PM</small>
          </div>
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div className="mobile-title">
            <Icon name="menu" size={22} />
            <span>{current.label}</span>
          </div>
          <div className="breadcrumb">
            <span>Industry Interaction Agent</span>
            <Icon name="chevron" size={14} />
            <strong>{current.label}</strong>
          </div>
          <div className="top-actions">
            <div className="search-box">
              <Icon name="search" size={17} />
              <input placeholder="Search partners, MoUs, activities..." />
              <kbd>⌘ K</kbd>
            </div>
            <button className="icon-button" aria-label="Notifications"><Icon name="bell" size={19} /><span className="notif-dot" /></button>
            <div className="avatar">IR</div>
          </div>
        </header>
        <section className="content"><Outlet /></section>
      </main>
    </div>
  );
}