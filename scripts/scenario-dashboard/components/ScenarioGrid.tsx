/** Scenario card grid component. @module ScenarioGrid */
import ScenarioCard from "../islands/ScenarioCard.tsx";

/** Props for the ScenarioGrid component. */
interface ScenarioGridProps {
  scenarios: Array<{
    id: string;
    name: string;
    status?: "passed" | "failed" | "skipped" | "running" | null;
    passed?: number;
    failed?: number;
    skipped?: number;
  }>;
}

/** Render a grid of ScenarioCard components. */
export default function ScenarioGrid({ scenarios }: ScenarioGridProps) {
  return (
    <div class="scenario-grid">
      {scenarios.map((s) => (
        <ScenarioCard
          key={s.id}
          id={s.id}
          name={s.name}
          status={s.status}
          passed={s.passed}
          failed={s.failed}
          skipped={s.skipped}
        />
      ))}
    </div>
  );
}
