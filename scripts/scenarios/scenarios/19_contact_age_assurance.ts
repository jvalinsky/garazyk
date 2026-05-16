/**
 * @module scenarios/19_contact_age_assurance
 *
 * Scenario: Contact Management & Age Assurance
 *
 * Behavior:
 * - Initialize test accounts.
 * - Perform phone verification and contact import flow for one user.
 * - Retrieve age assurance configuration and trigger age assurance flow for another user.
 *
 * Expectations:
 * - Phone verification and contact management operations succeed.
 * - Age assurance configuration and state endpoints return expected responses.
 */

import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";
export { ScenarioResult, StepResult, StepStatus } from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { assert } from "../../lib/deno/assertions.ts";
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Contact Management & Age Assurance");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result, `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(char.handle, char.email, char.password);
      },
      (s) => `did=${s.did}`
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const luna = getCharacter("luna");
  const marcus = getCharacter("marcus");

  if (luna.accessJwt) {
    try {
      await timedCall(
        result, "Luna starts phone verification",
        async () => {
          return await client.contact.startPhoneVerification("+15551234567", luna.accessJwt);
        },
        (r) => `verificationId=${r.verificationId || ""}`
      );

      await timedCall(
        result, "Luna verifies phone code",
        async () => {
          return await client.contact.verifyPhone("+15551234567", "123456", luna.accessJwt);
        },
        (r) => `got_token=${!!r.token}`
      );

      await timedCall(
        result, "Luna imports contacts",
        async () => {
          return await client.contact.importContacts(
            ["+15551111111", "+15552222222", "+15553333333"],
            "test-import-token", luna.accessJwt
          );
        },
        (r) => `matches=${r.matches?.length || 0}`
      );

      await timedCall(
        result, "Luna gets contact matches",
        async () => {
          return await client.contact.getContactMatches(luna.accessJwt);
        },
        (r) => `matches=${(Array.isArray(r) ? r : r.matches)?.length || 0}`
      );

      await timedCall(
        result, "Luna gets sync status",
        async () => {
          return await client.contact.getContactSyncStatus(luna.accessJwt);
        }
      );

      await timedCall(
        result, "Luna removes contact data",
        async () => {
          return await client.contact.removeContactData(luna.accessJwt);
        }
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
  }

  try {
    await timedCall(
      result, "Get age assurance config",
      async () => {
        return await client.ageAssurance.getAgeAssuranceConfig();
      }
    );

    if (marcus.accessJwt) {
      await timedCall(
        result, "Marcus begins age assurance",
        async () => {
          return await client.ageAssurance.beginAgeAssurance(
            marcus.email, "en", "US", { regionCode: "CA", token: marcus.accessJwt }
          );
        }
      );

      await timedCall(
        result, "Marcus age assurance state",
        async () => {
          return await client.ageAssurance.getAgeAssuranceState("US", { regionCode: "CA", token: marcus.accessJwt });
        }
      );
    }
  } catch (e) {
    if (!(e instanceof XrpcError && e.status === 404)) throw e;
  }

  result.finish();
  return result;
}

if (import.meta.main) {
  run().then(res => {
    console.log(res.summary());
    Deno.exit(res.ok ? 0 : 1);
  });
}
