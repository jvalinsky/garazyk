# Low Priority Findings

## L1: PLC recovery window not enforced

### Spec Reference

https://web.plc.directory/spec/v0.1/did-plc — PLC rotation key changes should have a recovery window during which the previous key can revert the operation.

### Current Implementation

`PLCServer.m:535-624` — `handlePostDID:` accepts and applies operations immediately. No recovery window is enforced.

### Impact

- Key rotation is instant with no grace period
- If a rotation key is compromised, the attacker can immediately take over the DID
- No opportunity for the legitimate key holder to recover

### Remediation

Implement a recovery window (typically 72 hours per the PLC spec):
1. Store pending rotation key changes with a timestamp
2. Allow the previous rotation key to revert changes within the window
3. After the window expires, the change becomes permanent

---

## L2: Lexicon validation not strict enough

### Evidence

Several lexicon-defined fields are not validated against their schemas:

1. `alsoKnownAs` entries should start with `at://` but this is not enforced in `PLCServer.m`
2. `services.atproto_pds.endpoint` should be a valid HTTPS URL but only length is checked
3. `verificationMethods` keys should be `did:key:` format but only length is checked

### Impact

Invalid data may be accepted and propagated through the network. Other implementations may reject operations that garazyk accepts.

### Remediation

Add stricter validation in `PLCValidateIncomingOperation`:
1. Validate `alsoKnownAs` entries start with `at://`
2. Validate service endpoints are valid HTTPS URLs
3. Validate `verificationMethods` values are `did:key:` format
4. Add tests for each validation rule
