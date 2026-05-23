#!/usr/bin/env deno run --allow-read --allow-write --allow-net
/**
 * @module scripts/generate_germ_record.ts
 *
 * Generates a valid cryptographically secure Ed25519 anchor key pair,
 * formats the corresponding com.germnetwork.declaration record, and optionally
 * publishes it to a PDS using an App Password / login credentials.
 */

import { parseArgs } from "jsr:@std/cli/parse-args";
import { join } from "jsr:@std/path/join";

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function publishRecord(
  pdsUrl: string,
  identifier: string,
  password: string,
  record: unknown
): Promise<{ did: string; uri: string; cid: string }> {
  const cleanPdsUrl = pdsUrl.replace(/\/$/, "");

  // 1. Create Session (Login)
  const sessionRes = await fetch(`${cleanPdsUrl}/xrpc/com.atproto.server.createSession`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ identifier, password }),
  });

  if (!sessionRes.ok) {
    const errorText = await sessionRes.text();
    throw new Error(`Failed to authenticate with PDS: ${sessionRes.status} ${errorText}`);
  }

  const session = await sessionRes.json() as { did: string; accessJwt: string };

  // 2. Put Record
  const putRecordRes = await fetch(`${cleanPdsUrl}/xrpc/com.atproto.repo.putRecord`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${session.accessJwt}`,
    },
    body: JSON.stringify({
      repo: session.did,
      collection: "com.germnetwork.declaration",
      rkey: "self",
      validate: true,
      record: record,
    }),
  });

  if (!putRecordRes.ok) {
    const errorText = await putRecordRes.text();
    throw new Error(`Failed to publish record to PDS: ${putRecordRes.status} ${errorText}`);
  }

  const putResult = await putRecordRes.json() as { uri: string; cid: string };
  return { did: session.did, uri: putResult.uri, cid: putResult.cid };
}

async function main() {
  const args = parseArgs(Deno.args, {
    string: ["url", "policy", "handle", "password", "pds", "out-dir"],
    alias: {
      h: "help",
      u: "handle",
      p: "password",
      d: "out-dir",
    },
    default: {
      url: "https://germ.garazyk.xyz/mailbox/message-me",
      policy: "everyone",
      pds: "https://pds.garazyk.xyz",
      "out-dir": "./keys",
    },
  });

  if (args.help) {
    console.log(`
Usage: deno run --allow-net --allow-read --allow-write scripts/generate_germ_record.ts [options]

Options:
  -u, --handle <handle>      ATProto handle or DID to log in and publish the record.
  -p, --password <pwd>       App Password or main password for PDS authentication.
  --pds <url>                The target PDS URL. (Default: https://pds.garazyk.xyz)
  --url <url>                The Germ messageMe URL. (Default: https://germ.garazyk.xyz/mailbox/message-me)
  --policy <type>            Button visibility policy: "everyone" | "usersIFollow" | "none". (Default: everyone)
  -d, --out-dir <path>       Directory to save the generated private & public key files. (Default: ./keys)
    `);
    Deno.exit(0);
  }

  const allowedPolicies = ["everyone", "usersIFollow", "none"];
  if (!allowedPolicies.includes(args.policy)) {
    console.error(`Error: Policy must be one of: ${allowedPolicies.join(", ")}`);
    Deno.exit(1);
  }

  console.log("Generating secure Ed25519 Anchor Key pair...");

  // 1. Generate standard cryptographically secure Ed25519 Key Pair
  const keyPair = (await crypto.subtle.generateKey(
    { name: "Ed25519" },
    true,
    ["sign", "verify"]
  )) as CryptoKeyPair;

  // 2. Export raw public key (32 bytes)
  const rawPublicKey = new Uint8Array(
    await crypto.subtle.exportKey("raw", keyPair.publicKey)
  );

  // 3. Export private key (PKCS#8 DER)
  const pkcs8PrivateKey = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keyPair.privateKey)
  );

  // 4. Create the 33-byte Typed Key Material (0x03 prefix + 32 bytes public key)
  const typedKey = new Uint8Array(33);
  typedKey[0] = 0x03; // curve25519Signing algorithm prefix
  typedKey.set(rawPublicKey, 1);

  const base64AnchorKey = bytesToBase64(typedKey);

  // 5. Build the complete ATProto com.germnetwork.declaration record
  const record = {
    $type: "com.germnetwork.declaration",
    version: "1.0.0",
    currentKey: {
      $bytes: base64AnchorKey,
    },
    messageMe: {
      showButtonTo: args.policy,
      messageMeUrl: args.url,
    },
  };

  // Convert PKCS#8 DER to standard PEM format
  const base64PrivateKey = bytesToBase64(pkcs8PrivateKey);
  const pemPrivateKey = [
    "-----BEGIN PRIVATE KEY-----",
    ...base64PrivateKey.match(/.{1,64}/g) || [base64PrivateKey],
    "-----END PRIVATE KEY-----",
  ].join("\n");

  // Save keys locally
  const outDir = args["out-dir"];
  await Deno.mkdir(outDir, { recursive: true });

  const filePrefix = args.handle ? args.handle.replace(/[^a-zA-Z0-9.-]/g, "_") : "germ";
  const privateKeyPath = join(outDir, `${filePrefix}_private.pem`);
  const publicKeyPath = join(outDir, `${filePrefix}_public.json`);

  await Deno.writeTextFile(privateKeyPath, pemPrivateKey);
  await Deno.writeTextFile(publicKeyPath, JSON.stringify(record, null, 2));

  console.log("\n========================================================");
  console.log("             GENERATED ANCHOR KEY MATERIAL              ");
  console.log("========================================================\n");

  console.log("🔑 RAW PUBLIC KEY (Hex):");
  console.log(bytesToHex(rawPublicKey));
  console.log();

  console.log("📦 TYPED ANCHOR KEY MATERIAL (Base64 / 33 bytes):");
  console.log(base64AnchorKey);
  console.log();

  console.log("💾 LOCAL FILES SAVED:");
  console.log(`  • Private Key (PEM): ${privateKeyPath}`);
  console.log(`  • Public Record (JSON): ${publicKeyPath}`);
  console.log();

  if (args.handle && args.password) {
    console.log(`🌐 Publishing record to PDS (${args.pds}) for account ${args.handle}...`);
    try {
      const publishResult = await publishRecord(args.pds, args.handle, args.password, record);
      console.log("\n✅ PUBLISHED SUCCESSFULLY!");
      console.log(`  • Account DID:   ${publishResult.did}`);
      console.log(`  • Record AT URI: \x1b[36mat://${publishResult.did}/com.germnetwork.declaration/self\x1b[0m`);
      console.log(`  • Record CID:    ${publishResult.cid}`);
      console.log();
      console.log("📜 Published Record:");
      console.log(JSON.stringify(record, null, 2));
    } catch (err) {
      console.error(`\n❌ Error publishing record: ${(err as Error).message}`);
      Deno.exit(1);
    }
  } else {
    console.log("📜 com.germnetwork.declaration RECORD (JSON):");
    console.log(JSON.stringify(record, null, 2));
    console.log();
    console.log("ℹ️  To automatically publish this record to your PDS, run with --handle and --password options.");
  }

  console.log("\n========================================================\n");
  console.log("⚠️  Keep your PRIVATE KEY secure! You will need it to sign key packages later.");
}

if (import.meta.main) {
  await main();
}
