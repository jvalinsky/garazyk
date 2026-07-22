# Permissioned-space signing-key rotation

This runbook changes only the signer used for newly issued permissioned-space
credentials. It does not rotate the account signing key or alter space data.

1. Stop all but one PDS process that can write the actor store. Prepare the
   key with `kaszlak account prepare-space-key <did>`. The command is
   idempotent and prints only the public `did:key` value.
2. Request an authenticated PLC operation signature, add the printed value as
   `verificationMethods.atproto_space`, then sign and submit it through
   `com.atproto.identity.signPlcOperation` and
   `com.atproto.identity.submitPlcOperation`. Preserve the current
   `atproto`, rotation keys, services, and `alsoKnownAs` entries.
3. Resolve the DID freshly and confirm that `#atproto_space` exactly matches
   the prepared public key. Only then will the PDS mint new credentials with
   that key and `kid` `#atproto_space`.
4. Keep the account key published through the configured credential lifetime.
   Existing `#atproto` credentials continue to verify during this overlap.
   If publishing fails, leave the dedicated key unused; normal credential
   issuance remains on `#atproto`.

The CLI never accepts private key material or PLC confirmation tokens as
arguments, and neither the command nor the PDS logs these values.
