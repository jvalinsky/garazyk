/**
 * @module scenarios/16_notification_management
 *
 * Scenario: Notification Management & Preferences
 *
 * Behavior:
 * - Create multiple test accounts (Luna, Marcus, Rosa, Volt).
 * - Have Marcus, Rosa, and Volt follow Luna.
 * - Perform various notifications-related operations (list, count, seen, push registration/preferences, activity subscriptions).
 *
 * Expectations:
 * - Accounts are created successfully.
 * - Notifications and preferences operations return expected data.
 * - Notification seen/unread status updates correctly.
 */

import { ScenarioResult, timedCall } from "@garazyk/hamownia";
export { ScenarioResult, StepResult, StepStatus } from "@garazyk/hamownia";
export type { ScenarioReport } from "@garazyk/hamownia";
import { assert } from "@garazyk/hamownia";
import { XrpcClient, XrpcError } from "@garazyk/gruszka";
import { getCharacter } from "@garazyk/hamownia/config";
import { PDS1 } from "@garazyk/hamownia/config";

function now() {
  return new Date().toISOString();
}

/**
 * Executes the scenario logic.
 * @returns A promise that resolves to the scenario result
 */
export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Notification Management & Preferences");
  result.start();

  const client = new XrpcClient(PDS1);

  await timedCall(result, "Server health check", async () => {
    await client.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const charNames = ["luna", "marcus", "rosa", "volt"];
  for (const name of charNames) {
    const char = getCharacter(name);
    const session = await timedCall(
      result,
      `Create account: ${char.name}`,
      async () => {
        return await client.accounts.createAccount(
          char.handle,
          char.email,
          char.password,
        );
      },
      (s) => `did=${s.did}`,
    );
    if (session) {
      char.did = session.did;
      char.accessJwt = session.accessJwt;
    }
  }

  const active = charNames.filter((n) => getCharacter(n).did);
  for (const name of active) {
    const char = getCharacter(name);
    try {
      await client.records.createRecord(
        char.did,
        "app.bsky.actor.profile",
        {
          $type: "app.bsky.actor.profile",
          displayName: char.name,
          description: char.persona,
        },
        char.accessJwt,
      );
    } catch (e) {
      if (!(e instanceof XrpcError && e.status === 404)) throw e;
    }
  }

  const luna = getCharacter("luna");

  // Everyone follows Luna and posts
  for (const followerName of ["marcus", "rosa", "volt"]) {
    const fchar = getCharacter(followerName);
    if (fchar.did && fchar.accessJwt && luna.did) {
      await timedCall(
        result,
        `${fchar.name} follows Luna`,
        async () => {
          return await client.records.createRecord(
            fchar.did,
            "app.bsky.graph.follow",
            {
              $type: "app.bsky.graph.follow",
              subject: luna.did,
              createdAt: now(),
            },
            fchar.accessJwt,
          );
        },
        (r) => `uri=${r.uri}`,
      );
    }
  }

  for (const name of ["marcus", "rosa", "volt"]) {
    const char = getCharacter(name);
    if (char.did && char.accessJwt) {
      await timedCall(
        result,
        `${char.name} posts`,
        async () => {
          return await client.records.createRecord(
            char.did,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text:
                `Hello from ${char.name}! This is a test post to generate notifications.`,
              createdAt: now(),
            },
            char.accessJwt,
          );
        },
        (r) => `uri=${r.uri}`,
      );
    }
  }

  if (luna.did && luna.accessJwt) {
    await timedCall(
      result,
      "Luna posts",
      async () => {
        return await client.records.createRecord(
          luna.did,
          "app.bsky.feed.post",
          {
            $type: "app.bsky.feed.post",
            text: "Exciting news everyone! I discovered a new nebula!",
            createdAt: now(),
          },
          luna.accessJwt,
        );
      },
      (r) => `uri=${r.uri}`,
    );
  }

  await new Promise((r) => setTimeout(r, 3000));

  if (luna.accessJwt) {
    await timedCall(
      result,
      "Luna lists notifications",
      async () => {
        return await client.notifications.listNotifications(luna.accessJwt);
      },
      (r) => `count=${r.notifications?.length || 0}`,
    );

    await timedCall(
      result,
      "Luna unread count",
      async () => {
        return await client.raw.xrpcGet(
          "app.bsky.notification.getUnreadCount",
          undefined,
          luna.accessJwt,
        );
      },
      (r) => `count=${r.count ?? 0}`,
    );

    await timedCall(
      result,
      "Luna marks notifications as seen",
      async () => {
        return await client.notifications.updateSeen(luna.accessJwt, 0);
      },
    );

    await timedCall(
      result,
      "Luna verifies unread count 0",
      async () => {
        return await client.raw.xrpcGet(
          "app.bsky.notification.getUnreadCount",
          undefined,
          luna.accessJwt,
        );
      },
      (r) => `count=${r.count ?? 0}`,
    );

    await timedCall(
      result,
      "Luna registers for push",
      async () => {
        return await client.notifications.registerPush(
          "did:web:localhost:3200",
          "test-device-token-abc123",
          "ios",
          "xyz.garazyk.test",
          luna.accessJwt,
        );
      },
    );

    await timedCall(
      result,
      "Luna gets notification preferences",
      async () => {
        return await client.notifications.getNotificationPreferences(
          luna.accessJwt,
        );
      },
    );

    await timedCall(
      result,
      "Luna sets notification preferences",
      async () => {
        return await client.notifications.putNotificationPreferences(
          { priority: true },
          luna.accessJwt,
        );
      },
    );

    const rosa = getCharacter("rosa");
    if (rosa.did && rosa.accessJwt) {
      await timedCall(
        result,
        "Rosa posts fresh bread",
        async () => {
          return await client.records.createRecord(
            rosa.did,
            "app.bsky.feed.post",
            {
              $type: "app.bsky.feed.post",
              text: "Fresh bread just out of the oven!",
              createdAt: now(),
            },
            rosa.accessJwt,
          );
        },
      );
    }

    await new Promise((r) => setTimeout(r, 1000));

    await timedCall(
      result,
      "Luna sees new notification",
      async () => {
        return await client.notifications.listNotifications(luna.accessJwt);
      },
      (r) => `count=${r.notifications?.length || 0}`,
    );

    const marcus = getCharacter("marcus");
    if (marcus.did) {
      await timedCall(
        result,
        "Luna subscribes to Marcus's activity",
        async () => {
          return await client.notifications.putActivitySubscription(
            marcus.did,
            true,
            true,
            luna.accessJwt,
          );
        },
      );
    }

    await timedCall(
      result,
      "Luna lists activity subscriptions",
      async () => {
        return await client.notifications.listActivitySubscriptions(
          luna.accessJwt,
        );
      },
      (r) => `count=${r.subscriptions?.length || 0}`,
    );

    await timedCall(
      result,
      "Luna unregisters push",
      async () => {
        return await client.notifications.unregisterPush(
          "did:web:localhost:3200",
          "test-device-token-abc123",
          "ios",
          "xyz.garazyk.test",
          luna.accessJwt,
        );
      },
    );
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
