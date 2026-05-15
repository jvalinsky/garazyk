import { categorize } from "../utils.ts";
import { useRuntime } from "../runtime.ts";
import TopologyInspector from "./TopologyInspector.tsx";

interface SidebarProps {
  activeScenario?: string;
}

const CATEGORIES: Record<string, string> = {
  core: "Core ATProto",
  identity: "UI & Identity",
  scale: "Scale & AppView",
  edge: "Edge Cases",
};

export default function Sidebar({ activeScenario }: SidebarProps) {
  const { state, dispatch } = useRuntime();
  const s = state.value;
  const scenarios = s.scenarios.all;
  const services = s.network.services;

  const collapsedCategories = s.ux.collapsedCategories;
  const searchTerm = s.ux.searchTerm;

  const grouped: Record<string, typeof scenarios> = {};
  for (const sc of scenarios) {
    const cat = categorize(sc.id);
    if (!grouped[cat]) grouped[cat] = [];
    grouped[cat].push(sc);
  }

  const toggleCollapsed = (cat: string) => {
    dispatch({ type: "ux/toggleCategory", category: cat });
  };

  const filterScenarios = (scen: typeof scenarios): typeof scenarios => {
    if (!searchTerm) return scen;
    const term = searchTerm.toLowerCase();
    return scen.filter((s) =>
      s.id.includes(term) || s.name.toLowerCase().includes(term)
    );
  };

  const runningServices = services.filter((s) => s.status === "running").length;
  const totalServices = services.length;
  const dotClass = runningServices === 0 ? "stopped"
               : runningServices < totalServices ? "starting"
               : "running";

  return (
    <aside class="sidebar">
      <div class="sidebar-section">
        <input
          type="text"
          class="filter-input"
          placeholder="Search scenarios..."
          value={searchTerm}
          onInput={(e) => dispatch({ type: "ux/setSearchTerm", term: (e.target as HTMLInputElement).value })}
          style="margin-bottom: var(--space-md);"
        />
      </div>

      <div class="sidebar-section">
        <div class="sidebar-section-title">Network</div>
        <div class="sidebar-item">
          <span class={`status-dot ${dotClass}`} />
          <span>{runningServices}/{totalServices} services</span>
        </div>
      </div>

      {Object.entries(CATEGORIES).map(([key, label]) => {
        const isCollapsed = collapsedCategories.has(key);
        const filtered = filterScenarios(grouped[key] || []);
        const hasResults = filtered.length > 0;

        return (
          <div class="sidebar-section" key={key}>
            <div
              class="sidebar-section-title"
              onClick={() => toggleCollapsed(key)}
              style="cursor: pointer; display: flex; justify-content: space-between; align-items: center; user-select: none;"
            >
              <span>{label}</span>
              <span style="font-size: 0.8em; margin-left: var(--space-xs);">
                {isCollapsed ? "▶" : "▼"}
              </span>
            </div>
            {!isCollapsed && hasResults && filtered.map((sc) => (
              <a
                href={`/scenario/${sc.id}`}
                class={`sidebar-item ${activeScenario === sc.id ? "active" : ""}`}
                key={sc.id}
              >
                <span
                  class={`status-dot ${
                    sc.lastStatus === "passed"
                      ? "running"
                      : sc.lastStatus === "failed"
                      ? "failed"
                      : sc.lastStatus === "skipped"
                      ? "skipped"
                      : "stopped"
                  }`}
                />
                <span>{sc.id} {sc.name}</span>
              </a>
            ))}
            {!isCollapsed && !hasResults && searchTerm && (
              <div style="padding: var(--space-sm) var(--space-lg); font-size: var(--font-size-xs); color: var(--color-text-tertiary);">
                No scenarios match "{searchTerm}"
              </div>
            )}
          </div>
        );
      })}

      <TopologyInspector />
    </aside>
  );
}
