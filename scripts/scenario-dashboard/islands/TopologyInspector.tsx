/** Topology inspector island — shows selected topology details and per-role metrics. @module TopologyInspector */
import { useRuntime } from "../runtime.ts";

/** Render topology details: roles, metrics, and capabilities. */
export default function TopologyInspector() {
  const { state } = useRuntime();
  const s = state.value;
  const topology = s.topology.preview;
  const stats = s.metrics.stats;

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
            const st = stats[role];
            return (
              <div key={role} class="role-metric-card">
                <div class="role-name-wrapper">
                  <span class="badge badge-secondary">{role}</span>
                </div>
                {st && (
                  <div class="metric-line">
                    <span class="metric-val">CPU: {st.cpu}</span>
                    <span class="metric-val">RAM: {st.mem}</span>
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
