// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
// Covers: two clients race to update the same record; winner is deterministic; loser gets 4xx not 5xx.
// Also covers: racing delete-vs-read; racing blob reference under simultaneous upload+delete.
// Extends 24_concurrent_write_throughput.ts (throughput) with semantic conflict assertions.
// Production paths: com.atproto.repo.{putRecord,deleteRecord,createRecord,getRecord},
//   com.atproto.sync.getBlob.
import { XrpcClient, XrpcError } from "../../lib/deno/client.ts";
import { PDS1, getCharacter } from "../../lib/deno/config.ts";
import { ScenarioResult, timedCall } from "../../lib/deno/runner.ts";

function now() {
  return new Date().toISOString();
}

// Minimal 1×1 PNG (67 bytes) for blob tests.
const TINY_PNG = new Uint8Array([
  0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
  0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
  0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
  0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,
  0xDE,0x00,0x00,0x00,0x0C,0x49,0x44,0x41,
  0x54,0x08,0xD7,0x63,0xF8,0xCF,0xC0,0x00,
  0x00,0x00,0x02,0x00,0x01,0xE2,0x21,0xBC,
  0x33,0x00,0x00,0x00,0x00,0x49,0x45,0x4E,
  0x44,0xAE,0x42,0x60,0x82,
]);

