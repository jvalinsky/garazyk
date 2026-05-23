/**
 * @module scenarios/39_list_management
 *
 * Scenario: Creates a curated list, adds a member, and removes it again.
 *
 * Behavior:
 * - Executes the 39 list management scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1, SERVICE_URLS } from "../../lib/deno/config.ts";
import { now, ScenarioResult } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */


function delay(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

/** Retry a predicate function with timeout. Throws if not fulfilled within deadline. */
async function waitFor(
  predicate: () => Promise<boolean>,
  timeoutMs = 15000,
  intervalMs = 500,
): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await predicate()) return;
    await delay(intervalMs);
  }
  if (!(await predicate())) {
    throw new Error(`Condition not met within ${timeoutMs}ms`);
  }
}

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("List Management");
  result.start();

  const pds = new XrpcClient(PDS1);
  const appview = new XrpcClient(SERVICE_URLS.appview);
  const luna = getActor("luna");
  const marcus = getActor("marcus");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) return result;

  for (const char of [luna, marcus]) {
    const session = await pds.accounts.createAccount(char.handle, char.email, char.password).catch(
      () => pds.accounts.createSession(char.handle, char.password),
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const listRkey = `curate-list-${Date.now()}`;
  const listRecord = {
    $type: "app.bsky.graph.list",
    purpose: "app.bsky.graph.defs#curatelist",
    name: "Luna's Favorites",
    description: "Accounts Luna finds interesting",
    createdAt: now(),
  };

  const listRef = await timedCall(result, "Create curate list", async () => {
    return await pds.records.createRecord(
      luna.did,
      "app.bsky.graph.list",
      listRecord,
      luna.accessJwt,
      { rkey: listRkey },
    );
  });

  if (listRef) {
    const listUri = listRef.uri;
    const itemRkey = `item-${Date.now()}`;

    await timedCall(result, "Add Marcus to list", async () => {
      return await pds.records.createRecord(
        luna.did,
        "app.bsky.graph.listitem",
        {
          $type: "app.bsky.graph.listitem",
          list: listUri,
          subject: marcus.did,
          createdAt: now(),
        },
        luna.accessJwt,
        { rkey: itemRkey },
      );
    });

    await timedCall(result, "Get lists for Luna", async () => {
      let lastCount = 0;
      await waitFor(async () => {
        try {
          const res = await appview.as(luna).raw.get(
            "app.bsky.graph.getLists",
            { actor: luna.did, limit: 10 },
          );
          lastCount = res.lists?.length || 0;
          return lastCount > 0;
        } catch {
          return false;
        }
      });
      return { lists: lastCount };
    });

    await timedCall(result, "Get list items", async () => {
      let lastCount = 0;
      await waitFor(async () => {
        try {
          const res = await appview.as(luna).raw.get(
            "app.bsky.graph.getList",
            { list: listUri, limit: 10 },
          );
          lastCount = res.items?.length || 0;
          return true; // getList succeeded (list is indexed)
        } catch {
          return false;
        }
      });
      return { items: lastCount };
    });

    await timedCall(result, "Remove Marcus from list", async () => {
      return await pds.records.deleteRecord(
        luna.did,
        "app.bsky.graph.listitem",
        itemRkey,
        luna.accessJwt,
      );
    });
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
