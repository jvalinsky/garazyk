/**
 * Scenario authoring primitives for Garazyk end-to-end tests.
 *
 * Mutable environment globals live under `@garazyk/hamownia/config`.
 * Network orchestration, diagnostics, progress, OTel, lifecycle, and mock
 * services are exposed through explicit subpaths.
 *
 * @module hamownia
 */

export {
  ScenarioResult,
  StepResult,
  StepStatus,
  timedCall,
  timedCallChecked,
  unwrapOutcome,
} from "./runner.ts";
export type { ScenarioReport, TimedCallOutcome } from "./runner.ts";
export { assert } from "./assertions.ts";
export {
  browserFlows,
  formatRequirement,
  getOptional,
  getParameters,
  getRequires,
  getTimeout,
  hasRequirement,
  isScenarioCompatible,
  missingRequirements,
  missingRequirementsDescription,
  needsPds2,
  normalizeScenarioRequirements,
  SCENARIO_MANIFESTS,
} from "./scenario_metadata.ts";
export type { ScenarioInfo, ScenarioManifest } from "./scenario_metadata.ts";
export {
  discoverScenarios,
  normalizeScenarioId,
  selectScenarios,
} from "./scenario_selector.ts";
export {
  attachPublicNetworkLeakGuard,
  blockedPublicHosts,
} from "./browser_flow.ts";
export type { RunnerArgs } from "./run_scenarios_types.ts";
export type { ScenarioExecutionResult } from "./run_loop.ts";
export type { ScenarioRequirement } from "@garazyk/schemat";
export {
  handleMockTwilioRequest,
  MockTwilioServer,
  parseMockTwilioConfig,
  serveMockTwilio,
  startMockTwilioServer,
  stopMockTwilioServer,
} from "./mock_twilio.ts";
export type {
  MockState,
  MockTwilioServerConfig,
  MockVerificationState,
} from "./mock_twilio.ts";
export {
  discoverLocalDidTargets,
  discoverRemoteAccountsViaAdminApi,
  discoverRemoteAccountsViaSsh,
  firstExistingServiceDbPath,
  resolveTargets,
} from "./account_discovery.ts";
export type {
  ResolveTargetsOptions,
  TargetIdentity,
} from "./account_discovery.ts";
export {
  getExistingInviteCodeViaSsh,
  insertInviteCodeViaSsh,
} from "./invite_code.ts";
export {
  handleAccountCreate,
  handlePostCreate,
  handleProfileUpdate,
  runKaszlak,
} from "./pds_cli.ts";
export type { PdsCliConfig } from "./pds_cli.ts";
