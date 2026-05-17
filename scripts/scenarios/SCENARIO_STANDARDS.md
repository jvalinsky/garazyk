# Scenario Documentation Standards

All scenarios in `scripts/scenarios/scenarios/*.ts` must follow this documentation template to
ensure clarity for developers and automated consistency.

## Required Structure

Each scenario file must start with a module header and a single JSDoc block for the `run` function.

### Example Template

```typescript
/**
 * @module scenarios/<name>
 *
 * Scenario: <Brief description of what is being tested>
 *
 * Behavior:
 * - <Describe step 1>
 * - <Describe step 2>
 *
 * Expectations:
 * - <Describe successful outcome>
 */

import { ScenarioResult } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  // ...
}
```

## Implementation Checklist

1. **Module Header:** Top-level comment block with `@module`, a brief scenario description, the
   behavioral steps, and expectations.
2. **Function Documentation:** Exactly one JSDoc block immediately before the exported `run`
   function.
3. **Assertions:** Use the `assert` helper from `../../lib/deno/assertions.ts` for all test checks.
4. **Timed Calls:** All major operations must be wrapped in `timedCall` for performance tracking.
5. **Imports:** Ensure relative imports are consistent with `scripts/lib/deno/` libraries.
6. **Return Type:** Use `Promise<ScenarioResult>` for `run`; do not use `Promise<any>`.
