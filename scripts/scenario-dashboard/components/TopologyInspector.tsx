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

export function TopologyInspector({ topology }: TopologyInspectorProps) {
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
        <div class="badge-list">
          {topology.roles.map((role) => (
            <span key={role} class="badge badge-secondary">
              {role}
            </span>
          ))}
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
