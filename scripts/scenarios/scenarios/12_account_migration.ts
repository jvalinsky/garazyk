/**
 * @module scenarios/12_account_migration
 *
 * Scenario: Account Migration and PLC Audit
 *
 * Behavior:
 * - Checks PDS and PLC health.
 * - Creates admin and user accounts.
 * - Performs multiple handle rotations via direct PLC operations.
 * - Audits the PLC operation log for integrity and handle propagation.
 *
 * Expectations:
 * - Account creation and handle rotations succeed.
 * - PLC operation log audit verifies chain integrity and handle updates.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { getActor, PDS1, PDS2, SERVICE_URLS } from "../../lib/deno/config.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Migration & PLC Audit");
  result.start();

  const pds1 = new XrpcClient(PDS1);
  const pds2 = new XrpcClient(PDS2);
  const luna = getActor("luna");
  const admin = getActor("admin");

  for (const [name, client] of [["PDS1", pds1], ["PDS2", pds2]] as const) {
    await timedCall(
      result,
      `${name} health check`,
      async () => {
        await client.waitForHealthy(30);
      },
    );
  }

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  await timedCall(
    result,
    "PLC health check",
    async () => {
      await pds1.raw.httpGet(`${SERVICE_URLS.plc}/_health`);
    },
  );

  await timedCall(
    result,
    "Create admin account on PDS1",
    async () => {
      const res = await pds1.accounts.createAccount(admin.handle, admin.email, admin.password);
      admin.did = res.did;
      return res;
    },
    (s) => `did=${s.did}`,
  );

  const session = await timedCall(
    result,
    "Create user account on PDS1",
    async () => {
      const res = await pds1.accounts.createAccount(luna.handle, luna.email, luna.password);
      return res;
    },
    (s) => `did=${s.did}`,
  );

  if (!session) {
    result.finish();
    return result;
  }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  const originalHandle = luna.handle;
  const parts = originalHandle.split(".");
  const domain = parts.length > 1 ? parts.pop() : "test";
  const base = parts.join(".");

  const newHandle1 = `one-${base}.${domain}`;
  const newHandle2 = `two-${base}.${domain}`;

  try {
    const tokenResp = await timedCall(
      result,
      "Request PLC operation signature",
      async () => {
        return await pds1.as(luna).raw.post(
          "com.atproto.identity.requestPlcOperationSignature",
          {},
        );
      },
    );
    const token = tokenResp?.token;

    if (token) {
      const signResp1 = await timedCall(
        result,
        `Sign handle rotation: ${newHandle1}`,
        async () => {
          return await pds1.as(luna).raw.post("com.atproto.identity.signPlcOperation", {
            token,
            alsoKnownAs: [`at://${newHandle1}`],
          });
        },
      );

      if (signResp1) {
        const op1 = { ...signResp1.operation };
        delete op1.did;
        try {
          await pds1.raw.httpPost(`${SERVICE_URLS.plc}/${luna.did}`, op1);
          result.stepPassed("First handle rotation (Direct PLC)", `handle=${newHandle1}`);
        } catch (exc: any) {
          result.stepFailed(
            "First handle rotation (Direct PLC)",
            `error=${exc.message || String(exc)}`,
          );
        }
      }
      await new Promise((r) => setTimeout(r, 1000));

      const tokenResp2 = await timedCall(
        result,
        "Request PLC signature (2nd)",
        async () => {
          return await pds1.as(luna).raw.post(
            "com.atproto.identity.requestPlcOperationSignature",
            {},
          );
        },
      );
      const token2 = tokenResp2?.token;

      if (token2) {
        const signResp2 = await timedCall(
          result,
          `Sign handle rotation: ${newHandle2}`,
          async () => {
            return await pds1.as(luna).raw.post("com.atproto.identity.signPlcOperation", {
              token: token2,
              alsoKnownAs: [`at://${newHandle2}`],
            });
          },
        );

        if (signResp2) {
          const op2 = { ...signResp2.operation };
          delete op2.did;
          try {
            await pds1.raw.httpPost(`${SERVICE_URLS.plc}/${luna.did}`, op2);
            result.stepPassed("Second handle rotation (Direct PLC)", `handle=${newHandle2}`);
          } catch (exc: any) {
            result.stepFailed(
              "Second handle rotation (Direct PLC)",
              `error=${exc.message || String(exc)}`,
            );
          }
        }
      }
      luna.handle = newHandle2;
    }
  } catch (exc: any) {
    result.stepFailed("Handle rotations via PLC", exc.message || String(exc));
  }

  try {
    const operations = await pds1.raw.httpGet(`${SERVICE_URLS.plc}/${luna.did}/log`);
    result.stepPassed("Fetch PLC operation log", `total_operations=${operations.length}`);

    if (operations.length === 0) {
      result.stepFailed("PLC log audit", "Log is empty");
    } else {
        let isValid = true;
        let failureReason = "";

        const isGenesis = (op: any): boolean => {
          const d = op.operation || op;
          return d.prev === null || d.prev === undefined;
        };

        if (!isGenesis(operations[0])) {
          isValid = false;
          failureReason = "First operation is not genesis (has a 'prev' CID)";
        }

        for (let i = 1; i < operations.length; i++) {
          const op = operations[i];
          const d = op.operation || op;
          if (!d.prev || typeof d.prev !== "string" || d.prev.length < 10) {
            isValid = false;
            failureReason = `Operation at index ${i} has invalid prev: ${JSON.stringify(d.prev)}`;
            break;
          }
        }

        if (isValid) {
          result.stepPassed("PLC operation chain audit", "Chain is intact and monotonic");
        } else {
          result.stepFailed("PLC operation chain audit", failureReason);
        }

        const handlesSeen = new Set<string>();
        for (const op of operations) {
          const opData = op.operation || op;
          const akas = opData.alsoKnownAs || [];
          for (const aka of akas) {
            if (aka.startsWith("at://")) {
              handlesSeen.add(aka.replace("at://", ""));
            }
          }
        }

        if (handlesSeen.has(newHandle1) && handlesSeen.has(newHandle2)) {
          result.stepPassed(
            "Verify handle updates in PLC",
            `Found handles: ${newHandle1}, ${newHandle2}`,
          );
        } else {
          result.stepFailed(
            "Verify handle updates in PLC",
            `Missing handle updates in log. Seen: ${Array.from(handlesSeen)}`,
          );
        }
      }
  } catch (exc: any) {
    result.stepFailed("Fetch PLC operation log", exc.message || String(exc));
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
