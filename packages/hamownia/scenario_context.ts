/**
 * Scenario execution context — the injected dependency for scenario `run()`.
 *
 * A `ScenarioContext` combines the resolved service configuration
 * ({@link ScenarioConfig}) with a character registry
 * ({@link CharacterRegistry}), so scenarios receive everything they need
 * through a single parameter instead of reading module-level mutable state.
 *
 * @module scenario_context
 */

import {
  createCharacterRegistry,
  createScenarioConfig,
} from "./config.ts";
import type { CharacterRegistry } from "./config.ts";
import type { ScenarioConfig } from "./config.ts";

/**
 * Injected context for a single scenario execution.
 *
 * Scenarios that have migrated to the context-injection pattern receive
 * this as the first argument to their `run()` function:
 *
 * ```ts
 * export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
 *   const pds = new XrpcClient(ctx.pds1);
 *   const luna = ctx.getCharacter("luna");
 * }
 * ```
 */
export type ScenarioContext = ScenarioConfig & CharacterRegistry;

/**
 * Create a scenario context from a scenario config.
 *
 * Builds a fresh character registry scoped to the config's PDS URLs and
 * returns the composite context object.
 *
 * @param config - Explicit scenario config (defaults to env-derived config)
 * @returns A scenario context ready to pass to a scenario's `run()`
 */
export function createScenarioContext(
  config: ScenarioConfig = createScenarioConfig(),
): ScenarioContext {
  const registry = createCharacterRegistry(config);
  return { ...config, ...registry };
}
