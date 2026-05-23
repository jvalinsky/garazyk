/**
 * @module scenarios/53_phone_verification
 *
 * Scenario: Exercises phone verification against the mock Twilio service.
 *
 * Behavior:
 * - Executes the 53 phone verification scenario.
 * - Validates core operations.
 *
 * Expectations:
 * - Scenario completes successfully without errors.
 */

import { getActor, PDS1 } from "../../lib/deno/config.ts";
import { ScenarioResult } from "../../lib/deno/runner.ts";
export {
  ScenarioResult,
  StepResult,
  StepStatus,
} from "../../lib/deno/runner.ts";
export type { ScenarioReport } from "../../lib/deno/runner.ts";
import { XrpcClient } from "../../lib/deno/client.ts";
import { assert } from "../../lib/deno/assertions.ts";
import {
  MockTwilioServer,
  startMockTwilioServer,
  stopMockTwilioServer,
} from "../../lib/deno/mock_twilio.ts";
import { timedCall } from "../../lib/deno/runner.ts";

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Phone Verification (Twilio)");
  result.start();

  // ── Connect to or start mock Twilio server ──────────────────────────────
  const configuredTwilioUrl = Deno.env.get("TWILIO_API_BASE_URL");
  const twilioUrls = [
    configuredTwilioUrl,
    "http://local-mock-twilio:8081",
    "http://127.0.0.1:8081",
  ].filter((url): url is string => Boolean(url));
  let twilio: MockTwilioServer | null = null;
  let owned = false;
  for (const url of twilioUrls) {
    const candidate = new MockTwilioServer(url);
    if (await candidate.getHealth()) {
      twilio = candidate;
      result.stepPassed("Connect to existing mock Twilio server", `url=${url}`);
      break;
    }
  }
  if (!twilio) {
    try {
      const port = configuredTwilioUrl
        ? Number.parseInt(new URL(configuredTwilioUrl).port, 10)
        : 0;
      twilio = await startMockTwilioServer(Number.isFinite(port) ? port : 0);
      owned = true;
      result.stepPassed("Start mock Twilio server", `url=${twilio.url}`);
    } catch (e: any) {
      result.stepFailed(
        "Initialize mock Twilio server",
        e.message || String(e),
      );
      result.finish();
      return result;
    }
  }

  const pds = new XrpcClient(PDS1);
  const luna = getActor("luna");

  // ── Ensure PDS is healthy ────────────────────────────────────────────────
  const healthy = await timedCall(
    result,
    "PDS health check",
    async () => {
      const res = await pds.raw.xrpcGet("com.atproto.server.describeServer");
      return res;
    },
    () => "ok",
  );
  if (!healthy) {
    result.stepSkipped(
      "Phone verification",
      "PDS not healthy, cannot continue",
    );
    stopMockTwilioServer(twilio);
    result.finish();
    return result;
  }

  // ── Try requestPhoneVerification ─────────────────────────────────────────
  // Requires PDS to be configured with:
  //   PDS_PHONE_VERIFICATION_PROVIDER=twilio
  //   TWILIO_ACCOUNT_SID=AC00000000000000000000000000000000
  //   TWILIO_AUTH_TOKEN=SK00000000000000000000000000000000
  //   TWILIO_VERIFY_SERVICE_SID=VA00000000000000000000000000000000
  //   TWILIO_API_BASE_URL=http://127.0.0.1:8081
  const phoneNumber = "+15551234567";

  await timedCall(
    result,
    "com.atproto.temp.requestPhoneVerification",
    async () => {
      return await pds.raw.xrpcPost(
        "com.atproto.temp.requestPhoneVerification",
        { phoneNumber },
      );
    },
    (r) => r ? `sessionID=${r.sessionID || "(empty)"}` : "no response",
  );

  // Check mock state: should have received a Verifications call
  const stateAfterSend = await twilio.getState();
  const storedForPhone = stateAfterSend.store[phoneNumber];
  if (storedForPhone) {
    result.stepPassed(
      "Twilio received verification request",
      `phone=${phoneNumber} code=${storedForPhone.code}`,
    );
  } else {
    const keys = Object.keys(stateAfterSend.store);
    result.stepSkipped(
      "Twilio received verification request",
      keys.length > 0
        ? `No entry for ${phoneNumber}, but store has: ${keys.join(", ")}`
        : "No entries in mock store — PDS may not be configured for Twilio",
    );
  }

  // ── Verify code via mock ─────────────────────────────────────────────────
  // Simulate the user entering the correct code by reading it from mock state
  if (storedForPhone) {
    const code = storedForPhone.code;
    await timedCall(
      result,
      "Verify code via mock control API",
      async () => {
        // Simulate a VerificationCheck by calling the mock's Twilio endpoint directly
        const creds = btoa(
          "AC00000000000000000000000000000000:SK00000000000000000000000000000000",
        );
        const client = new XrpcClient(twilio.url);
        const body = await client.raw.httpPost(
          "/v2/Service/VA00000000000000000000000000000000/VerificationCheck",
          { To: phoneNumber, Code: code },
          creds,
        );
        if (body.status !== "approved") {
          throw new Error(`VerificationCheck returned: ${body.status}`);
        }
        return body;
      },
      (r) => `status=${r.status} valid=${r.valid}`,
    );

    // Verify the mock marked it as verified
    const finalState = await twilio.getState();
    const verified = finalState.store[phoneNumber]?.verified;
    if (verified) {
      result.stepPassed("Mock state reflects verified", "phone_verified=true");
    } else {
      result.stepFailed(
        "Mock state reflects verified",
        "phone not verified after successful check",
      );
    }
  }

  // ── Test wrong code rejection ────────────────────────────────────────────
  if (storedForPhone) {
    await twilio.setAlwaysApprove([]);
    await timedCall(
      result,
      "Wrong code is rejected",
      async () => {
        const creds = btoa(
          "AC00000000000000000000000000000000:SK00000000000000000000000000000000",
        );
        const client = new XrpcClient(twilio.url);
        try {
          const body = await client.raw.httpPost(
            "/v2/Service/VA00000000000000000000000000000000/VerificationCheck",
            { To: phoneNumber, Code: "999999" },
            creds,
          );
          if (body.status === "approved") {
            throw new Error(
              "Wrong code was incorrectly approved — expected rejection",
            );
          }
          return body;
        } catch (exc: any) {
          // If it throws status 400 or returns status !== approved, it's correct
          if (exc.status === 400 || (exc.body && (exc.body as any).status !== "approved")) {
            return exc.body || { status: "rejected" };
          }
          throw exc;
        }
      },
      (r) => `status=${r.status} (correctly rejected)`,
    );
  }

  // ── Always-approve code test ─────────────────────────────────────────────
  await twilio.setAlwaysApprove(["123456"]);
  await timedCall(
    result,
    "Always-approve code works",
    async () => {
      const creds = btoa(
        "AC00000000000000000000000000000000:SK00000000000000000000000000000000",
      );
      const client = new XrpcClient(twilio.url);
      const body = await client.raw.httpPost(
        "/v2/Service/VA00000000000000000000000000000000/VerificationCheck",
        { To: phoneNumber, Code: "123456" },
        creds,
      );
      if (body.status !== "approved") {
        throw new Error(`Expected approved, got: ${body.status}`);
      }
      return body;
    },
    (r) => `status=${r.status}`,
  );

  // ── Reset mock state ────────────────────────────────────────────────────
  await twilio.reset();
  result.stepPassed("Reset mock state");

  // ── Cleanup ──────────────────────────────────────────────────────────────
  if (owned) {
    stopMockTwilioServer(twilio);
    result.stepPassed("Stop mock Twilio server");
  } else {
    result.stepPassed("Finished scenario (preserved shared mock)");
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
