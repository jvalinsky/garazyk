#!/bin/bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# scaffold-scenario.sh — Generate boilerplate for a new scenario.
#
# Usage: scaffold-scenario.sh <number> <name>
# Example: scaffold-scenario.sh 59 labeler_lifecycle
#
# Creates:
#   scripts/scenarios/scenarios/NN_name.ts
#
# Does NOT modify run_scenarios.ts (add to NEEDS_PDS2 manually if needed).

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <number> <name>"
    echo "Example: $0 59 labeler_lifecycle"
    echo ""
    echo "Number: zero-padded scenario number (e.g., 59)"
    echo "Name:   snake_case descriptive name (e.g., labeler_lifecycle)"
    exit 1
fi

NUMBER="$1"
NAME="$2"
SCENARIO_DIR="$(cd "$(dirname "$0")/../../.." && pwd)/scripts/scenarios/scenarios"

# Zero-pad to 2 digits
NUMBER_PADDED="$(printf '%02d' "$NUMBER")"

# Derive display name from snake_case
DISPLAY_NAME="$(echo "$NAME" | sed 's/_/ /g')"
# Capitalize first letter of each word
DISPLAY_TITLE="$(echo "$DISPLAY_NAME" | sed 's/\b\(.\)/\u\1/g')"

SCENARIO_FILE="${SCENARIO_DIR}/${NUMBER_PADDED}_${NAME}.ts"

if [[ -f "$SCENARIO_FILE" ]]; then
    echo "Error: Scenario file already exists: $SCENARIO_FILE"
    exit 1
fi

cat > "$SCENARIO_FILE" <<SCENARIO_EOF
import { XrpcClient } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("${DISPLAY_TITLE}");
  result.start();

  const client = new XrpcClient(PDS1);

  // ── Health check ────────────────────────────────────────────────────────

  await timedCall(
    result, "Server health check",
    async () => {
      const res = await fetch(\`\${PDS1}/xrpc/com.atproto.server.describeServer\`);
      if (!res.ok) throw new Error("Server not healthy");
    }
  );

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  // ── Create accounts ──────────────────────────────────────────────────────

  const luna = getCharacter("luna");
  const session = await timedCall(
    result, \`Create account: \${luna.name}\`,
    async () => {
      try {
        const res = await client.agent.createAccount({
          handle: luna.handle,
          email: luna.email,
          password: luna.password,
        });
        return res.data;
      } catch (e: any) {
        if (e.message?.includes("already exists")) {
          const res = await client.agent.login({
            identifier: luna.handle,
            password: luna.password,
          });
          return res.data;
        }
        throw e;
      }
    },
    (s) => \`did=\${s.did}\`
  );
  if (session) {
    luna.did = session.did;
    luna.accessJwt = session.accessJwt;
  }

  // ── Test steps ──────────────────────────────────────────────────────────

  // TODO: Add your test steps here using timedCall
  // Example:
  // await timedCall(
  //   result, "Create a post",
  //   async () => {
  //     return await client.raw.post("com.atproto.repo.createRecord", {
  //       repo: luna.did,
  //       collection: "app.bsky.feed.post",
  //       record: {
  //         \$type: "app.bsky.feed.post",
  //         text: "Hello from scenario ${NUMBER_PADDED}!",
  //         createdAt: now(),
  //       },
  //     }, luna.accessJwt);
  //   }
  // );

  // ── Finish ───────────────────────────────────────────────────────────────

  result.finish();
  return result;
}

// ── Standalone execution ────────────────────────────────────────────────────

if (import.meta.main) {
  const result = await run();
  console.log(result.summary());
  Deno.exit(result.ok ? 0 : 1);
}
SCENARIO_EOF

echo "Created: ${SCENARIO_FILE}"
echo ""
echo "Next steps:"
echo "  1. Edit the scenario file and add your test steps"
echo "  2. If the scenario needs PDS2, add '${NUMBER_PADDED}' to NEEDS_PDS2 in scripts/run_scenarios.ts"
echo "  3. Run the scenario:"
echo "     ./scripts/run_scenarios.ts --binary ${NUMBER_PADDED}"
echo "  4. Or run standalone:"
echo "     deno run -A ${SCENARIO_FILE}"
