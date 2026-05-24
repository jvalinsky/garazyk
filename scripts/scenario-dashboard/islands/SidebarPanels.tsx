/** Shared sidebar panel sections for desktop and mobile drawer. @module SidebarPanels */
import { categorize } from "../utils.ts";
import { useRuntime } from "../runtime.ts";
import TopologyInspector from "./TopologyInspector.tsx";

export type SidebarPanelView = "all" | "scenarios" | "network" | "topology";

interface SidebarPanelsProps {
  view?: SidebarPanelView;
  activeScenario?: string;
  /** Called when the user follows an in-app link (closes mobile drawer). */
  onNavigate?: () => void;
}

const CATEGORIES: Record<string, string> = {
  core: "Core ATProto",
  identity: "UI & Identity",
  scale: "Scale & AppView",
  edge: "Edge Cases",
};

function showSection(view: SidebarPanelView, section: SidebarPanelView): boolean {
  return view === "all" || view === section;
}

/** Render searchable scenarios, network summary, and topology inspector sections. */
export default function SidebarPanels({
  view = "all",
  activeScenario,
  onNavigate,
}: SidebarPanelsProps) {
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
    return scen.filter((item) =>
      item.id.includes(term) || item.name.toLowerCase().includes(term)
    );
  };

  const runningServices = services.filter((svc) => svc.status === "running").length;
  const totalServices = services.length;
  const dotClass = runningServices === 0
    ? "stopped"
    : runningServices < totalServices
    ? "starting"
    : "running";

  return (
    <>
      {showSection(view, "scenarios") && (
        <div class="sidebar-section">
          <label class="sidebar-search-label" for="sidebar-scenario-search">
            Search scenarios
          </label>
          <input
            id="sidebar-scenario-search"
            type="search"
            class="filter-input sidebar-search-input"
            placeholder="Search scenarios..."
            value={searchTerm}
            onInput={(e) =>
              dispatch({
                type: "ux/setSearchTerm",
                term: (e.target as HTMLInputElement).value,
              })}
          />
        </div>
      )}

      {showSection(view, "network") && (
        <div class="sidebar-section">
          <h3 class="sidebar-static-title">Network</h3>
          <div class="sidebar-item">
            <span class={`status-dot ${dotClass}`} />
            <span>{runningServices}/{totalServices} services running</span>
          </div>
          <p class="sidebar-meta-line">
            Topology: <strong>{s.topology.selected}</strong> · Runner:{" "}
            <strong>{s.ux.runner}</strong>
          </p>
          {services.length > 0 && (
            <ul class="mobile-service-list">
              {services.map((svc) => (
                <li key={svc.name} class="mobile-service-row">
                  <span
                    class={`health-dot ${
                      svc.status === "running"
                        ? svc.healthy ? "healthy" : "unhealthy"
                        : svc.status === "starting"
                        ? "starting"
                        : "stopped"
                    }`}
                  />
                  <span class="mobile-service-name">{svc.label}</span>
                  <span class="badge badge-secondary">{svc.status}</span>
                </li>
              ))}
            </ul>
          )}
          <a
            href="#network-status"
            class="btn btn-secondary btn-sm mobile-network-jump"
            onClick={onNavigate}
          >
            Open network controls
          </a>
        </div>
      )}

      {showSection(view, "scenarios") &&
        Object.entries(CATEGORIES).map(([key, label]) => {
          const isCollapsed = collapsedCategories.has(key);
          const filtered = filterScenarios(grouped[key] || []);
          const hasResults = filtered.length > 0;
          const sectionId = `sidebar-category-${key}`;

          return (
            <div class="sidebar-section" key={key}>
              <button
                type="button"
                class="sidebar-section-title"
                aria-expanded={!isCollapsed}
                aria-controls={sectionId}
                onClick={() => toggleCollapsed(key)}
              >
                <span>{label}</span>
                <span class="sidebar-section-chevron" aria-hidden="true">
                  {isCollapsed ? "▶" : "▼"}
                </span>
              </button>
              <div id={sectionId} hidden={isCollapsed}>
                {!isCollapsed && hasResults && filtered.map((sc) => (
                  <a
                    href={`/scenario/${sc.id}`}
                    class={`sidebar-item ${
                      activeScenario === sc.id ? "active" : ""
                    }`}
                    key={sc.id}
                    onClick={onNavigate}
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
                  <p class="sidebar-empty-hint">
                    No scenarios match "{searchTerm}"
                  </p>
                )}
              </div>
            </div>
          );
        })}

      {showSection(view, "topology") && <TopologyInspector />}
    </>
  );
}