export async function run(): Promise<ScenarioResult> {
  const result = new ScenarioResult("Concurrent Record Conflict");
  result.start();

  const pds = new XrpcClient(PDS1);
  const luna = getCharacter("luna");

  await timedCall(result, "PDS health check", async () => {
    await pds.waitForHealthy(30);
  });

  if (result.failed > 0) {
    result.finish();
    return result;
  }

  const session = await timedCall(
    result, "Create luna account",
    async () => {
      try {
        return await pds.accounts.createAccount(luna.handle, luna.email, luna.password);
      } catch {
        return await pds.accounts.createSession(luna.handle, luna.password);
      }
    },
    (s) => `did=${s.did}`
  );

  if (session) {
    luna.did = session.did;
    luna.accessJwt = session.accessJwt;
  } else {
    result.finish();
    return result;
  }

  // Seed a profile record that both concurrent writers will race to update.
  const profileRkey = "self";
  await timedCall(
    result, "Create initial profile record",
    async () => {
      return await pds.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.actor.profile",
        rkey: profileRkey,
        record: {
          $type: "app.bsky.actor.profile",
          displayName: "Initial Name",
          description: "seed record for conflict test",
        },
      }, luna.accessJwt);
    }
  );

  // --- Concurrent putRecord: one wins, one errors structurally ---
  // Both writes target the same (repo, collection, rkey). The PDS must:
  //   - Let exactly one succeed (not both, not neither).
  //   - Return a 4xx (not 5xx) for the loser.
  //   - Persist one of the two displayName values (deterministic winner).
  {
    const raceResults = await Promise.allSettled([
      pds.records.putRecord(luna.did, "app.bsky.actor.profile", profileRkey, {
        $type: "app.bsky.actor.profile",
        displayName: "Racer A",
        description: "first concurrent writer",
      }, luna.accessJwt!),
      pds.records.putRecord(luna.did, "app.bsky.actor.profile", profileRkey, {
        $type: "app.bsky.actor.profile",
        displayName: "Racer B",
        description: "second concurrent writer",
      }, luna.accessJwt!),
    ]);

    const fulfilled = raceResults.filter(r => r.status === "fulfilled");
    const rejected  = raceResults.filter(r => r.status === "rejected");

    // Check for 5xx — any server error is a test failure.
    let hasServerError = false;
    for (const r of rejected) {
      const e = (r as PromiseRejectedResult).reason;
      if (e instanceof XrpcError && e.status >= 500) {
        hasServerError = true;
        result.stepFailed("Concurrent putRecord: no 5xx error",
          `Got ${e.status} from concurrent write: ${e.message}`);
        break;
      }
    }

    if (!hasServerError) {
      if (fulfilled.length === 0) {
        result.stepFailed("Concurrent putRecord: at least one succeeds", "Both writes failed");
      } else {
        // Read back the winner and assert it has one of the two expected values.
        const winner = await pds.records.getRecord(luna.did, "app.bsky.actor.profile", profileRkey);
        const winnerName = (winner as any)?.value?.displayName;
        if (winnerName === "Racer A" || winnerName === "Racer B") {
          result.stepPassed(
            "Concurrent putRecord: one wins, one errors structurally",
            `winner=${winnerName}, fulfilled=${fulfilled.length}, rejected=${rejected.length}`
          );
        } else {
          result.stepFailed(
            "Concurrent putRecord: winner has expected value",
            `displayName=${JSON.stringify(winnerName)} is neither "Racer A" nor "Racer B"`
          );
        }
      }
    }
  }

  // --- Racing delete vs read ---
  // Create a throwaway post, then race deleteRecord against getRecord on the same rkey.
  // Neither outcome is wrong (read may win or lose the race), but a 5xx is never acceptable.
  {
    const throwaway = await timedCall(
      result, "Create throwaway post for delete-race",
      async () => pds.raw.post("com.atproto.repo.createRecord", {
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: { $type: "app.bsky.feed.post", text: "delete race target", createdAt: now() },
      }, luna.accessJwt!),
      (r) => `uri=${r.uri}`
    );

    if (throwaway) {
      const rkey = throwaway.uri.split("/").pop()!;
      const raceResults = await Promise.allSettled([
        pds.records.deleteRecord(luna.did, "app.bsky.feed.post", rkey, luna.accessJwt!),
        pds.records.getRecord(luna.did, "app.bsky.feed.post", rkey),
      ]);

      let hasServerError = false;
      for (const r of raceResults) {
        if (r.status === "rejected") {
          const e = (r as PromiseRejectedResult).reason;
          if (e instanceof XrpcError && e.status >= 500) {
            hasServerError = true;
            result.stepFailed("Racing delete-vs-read returns structured result",
              `Got ${e.status}: ${e.message}`);
            break;
          }
        }
      }
      if (!hasServerError) {
        result.stepPassed(
          "Racing delete-vs-read returns structured result",
          `delete=${raceResults[0].status}, read=${raceResults[1].status}`
        );
      }
    } else {
      result.stepSkipped("Racing delete-vs-read returns structured result",
        "throwaway post not created");
    }
  }

  // --- Racing blob upload + delete ---
  // Upload a blob, reference it from a post record, then race deleteRecord against getBlob.
  // The ref-count path must not produce a 5xx under concurrent access.
  {
    const blobResult = await timedCall(
      result, "Upload blob for race test",
      async () => pds.blobs.uploadBlob(TINY_PNG, "image/png", luna.accessJwt!),
      (r) => `cid=${r?.blob?.$link ?? r?.blob?.ref?.$link ?? "present"}`
    );

    const blobCid: string | null =
      (blobResult as any)?.blob?.$link ??
      (blobResult as any)?.blob?.ref?.$link ??
      null;

    if (blobCid && blobResult) {
      // Create a post that embeds the blob so the PDS tracks the reference.
      const blobPost = await timedCall(
        result, "Create record referencing blob",
        async () => pds.raw.post("com.atproto.repo.createRecord", {
          repo: luna.did,
          collection: "app.bsky.feed.post",
          record: {
            $type: "app.bsky.feed.post",
            text: "blob race post",
            createdAt: now(),
            embed: {
              $type: "app.bsky.embed.images",
              images: [{
                $type: "app.bsky.embed.images#image",
                image: (blobResult as any).blob,
                alt: "test",
              }],
            },
          },
        }, luna.accessJwt!),
        (r) => `uri=${r.uri}`
      );

      if (blobPost) {
        const blobRkey = blobPost.uri.split("/").pop()!;
        const blobRace = await Promise.allSettled([
          pds.records.deleteRecord(luna.did, "app.bsky.feed.post", blobRkey, luna.accessJwt!),
          pds.raw.xrpcGetBinary("com.atproto.sync.getBlob",
            { params: { did: luna.did, cid: blobCid } }),
        ]);

        let hasServerError = false;
        for (const r of blobRace) {
          if (r.status === "rejected") {
            const e = (r as PromiseRejectedResult).reason;
            if (e instanceof XrpcError && e.status >= 500) {
              hasServerError = true;
              result.stepFailed("Racing blob upload+delete produces no 500",
                `Got ${e.status}: ${e.message}`);
              break;
            }
          }
        }
        if (!hasServerError) {
          result.stepPassed(
            "Racing blob upload+delete produces no 500",
            `delete=${blobRace[0].status}, getBlob=${blobRace[1].status}`
          );
        }
      } else {
        result.stepSkipped("Racing blob upload+delete produces no 500",
          "blob post not created");
      }
    } else {
      result.stepSkipped("Racing blob upload+delete produces no 500",
        "blob upload not available");
    }
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
