import { signal } from "@preact/signals";
import { TopologyPreview } from "./islands/TopologyInspector.tsx";
import { Run } from "./services/types.ts";

export const selectedTopology = signal("garazyk-default");
export const topologyPreview = signal<TopologyPreview | null>(null);
export const activeRun = signal<Run | null>(null);

const IS_BROWSER = typeof document !== "undefined";

// Persist selection
if (IS_BROWSER && typeof localStorage !== "undefined") {
  const saved = localStorage.getItem("garazyk-dashboard-topology");
  if (saved) {
    selectedTopology.value = saved;
  }

  selectedTopology.subscribe((val) => {
    localStorage.setItem("garazyk-dashboard-topology", val);
  });
}

// Fetch preview and poll for run status — only in browser
if (IS_BROWSER) {
  selectedTopology.subscribe(async (name) => {
    try {
      const res = await fetch(`/api/topologies/${name}`);
      if (res.ok) {
        topologyPreview.value = await res.json();
      }
    } catch (e) {
      console.error("Failed to fetch topology preview:", e);
    }
  });

  // Poll for active run status
  const pollActiveRun = async () => {
    try {
      const res = await fetch("/api/runs/active");
      if (res.ok) {
        const { activeRun: data } = await res.json();
        activeRun.value = data;
      }
    } catch (e) {
      console.error("Failed to poll active run:", e);
    }
  };

  setInterval(pollActiveRun, 2000);
  pollActiveRun();
}
