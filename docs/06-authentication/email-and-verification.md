---
title: Email and Verification
---

# Email and Verification

## Overview

Account creation in September is not just "accept email and password." The implementation combines registration policy, handle/domain rules, optional email delivery, and optional verification providers.

The important contributor distinction is this:

- some settings are product policy,
- some settings are integration points,
- and some settings exist mainly to support local development or tests.

Understanding which is which prevents accidental production regressions.

## The Three Policy Layers

### Registration policy

The `session` section decides how open account creation is:

- `invite_code_required`
- access and refresh token TTLs

In the runtime configuration class, defaults skew toward development convenience. Production guidance in this repository is stricter and requires invite codes to stay enabled.

### Identity and handle policy

The `server` section controls:

- canonical issuer,
- bind host and port,
- `available_user_domains`

This is what determines which handles the server is willing to issue and what identity clients see in discovery metadata.

### Verification integrations

The PDS supports pluggable providers rather than hard-coding one delivery mechanism.

- `phone_verification.provider`
- `email.provider`
- provider-specific SMTP and Resend settings

The default posture is intentionally conservative: no provider is assumed unless configured.

## Email Providers

The configuration loader supports these email provider modes:

| Provider value | Intended use |
| --- | --- |
| `none` | No outbound email integration |
| `mock` | Tests and local development |
| `smtp` | SMTP delivery using configured host, port, credentials, and TLS flag |
| `resend` | HTTP delivery using the Resend integration and secrets provider settings |

The practical rule for contributors is simple: if a docs example needs email, it should say whether it assumes `mock`, `smtp`, or `resend`.

## Phone Verification Providers

Phone verification follows the same pattern:

| Provider value | Meaning |
| --- | --- |
| `none` | No phone verification requirement |
| `mock` | Development or test-only behavior |
| custom provider key | Real provider integration selected by configuration |

The codebase currently centralizes selection logic in configuration, which means docs should describe provider choice at the config level, not pretend it is a hard-wired runtime behavior.

## Secrets and Provider Settings

Provider configuration spans several categories:

| Category | Example keys |
| --- | --- |
| SMTP transport | `smtp_host`, `smtp_port`, `smtp_username`, `smtp_password`, `smtp_use_tls` |
| Resend integration | `resend_api_key_source`, `resend_api_key_env_var`, `resend_keychain_service`, `resend_keychain_account`, `resend_from_address`, `resend_api_endpoint` |
| Environment overrides | `PDS_EMAIL_PROVIDER`, `PDS_EMAIL_SMTP_*`, `PDS_RESEND_*` |

For storage and secret-handling guidance, use [Secrets Management](./secrets-management). This page is about how the verification model fits into contributor workflows, not how to store credentials safely.

## Why This Design Exists

The email and verification design solves three different problems:

1. Local development needs fast paths such as `mock` without forcing fake production defaults into shipped configs.
2. Production deployments need explicit, auditable integration points for real delivery providers.
3. Core account logic should not need to know whether a message was sent via SMTP, Resend, or a test double.

That separation is why provider choice belongs in configuration and why docs should explain the operational reason behind each setting.

## What Contributors Usually Touch

If you are changing onboarding or account flows, you usually need to inspect:

- `PDSConfiguration` for provider selection and env overrides,
- account service code for when verification is enforced,
- email provider implementations under `ATProtoPDS/Sources/Email/`,
- the tests in `ATProtoPDS/Tests/Email/` and related account/auth tests.

If you are writing docs, also cross-check:

- [Tutorial 2: Accounts](../10-tutorials/tutorial-2-accounts)
- [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment)
- historical deep dives under `docs/oauth2/` and `docs/security/`

## Recommended Contributor Defaults

Use these assumptions unless a task says otherwise:

- local development: `mock` or `none`
- integration testing: explicit mock provider
- production docs: invite codes enabled, real issuer, real PLC, real provider or an explicit note that email is not enabled

That keeps the docs honest about what is runnable, what is safe, and what still depends on deployment policy.

## Related Reading

- [Secrets Management](./secrets-management)
- [Security Best Practices](./security-best-practices)
- [Tutorial 2: Accounts](../10-tutorials/tutorial-2-accounts)
- [Tutorial 6: Deployment](../10-tutorials/tutorial-6-deployment)
