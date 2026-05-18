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

import type { ScenarioContext } from "@garazyk/hamownia";
import { createScenarioContext } from "@garazyk/hamownia";
import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient } from "@garazyk/gruszka";
/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(ctx: ScenarioContext): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account Migration & PLC Audit");
  result.start();

  const pds1 = new XrpcClient(ctx.pds1);
  const pds2 = new XrpcClient(ctx.pds2);
  const luna = ctx.getCharacter("luna");
  const admin = ctx.getCharacter("admin");

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
      const res = await fetch(`${ctx.serviceUrls.plc}/_health`);
      if (res.status !== 200) throw new Error(`PLC status=${res.status}`);
    },
  );

  await timedCall(
    result,
    "Create admin account on PDS1",
    async () => {
      const res = await pds1.accounts.createAccount(
        admin.handle,
        admin.email,
        admin.password,
      );
      admin.did = res.did;
      return res;
    },
    (s: any) => `did=${s.did}`,
  );

  const session = await timedCall(
    result,
    "Create user account on PDS1",
    async () => {
      const res = await pds1.accounts.createAccount(
        luna.handle,
        luna.email,
        luna.password,
      );
      return res;
    },
    (s: any) => `did=${s.did}`,
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
        return await pds1.raw.xrpcPost(
          "com.atproto.identity.requestPlcOperationSignature",
          {},
          luna.accessJwt,
        );
      },
    );
    const token = tokenResp?.data?.token;

    if (token) {
      const signResp1 = await timedCall(
        result,
        `Sign handle rotation: ${newHandle1}`,
        async () => {
          return await pds1.raw.xrpcPost(
            "com.atproto.identity.signPlcOperation",
            {
              token,
              alsoKnownAs: [`at://${newHandle1}`],
            },
            luna.accessJwt,
          );
        },
      );

      if (signResp1) {
        const op1 = { ...signResp1.data.operation };
        delete op1.did;
        const plcRes = await fetch(`${ctx.serviceUrls.plc}/${luna.did}`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(op1),
        });
        if (plcRes.status === 200) {
          result.stepPassed(
            "First handle rotation (Direct PLC)",
            `handle=${newHandle1}`,
          );
        } else {
          result.stepFailed(
            "First handle rotation (Direct PLC)",
            `status=${plcRes.status} body=${await plcRes.text()}`,
          );
        }
      }
      await new Promise((r) => setTimeout(r, 1000));

      const tokenResp2 = await timedCall(
        result,
        "Request PLC signature (2nd)",
        async () => {
          return await pds1.raw.xrpcPost(
            "com.atproto.identity.requestPlcOperationSignature",
            {},
            luna.accessJwt,
          );
        },
      );
      const token2 = tokenResp2?.data?.token;

      if (token2) {
        const signResp2 = await timedCall(
          result,
          `Sign handle rotation: ${newHandle2}`,
          async () => {
            return await pds1.raw.xrpcPost(
              "com.atproto.identity.signPlcOperation",
              {
                token: token2,
                alsoKnownAs: [`at://${newHandle2}`],
              },
              luna.accessJwt,
            );
          },
        );

        if (signResp2) {
          const op2 = { ...signResp2.data.operation };
          delete op2.did;
          const plcRes2 = await fetch(`${ctx.serviceUrls.plc}/${luna.did}`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(op2),
          });
          if (plcRes2.status === 200) {
            result.stepPassed(
              "Second handle rotation (Direct PLC)",
              `handle=${newHandle2}`,
            );
          } else {
            result.stepFailed(
              "Second handle rotation (Direct PLC)",
              `status=${plcRes2.status} body=${await plcRes2.text()}`,
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
    const logResp = await fetch(`${ctx.serviceUrls.plc}/${luna.did}/log`);
    if (logResp.status === 200) {
      const operations = await logResp.json();
      result.stepPassed(
        "Fetch PLC operation log",
        `total_operations=${operations.length}`,
      );

      if (operations.length === 0) {
        result.stepFailed("PLC log audit", "Log is empty");
      } else {
        let isValid = true;
        let failureReason = "";

        const genesis = operations[0];
        if (genesis.prev !== null && genesis.prev !== undefined) {
          isValid = false;
          failureReason = "Genesis operation has a 'prev' CID";
        }

        let lastCid = genesis.cid;
        for (let i = 1; i < operations.length; i++) {
          const op = operations[i];
          const opData = op.operation || op;
          if (opData.prev !== lastCid) {
            isValid = false;
            failureReason =
              `Chain broken at index ${i}: expected prev=${lastCid}, got ${opData.prev}`;
            break;
          }
          lastCid = op.cid || opData.cid;
        }

        if (isValid) {
          result.stepPassed(
            "PLC operation chain audit",
            "Chain is intact and monotonic",
          );
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
    } else {
      result.stepFailed("Fetch PLC operation log", `status=${logResp.status}`);
    }
  } catch (exc: any) {
    result.stepFailed("Fetch PLC operation log", exc.message || String(exc));
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run(createScenarioContext()).then((res) => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
