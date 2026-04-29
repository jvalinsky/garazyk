# Medium Priority Findings

## M1: Docker testnet keys in `/tmp` (fragile)

### Evidence

`docker/local-network/docker-compose.yml` mounts key material from host `/tmp` paths. On macOS, `/tmp` is cleared periodically and on reboot.

### Impact

- Testnet requires re-seeding after every reboot
- Keys disappear without warning
- Developers waste time debugging "why did auth stop working"

### Remediation

Use named Docker volumes or persistent host paths:
```yaml
volumes:
  plc-keys:
  pds-keys:
```

---

## M2: E2E test stack lacks AppView

### Evidence

`docker/e2e/docker-compose.yml` only includes:
- PLC (campagnola) on port 2582
- PDS (kaszlak) on port 2583
- Relay (zuk) on port 2584

Missing: AppView (syrena) on port 3200.

### Impact

- Cannot test subscription processing
- Cannot test label generation
- Cannot test indexed views
- Cannot verify full pipeline: PDS → Relay → AppView

### Remediation

Add syrena service to `docker/e2e/docker-compose.yml` with proper relay and PLC URL configuration.

---

## M3: Relay does not forward `#account` events from upstream

### Evidence

`RelayDownstreamHandler.m:90`:
```objc
[self broadcastIdentityEvent:identityEvent];
```

Only `#identity` events are forwarded. The relay subscribes to PDS firehose streams but drops `#account` events.

### Impact

Relay consumers (AppViews, labelers) miss account lifecycle events from all connected PDS instances. This compounds the C1 finding — even if PDS instances start emitting `#account` events, the relay won't forward them.

### Remediation

Add `#account` event forwarding in `RelayDownstreamHandler`:
```objc
- (void)handleAccountEvent:(FirehoseAccountEvent *)accountEvent {
    [self broadcastAccountEvent:accountEvent];
}
```

---

## M4: `getAccountForDid:` returns email (PII leak)

### Evidence

`PDSAccountService.m:390-399`:
```objc
return @{
    @"did": account.did ?: @"",
    @"handle": account.handle ?: @"",
    @"email": account.email ?: @""  // ← Should not be in response
};
```

The spec for `com.atproto.server.getAccount` returns `{did, handle}` only. Email is PII and should not be exposed through this endpoint.

### Impact

- Email addresses leak through XRPC endpoint
- Violates principle of least privilege
- May violate privacy regulations

### Remediation

Remove `email` from the response dictionary. If email is needed, it should be gated behind a separate authenticated endpoint (e.g., `com.atproto.server.getSession` already provides this).
