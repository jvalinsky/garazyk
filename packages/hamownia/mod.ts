/**
 * Scenario authoring primitives for Garazyk end-to-end tests.
 *
 * Scenario configuration and character registry live under
 * `@garazyk/hamownia/config`. Injected context is at
 * `@garazyk/hamownia/scenario-context`.
 * Network orchestration, diagnostics, progress, OTel, lifecycle, and mock
 * services are exposed through explicit subpaths.
 *
 * @module hamownia
 */

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
export { assert } from "./assertions.ts";
export {
  attachPublicNetworkLeakGuard,
  blockedPublicHosts,
} from "./browser_flow.ts";
export {
  Character,
  createCharacterRegistry,
  createScenarioConfig,
} from "./config.ts";
export type {
  CharacterRegistry,
  ScenarioConfig,
  ScenarioConfigOptions,
  WebClientConfig,
} from "./config.ts";
export {
  InstrumentationReport,
  OperationTimer,
  PhaseTimer,
  PrometheusScraper,
  StorageMonitor,
} from "./instrumentation.ts";
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
export {
  ScenarioResult,
  StepResult,
  StepStatus,
  timedCall,
  timedCallChecked,
  unwrapOutcome,
} from "./runner.ts";
export type { ScenarioReport, TimedCallOutcome } from "./runner.ts";
export {
  collectDiagnostics,
  createRunContext,
  redactDiagnosticText,
} from "./run_diagnostics.ts";
export type { E2ERunContext } from "./run_diagnostics.ts";
export { createScenarioContext } from "./scenario_context.ts";
export type { ScenarioContext } from "./scenario_context.ts";
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
export type { ScenarioExecutionResult } from "./run_loop.ts";
export type { RunnerArgs } from "./run_scenarios_types.ts";
export type { ScenarioRequirement } from "@garazyk/schemat";
export { appendScenarioLoopResult, buildOtelReexecEnv } from "./run_command.ts";
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
export { runSmoke } from "./smoke_command.ts";

// ---------------------------------------------------------------------------
// Lexicon resolution (re-exported from @garazyk/gruszka/lexicon-resolution)
// ---------------------------------------------------------------------------

/**
 * Dynamically resolve an AT Protocol lexicon at scenario runtime.
 *
 * Uses the sans-IO resolution pipeline from `@garazyk/gruszka` to resolve
 * an NSID through DNS → DID → record fetch.  Scenarios can call this to
 * fetch lexicons on-the-fly rather than shipping pre-bundled copies.
 *
 * @example
 * ```ts
 * import { resolveLexicon } from "@garazyk/hamownia";
 * import { DenoDnsResolver, HttpDidResolver, HttpRecordFetcher }
 *   from "@garazyk/gruszka/lexicon-resolution";
 *
 * const result = await resolveLexicon("app.bsky.feed.post", {
 *   dns: new DenoDnsResolver(),
 *   did: new HttpDidResolver(),
 *   record: new HttpRecordFetcher(),
 * });
 * if (result.ok) {
 *   console.log("Resolved:", result.value.id);
 * }
 * ```
 */
export { resolveLexicon } from "@garazyk/gruszka/lexicon-resolution";
export type { ResolutionPorts } from "@garazyk/gruszka/lexicon-resolution";
