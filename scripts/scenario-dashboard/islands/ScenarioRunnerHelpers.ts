/**
 * Pure props derivation helpers for the ScenarioRunner island.
 *
 * Extracted for unit-testability — these functions take raw dashboard state
 * and derive the button's label, disabled state, and onClick guard without
 * any Preact or signal dependencies.
 *
 * @module ScenarioRunnerHelpers
 */

export interface ScenarioRunnerButtonProps {
  /** Whether the button is disabled. */
  disabled: boolean;
  /** Button label text. */
  label: string;
  /** Whether clicking should be a no-op (agentMode guard). */
  onClickIgnored: boolean;
}

/**
 * Derive button props from UX state for the scenario run button.
 *
 *   agentMode | busy | disabled | label
 *   -----------|------|----------|------------------------------------------
 *   true       | *    | true     | "Disable Agent Mode to run individually"
 *   false      | true | true     | "Starting Run..."
 *   false      | false| false    | "Run This Scenario"
 */
export function deriveButtonProps(
  agentMode: boolean,
  busy: boolean,
): ScenarioRunnerButtonProps {
  const disabled = busy || agentMode;
  let label: string;
  if (agentMode) {
    label = "Disable Agent Mode to run individually";
  } else if (busy) {
    label = "Starting Run...";
  } else {
    label = "Run This Scenario";
  }
  return { disabled, label, onClickIgnored: agentMode };
}
