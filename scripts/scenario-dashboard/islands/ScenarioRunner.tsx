/** Scenario runner button island — dispatches a start-run request for a single scenario. @module ScenarioRunner */
import { useRuntime } from "../runtime.ts";
import { deriveButtonProps } from "./ScenarioRunnerHelpers.ts";

interface ScenarioRunnerProps {
  scenarioId: string;
  needsPds2: boolean;
}

/** Render a "Run This Scenario" button. */
export default function ScenarioRunner({ scenarioId, needsPds2 }: ScenarioRunnerProps) {
  const { state, dispatch } = useRuntime();

  const { disabled, label, onClickIgnored } = deriveButtonProps(
    state.value.ux.agentMode,
    state.value.ux.busy,
  );
  const agentMode = state.value.ux.agentMode;

  const handleRun = () => {
    if (onClickIgnored) return;
    dispatch({ type: "runs/startRequested", scenarioIds: [scenarioId], pds2: needsPds2 });
  };

  return (
    <button
      class="btn btn-primary"
      onClick={handleRun}
      disabled={disabled}
      title={agentMode ? "Single-scenario runs are not supported in agent mode. Uncheck 'Agent' in the toolbar to run individually." : undefined}
    >
      {label}
    </button>
  );
}
