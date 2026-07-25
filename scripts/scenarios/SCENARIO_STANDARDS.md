# Scenario Standards

Scenario files live in `scripts/scenarios/scenarios/`.

Each file should:

1. Start with a module comment that names the behavior and expected result.
2. Export `run(): Promise<ScenarioResult>`.
3. Use the shared assertion helpers.
4. Wrap major network operations with `timedCall`.
5. Import shared clients and configuration from `scripts/lib/deno/`.

```ts
/**
 * @module scenarios/example
 *
 * Checks that a created record can be read from the PDS.
 */

import { ScenarioResult } from "../../lib/deno/runner.ts";

/**
 * Runs the scenario.
 */
export async function run(): Promise<ScenarioResult> {
  // ...
}
```

Use a two-digit filename prefix. Add manifest requirements in
`packages/hamownia/scenario_metadata.ts` when the scenario depends on a specific
role, capability, second PDS, browser flow, or timeout.
