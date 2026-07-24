---
title: Germ E2EE Mailbox Setup Guide
---

# Germ E2EE Mailbox Setup Guide

This guide describes how to configure, generate key material for, and publish a `com.germnetwork.declaration` record to an AT Protocol Personal Data Server (PDS) to point to a live Germ E2EE Mailbox (such as `germ.garazyk.xyz`).

---

## 1. Concepts & Architecture

Germ’s end-to-end encrypted (E2EE) messaging protocol uses a cryptographic binding between your AT Protocol identity (DID) and a client-side device key:

- **PDS Repository Key**: Held (or authorized) by your PDS to sign standard ATProto repository writes (posts, profiles, follow graphs).
- **Anchor Key (`currentKey`)**: A separate, device-bound Ed25519 signing key generated on your device. For security, your raw private messaging key **never** leaves your local client.
- **Germ Declaration Record (`com.germnetwork.declaration`)**: A record stored in your repository at the path `com.germnetwork.declaration/self`. It contains:
  - Your public **Anchor Key** (`currentKey`), indicating you authorize this key for messaging.
  - A Visibility Policy (`showButtonTo`), indicating who can see your message button.
  - A Mailbox URL (`messageMeUrl`), indicating where clients should direct DMs.

---

## 2. Generating & Publishing via Deno Tooling

The project provides an automated Deno script to handle key generation, local storage, PDS authentication (via App Passwords), and record publishing:

```bash
# Script Path
scripts/generate_germ_record.ts
```

### Dry-Run: Local Generation Only
Generate a cryptographically secure Ed25519 key pair and construct the corresponding record locally without authenticating with a PDS:

```bash
deno run -A scripts/generate_germ_record.ts
```

This output shows your raw public key, base64-encoded Typed Key Material, and saves the files locally:
- **Private Key**: `keys/germ_private.pem` (PKCS#8 format)
- **Public Record**: `keys/germ_public.json`

---

### Full Run: Local Generation & PDS Publishing
To automatically write this record into your active PDS repository using your handle and an App Password (or main password):

```bash
deno run -A scripts/generate_germ_record.ts \
  --handle "your-handle.garazyk.xyz" \
  --password "your-app-password" \
  --pds "https://pds.garazyk.xyz" \
  --url "https://germ.garazyk.xyz/mailbox/message-me" \
  --policy "everyone"
```

#### Command-Line Arguments:
- `-u, --handle`: Your ATProto handle or DID.
- `-p, --password`: Your PDS password or App Password.
- `--pds`: The target PDS host URL (Defaults to `https://pds.garazyk.xyz`).
- `--url`: The message me endpoint URL (Defaults to `https://germ.garazyk.xyz/mailbox/message-me`).
- `--policy`: Visibility of the button (`everyone` | `usersIFollow` | `none`).
- `-d, --out-dir`: The directory to write the generated keys (Defaults to `./keys`).

---

### Command Output Explanation

When run successfully, the script prints:

1. **Local Files Saved**:
   - `keys/your-handle.garazyk.xyz_private.pem` (Your private key—keep this secure!)
   - `keys/your-handle.garazyk.xyz_public.json` (Your public record configuration)
2. **PDS Publish Confirmation**:
   - **Account DID**: The resolved `did:plc:...` of your handle.
   - **Record AT URI**: The canonical reference to the record:
     `at://did:plc:<your-did>/com.germnetwork.declaration/self`
   - **Record CID**: The content identifier of the published commit.

---

## 3. Verifying the Setup

You can verify that the PDS repository has successfully published the record by performing a public `getRecord` query using `curl`:

```bash
curl -s "https://pds.garazyk.xyz/xrpc/com.atproto.repo.getRecord?repo=did:plc:<your-did>&collection=com.germnetwork.declaration&rkey=self"
```

Expected response containing the lexicon schema:

```json
{
  "uri": "at://did:plc:<your-did>/com.germnetwork.declaration/self",
  "cid": "bafyreih...",
  "value": {
    "$type": "com.germnetwork.declaration",
    "version": "1.0.0",
    "currentKey": {
      "$bytes": "A06d/vZ2tnqJJ9ephTXn3G6HO6cfucgWCf1ck37ELOEk"
    },
    "messageMe": {
      "showButtonTo": "everyone",
      "messageMeUrl": "https://germ.garazyk.xyz/mailbox/message-me"
    }
  }
}
```

---

## 4. How Clients Interact with your Mailbox

Once your record is published, ATProto clients and AppViews perform the following steps to interact with your live mailbox:

### A. Completing the DM Button Link
When another user (e.g. `did:plc:bob`) views your profile (`did:plc:alice`), their client completes the `messageMeUrl` by appending both DIDs to the hash fragment:

- **Link structure**: `[messageMeUrl]#[profileDID]+[viewerDID]`
- **Completed Link**: `https://germ.garazyk.xyz/mailbox/message-me#did:plc:alice+did:plc:bob`

### B. Authenticating to the Germ Mailbox Service
To claim mailbox addresses or poll messages, your client needs PDS-signed **Service Authentication** tokens:

1. Request a token targeting the Germ service host's DID (`did:web:germ.garazyk.xyz#germ_mailbox`) from your PDS via `com.atproto.server.getServiceAuth`:
   ```bash
   curl -X GET "https://pds.garazyk.xyz/xrpc/com.atproto.server.getServiceAuth?aud=did:web:germ.garazyk.xyz%23germ_mailbox&lxm=com.germnetwork.mailbox.claimAddresses" \
     -H "Authorization: Bearer <your_pds_access_jwt>"
   ```
2. Send the returned JWT token as a Bearer authorization token to the Germ service endpoints:
   - `POST https://germ.garazyk.xyz/xrpc/com.germnetwork.mailbox.claimAddresses`
   - `POST https://germ.garazyk.xyz/xrpc/com.germnetwork.mailbox.deliver`
   - `GET  https://germ.garazyk.xyz/xrpc/com.germnetwork.mailbox.poll`
