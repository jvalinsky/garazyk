import { useState, useEffect } from "preact/hooks";
import { activeRun } from "../signals.ts";

/**
 * Topology Inspector — shows details about a selected topology.
 */

export interface TopologyPreview {
  name: string;
  description?: string;
  roles: string[];
  capabilities: string[];
}

interface TopologyInspectorProps {
  topology: TopologyPreview | null;
}

export default function TopologyInspector({ topology }: TopologyInspectorProps) {
  const [stats, setStats] = useState<Record<string, { cpu: string; mem: string }>>({});

  useEffect(() => {
    let interval: number | undefined;

    const fetchMetrics = async () => {
      if (activeRun.value && activeRun.value.status === "running") {
        try {
          const res = await fetch("/api/runs/active/metrics");
          if (res.ok) {
            const data = await res.json();
            setStats(data.stats);
          }
        } catch (e) {
          console.error("Failed to fetch metrics", e);
        }
      } else {
        setStats({});
      }
    };

    if (activeRun.value && activeRun.value.status === "running") {
      fetchMetrics();
      interval = setInterval(fetchMetrics, 3000);
    }

    return () => {
      if (interval) clearInterval(interval);
    };
  }, [activeRun.value?.status]);

  if (!topology) {
    return (
      <div class="topology-inspector-empty">
        Select a topology to see configuration details.
      </div>
    );
  }

  return (
    <div class="topology-inspector">
      <div class="topology-inspector-header">
        <h3 class="topology-inspector-title">{topology.name}</h3>
        {topology.description && (
          <p class="topology-inspector-description">{topology.description}</p>
        )}
      </div>

      <div class="topology-inspector-section">
        <div class="topology-inspector-label">Roles</div>
        <div class="role-grid">
          {topology.roles.map((role) => {
            const s = stats[role];
            return (
              <div key={role} class="role-metric-card">
                <div class="role-name-wrapper">
                  <span class="badge badge-secondary">{role}</span>
                </div>
                {s && (
                  <div class="metric-line">
                    <span class="metric-val">CPU: {s.cpu}</span>
                    <span class="metric-val">RAM: {s.mem}</span>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div class="topology-inspector-section">
        <div class="topology-inspector-label">Capabilities</div>
        <div class="badge-list">
          {topology.capabilities.map((cap) => (
            <span key={cap} class="badge badge-outline">
              {cap}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

