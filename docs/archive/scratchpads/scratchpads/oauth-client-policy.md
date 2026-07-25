# OAuth Client Policy & Display Name Spoofing Hardening Scratchpad

This scratchpad serves as temporary memory and implementation notes for the OAuth policy changes.

## Goals & Decisions

- **Goal #518**: Implement PDS OAuth client policy and trusted ID display.
- **Decision #519**: Sanitize `client_name` in `validateClient` for spoofing protection.
- **Decision #520**: Operator allowlist client policy.

---

## 1. Configuration Spec (`oauth` block)

Under the nested `oauth` configuration map:
```yaml
oauth:
  client_policy: "dynamic" | "allowlist"
  trusted_client_ids:
    - "https://bsky.app/oauth/client-metadata.json"
  allowed_client_ids:
    - "https://bsky.app/oauth/client-metadata.json"
```

Environment overrides:
- `PDS_OAUTH_CLIENT_POLICY`
- `PDS_OAUTH_TRUSTED_CLIENT_IDS` (comma-separated string)
- `PDS_OAUTH_ALLOWED_CLIENT_IDS` (comma-separated string)

---

## 2. Implementation Checklist

- [ ] Add config properties to `ATProtoServiceConfiguration.h`
- [ ] Parse config properties and setup env overrides in `ATProtoServiceConfiguration.m`
- [ ] Enforce client_policy allowlist in `OAuth2Handler.m` `validateClient:completion:`
- [ ] Overwrite `client_name` to `clientID` if the client is not database-registered and not in `trusted_client_ids`
- [ ] Update `serveAuthorizePage:params:` signature to include client dictionary
- [ ] Render `{{client_name}}` in `authorize.html`
- [ ] Write robust unit tests verifying policy checks and display name spoofing mitigations
- [ ] Build & run the entire test suite and verify scenario passes
