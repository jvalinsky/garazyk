import { useRuntime } from "../runtime.ts";

interface ScenarioRunnerProps {
  scenarioId: string;
  needsPds2: boolean;
}

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
