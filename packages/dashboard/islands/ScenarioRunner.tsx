/** Scenario runner button island — dispatches a start-run request for a single scenario. @module ScenarioRunner */
import { useRuntime } from "../runtime.ts";

interface ScenarioRunnerProps {
  scenarioId: string;
  needsPds2: boolean;
}

/** Render a "Run This Scenario" button. */
export default function ScenarioRunner({ scenarioId, needsPds2 }: ScenarioRunnerProps) {
  const { state, dispatch } = useRuntime();

  const handleRun = () => {
    dispatch({ type: "runs/startRequested", scenarioIds: [scenarioId], pds2: needsPds2 });
  };

  return (
    <button class="btn btn-primary" onClick={handleRun} disabled={state.value.ux.busy}>
      {state.value.ux.busy ? "Starting Run..." : "Run This Scenario"}
    </button>
  );
}
