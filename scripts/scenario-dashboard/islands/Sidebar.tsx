import { useSignal } from "@preact/signals";
import { categorize } from "../utils.ts";

interface ScenarioMeta {
  id: string;
  name: string;
  category: string;
  needsPds2: boolean;
  lastStatus?: "passed" | "failed" | "skipped" | null;
}

interface ServiceStatus {
  name: string;
  url: string;
  status: "running" | "stopped" | "starting" | "error";
  healthy?: boolean;
}

interface SidebarProps {
  scenarios: ScenarioMeta[];
  services: ServiceStatus[];
  activeScenario?: string;
}

const CATEGORIES: Record<string, string> = {
  core: "Core ATProto",
  identity: "UI & Identity",
  scale: "Scale & AppView",
  edge: "Edge Cases",
};

export default function Sidebar({ scenarios, services, activeScenario }: SidebarProps) {
  const collapsed = useSignal<Set<string>>(new Set(["edge"]));
  const searchTerm = useSignal("");

  const grouped: Record<string, ScenarioMeta[]> = {};
  for (const s of scenarios) {
    const cat = categorize(s.id);
    if (!grouped[cat]) grouped[cat] = [];
    grouped[cat].push(s);
  }

  const toggleCollapsed = (cat: string) => {
    const next = new Set(collapsed.value);
    if (next.has(cat)) {
      next.delete(cat);
    } else {
      next.add(cat);
    }
    collapsed.value = next;
  };

  const filterScenarios = (scen: ScenarioMeta[]): ScenarioMeta[] => {
    if (!searchTerm.value) return scen;
    const term = searchTerm.value.toLowerCase();
    return scen.filter(s =>
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
          value={searchTerm.value}
          onInput={(e) => searchTerm.value = (e.target as HTMLInputElement).value}
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
        const isCollapsed = collapsed.value.has(key);
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
            {!isCollapsed && hasResults && filtered.map((s) => (
              <a
                href={`/scenario/${s.id}`}
                class={`sidebar-item ${activeScenario === s.id ? "active" : ""}`}
                key={s.id}
              >
                <span
                  class={`status-dot ${
                    s.lastStatus === "passed"
                      ? "running"
                      : s.lastStatus === "failed"
                      ? "failed"
                      : s.lastStatus === "skipped"
                      ? "skipped"
                      : "stopped"
                  }`}
                />
                <span>{s.id} {s.name}</span>
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
    </aside>
  );
}
