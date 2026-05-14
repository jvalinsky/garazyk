import { categorize } from "../utils.ts";

export interface ScenarioMeta {
  id: string;
  name: string;
  category: string;
  needsPds2: boolean;
  lastStatus?: "passed" | "failed" | "skipped" | null;
}

export interface ServiceStatus {
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
  const grouped: Record<string, ScenarioMeta[]> = {};
  for (const s of scenarios) {
    const cat = categorize(s.id);
    if (!grouped[cat]) grouped[cat] = [];
    grouped[cat].push(s);
  }

  const runningServices = services.filter((s) => s.status === "running").length;
  const totalServices = services.length;
  const dotClass = runningServices === 0 ? "stopped"
               : runningServices < totalServices ? "starting"
               : "running";

  return (
    <aside class="sidebar">
      <div class="sidebar-section">
        <div class="sidebar-section-title">Network</div>
        <div class="sidebar-item">
          <span class={`status-dot ${dotClass}`} />
          <span>{runningServices}/{totalServices} services</span>
        </div>
      </div>

      {Object.entries(CATEGORIES).map(([key, label]) => (
        <div class="sidebar-section" key={key}>
          <div class="sidebar-section-title">{label}</div>
          {(grouped[key] || []).map((s) => (
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
        </div>
      ))}
    </aside>
  );
}
