#!/usr/bin/env -S deno run -A
import { XrpcClient } from "@garazyk/gruszka";
import { nowIso, waitForServer } from "@garazyk/gruszka/seed";

const baseUrl = (Deno.env.get("PDS_URL") || "http://localhost:2583").replace(/\/$/, "");

function envBool(key: string, defaultValue: boolean): boolean {
  const raw = Deno.env.get(key);
  if (raw === undefined) return defaultValue;
  return ["1", "true", "yes", "y", "on"].includes(raw.trim().toLowerCase());
}

function envInt(key: string, defaultValue: number): number {
  const raw = Deno.env.get(key);
  if (raw === undefined || raw.trim() === "") return defaultValue;
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) throw new Error(`${key} must be an integer (got ${raw})`);
  return parsed;
}

function normalizeDomain(domain: string): string {
  const normalized = domain.trim().replace(/^\.+|\.+$/g, "");
  if (!normalized) throw new Error("DEMO_HANDLE_DOMAIN must not be empty");
  return normalized;
}

function randomSuffix(): string {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return String(1000 + (value[0] % 9000));
}

async function main() {
  const seedMode = (Deno.env.get("DEMO_SEED_MODE") || "create").trim().toLowerCase();
  if (!["create", "login"].includes(seedMode)) {
    throw new Error("DEMO_SEED_MODE must be 'create' or 'login'");
  }
  const handleDomain = normalizeDomain(Deno.env.get("DEMO_HANDLE_DOMAIN") || "test");
  const emailDomain = (Deno.env.get("DEMO_EMAIL_DOMAIN") || "test.invalid").trim().replace(
    /^@/,
    "",
  );
  const suffix = (Deno.env.get("DEMO_SUFFIX") || "").trim() || randomSuffix();
  const password = (Deno.env.get("DEMO_PASSWORD") || "").trim() || `hunter${suffix}`;
  const prefixes = (Deno.env.get("DEMO_ACCOUNT_PREFIXES") || "alice,bob")
    .split(",")
    .map((prefix) => prefix.trim())
    .filter(Boolean);
  const postsPerAccount = Math.max(0, envInt("DEMO_POSTS_PER_ACCOUNT", 3));
  const createProfiles = envBool("DEMO_CREATE_PROFILES", true);
  if (prefixes.length === 0) {
    throw new Error("DEMO_ACCOUNT_PREFIXES must include at least one prefix");
  }

  console.log(`Waiting for server at ${baseUrl} ...`);
  await waitForServer(baseUrl, 30);
  console.log("Server is up!");

  console.log("Demo config:");
  console.log(`  mode=${seedMode}`);
  console.log(`  suffix=${suffix}`);
  console.log(`  handle_domain=${handleDomain}`);
  console.log(`  prefixes=${prefixes.join(",")}`);
  console.log(`  posts_per_account=${postsPerAccount}`);
  console.log(`  create_profiles=${createProfiles}`);

  const client = new XrpcClient(baseUrl);
  const now = nowIso();
  const sessions: Array<Record<string, string>> = [];

  for (const prefix of prefixes) {
    const handle = `${prefix}${suffix}.${handleDomain}`;
    const email = `${prefix}${suffix}@${emailDomain}`;
    if (seedMode === "create") {
      console.log(`Creating account ${handle} (this may write to the configured PLC directory)...`);
      sessions.push(await client.accounts.createAccount(handle, email, password));
    } else {
      console.log(`Logging in as ${handle} ...`);
      sessions.push(await client.accounts.createSession(handle, password));
    }
  }

  for (const session of sessions) {
    const handle = session.handle ?? "<unknown>";
    const did = session.did;
    const jwt = session.accessJwt;
    if (!jwt) throw new Error(`Missing accessJwt for ${handle} (${did})`);
    console.log(`Seeding records for ${handle} (${did})...`);

    if (createProfiles) {
      try {
        await client.records.createRecord(
          did,
          "app.bsky.actor.profile",
          {
            "$type": "app.bsky.actor.profile",
            displayName: handle.split(".")[0].charAt(0).toUpperCase() +
              handle.split(".")[0].slice(1),
            description: "Seeded demo profile",
          },
          jwt,
          { rkey: "self" },
        );
      } catch (exc) {
        console.log(`  Profile creation failed: ${exc}`);
      }
    }

    for (let i = 0; i < postsPerAccount; i++) {
      try {
        await client.records.createRecord(did, "app.bsky.feed.post", {
          "$type": "app.bsky.feed.post",
          text: `Demo post #${i + 1} from ${handle} (Run ${suffix})`,
          createdAt: now,
        }, jwt);
      } catch (exc) {
        console.log(`  Post #${i + 1} failed: ${exc}`);
      }
    }
  }

  console.log("\nDemo accounts:");
  for (const session of sessions) {
    console.log(`  - ${session.handle}  password=${password}  did=${session.did}`);
  }
}

if (import.meta.main) {
  await main();
}
