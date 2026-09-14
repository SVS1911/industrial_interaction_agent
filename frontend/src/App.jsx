import { Navigate, Route, Routes } from "react-router-dom";
import MainLayout from "./layouts/MainLayout";
import Dashboard from "./pages/Dashboard";
import Partners from "./pages/Partners";
import Mous from "./pages/Mous";
import MouDetails from "./pages/MouDetails";
import Activities from "./pages/Activities";
import GuestLectures from "./pages/GuestLectures";
import EngagementHealth from "./pages/EngagementHealth";
import Recommendations from "./pages/Recommendations";
import Evidence from "./pages/Evidence";
import AgentRuns from "./pages/AgentRuns";

export default function App() {
  return (
    <Routes>
      <Route element={<MainLayout />}>
        <Route path="/" element={<Dashboard />} />
        <Route path="/partners" element={<Partners />} />
        <Route path="/mous" element={<Mous />} />
        <Route path="/mous/:id" element={<MouDetails />} />
        <Route path="/activities" element={<Activities />} />
        <Route path="/guest-lectures" element={<GuestLectures />} />
        <Route path="/health" element={<EngagementHealth />} />
        <Route path="/recommendations" element={<Recommendations />} />
        <Route path="/evidence" element={<Evidence />} />
        <Route path="/agent-runs" element={<AgentRuns />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}