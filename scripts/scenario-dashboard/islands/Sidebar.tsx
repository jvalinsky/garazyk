/** Sidebar island — desktop navigation column. @module Sidebar */
import SidebarPanels from "./SidebarPanels.tsx";

interface SidebarProps {
  activeScenario?: string;
}

/** Desktop sidebar with search, scenarios, network summary, and topology. */
export default function Sidebar({ activeScenario }: SidebarProps) {
  return (
    <aside class="sidebar">
      <SidebarPanels view="all" activeScenario={activeScenario} />
    </aside>
  );
}
