---
name: garazyk-phone-email-providers
description: Implement, test, or review Garazyk phone verification and email provider integrations. Covers Twilio, Vonage, Plivo, Telegram Gateway, Resend, SMTP/mock providers, mock servers, secrets, retries, error semantics, and test isolation.
---

# Garazyk Phone and Email Providers

Use this skill for phone verification, OTP, email delivery, provider factories, mock provider tests, and production secret handling.

## Key files

Phone verification:

- `Garazyk/Sources/PhoneVerification/`
- `Garazyk/Sources/Registration/PDSPhoneOTPRegistrationGate.*`
- mock servers: `scripts/mock-twilio-server.ts`, `scripts/mock-twilio-server.test.ts`, `scripts/mock-telegram-server.ts`, `scripts/mock-telegram-server.test.ts`
- scenario/config flags: `scripts/manage_local_network.ts`, `docker/local-network/Dockerfile.mock-twilio`

Email:

- `Garazyk/Sources/Email/`
- `PDSResendEmailProvider.*`
- `PDSSMTPEmailProvider.*` (configured but intentionally not implemented)
- `PDSMockEmailProvider.*`
- `PDSEmailProviderFactory.*`

Tests:

- relevant `Garazyk/Tests/` provider/factory/registration tests
- scenario `19_contact_age_assurance.ts`, `53_phone_verification.ts`, negative auth/contact scenarios

## Provider design principles

- Provider adapters should be thin and deterministic.
- Normalize provider-specific failures into project-domain errors.
- Do not leak phone numbers, emails, OTPs, API keys, auth headers, or verification IDs in logs.
- Keep retry policy bounded and explicit.
- Tests should use mock providers/servers, never real third-party APIs.
- Production credentials come from environment/secret store, not source files.

## Secrets and logging checklist

Before adding or changing a provider, identify all sensitive values:

- API keys/tokens
- account SID/app IDs
- phone numbers and email addresses
- OTP codes
- verification session IDs
- auth headers
- webhook signatures

Rules:

- redact in logs and diagnostics
- never include in XCTest failure strings unless masked
- do not persist raw OTPs unnecessarily
- avoid recording provider request bodies as artifacts unless redacted
- ensure config examples use placeholders only

## Phone provider workflow

### 1. Classify provider behavior

Record:

- send endpoint and check endpoint
- auth scheme
- request content type
- success response fields
- pending/approved/failed/expired states
- provider rate-limit response
- idempotency/session semantics
- timeout and retry recommendations

### 2. Implement adapter

Follow existing provider style in `Garazyk/Sources/PhoneVerification/`.

Adapter should:

- validate phone format before external calls where possible
- build requests with prepared/escaped URL or JSON/form bodies
- set explicit timeouts
- parse JSON defensively
- map provider status into internal status enum/string consistently
- return useful but redacted errors
- make retry decisions only for transient failures

### 3. Mock server support

For external APIs, add/update a Deno mock server if scenario or integration tests need HTTP behavior.

Mock server should support:

- deterministic success path
- invalid code path
- expired/session-not-found path
- provider rate-limit or transient 5xx path
- request assertions without storing secrets in logs

Use existing mock server patterns in `scripts/mock-*-server.ts`.

## Email provider workflow

### Resend

Check:

- API endpoint and key from config/env
- sender/from address validation
- JSON response parsing
- non-2xx mapping
- redaction of recipient/content in logs where appropriate

### SMTP

`PDSSMTPEmailProvider` is currently a configured-but-not-implemented provider. Do not make tests expect real SMTP delivery unless implementing the full adapter. If enabling SMTP, include TLS/auth configuration and integration tests behind environment gating.

### Mock email

Mock provider should be the default test path. Tests can assert:

- message was requested
- recipient/template/subject shape
- failure injection behavior
- no network required

## Retry and error semantics

Classify errors:

| Error | Behavior |
| --- | --- |
| malformed phone/email | fail fast, no provider call |
| invalid OTP | expected user-facing failure |
| expired verification | expected retry/new-session path |
| provider 401/403 | config/secret error, do not retry indefinitely |
| provider 429 | bounded retry or clear rate-limit error |
| provider 5xx/network | bounded retry with backoff |
| parse error | provider contract error, include redacted body summary only |

Keep retries low in request paths. Prefer queue/background retry only where architecture already supports it.

## Test isolation

XCTest/provider tests must:

- set env/config explicitly
- use mock providers or localhost mock servers
- avoid dependence on test order
- clear provider factory registrations after test
- avoid writing to production data/secrets paths
- run with deterministic OTP/code values when possible

Scenario tests must:

- start mock servers through local-network setup where needed
- record only redacted artifacts
- skip clearly when optional provider capability is disabled
- include negative paths for invalid/expired codes

## Production readiness checklist

- Config validation catches missing required provider secrets.
- Logs redact sensitive values.
- Provider timeout/retry behavior is bounded.
- Mock tests cover success and failure mappings.
- Scenario coverage exists for user-visible flow.
- Docs/config examples describe required env vars without real secrets.

## Review output format

```md
## Provider review

- Provider:
- Flow: send/check/email delivery
- Secrets involved:
- Mock coverage:
- Error mapping:
- Retry behavior:
- Test isolation:
- Scenario impact:
```

## Definition of done

- Provider adapter maps external contract to internal semantics.
- Secrets are never committed or logged raw.
- Mock server/provider tests cover success and key failure states.
- Config validation and examples are updated.
- Scenario or integration coverage exists for user-visible behavior.
