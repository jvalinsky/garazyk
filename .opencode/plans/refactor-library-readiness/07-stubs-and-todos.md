# Refactor 7: Stub/TODO Documentation

## Evidence

**Not-implemented features currently in the codebase:**

| Feature | File | Status |
|---------|------|--------|
| SMTP email delivery | `Sources/Email/PDSSMTPEmailProvider.m` | Stub — fails closed with error |
| CAPTCHA server-side verify | `Sources/Registration/PDSCaptchaRegistrationGate.m:58` | TODO — HTTP POST not implemented |
| YubiKey OATH | `Sources/Auth/YubiKeyOATH.h` | Error constant for not implemented |
| STAR MST walk | `Sources/Repository/STAR.m:974` | TODO — MST reconstruction from CAR |
| SMTP CLI warning | `Sources/CLI/PDSCLIInitCommand.m:96` | Warns SMTP not implemented |
| GSTREAMER video | `Sources/Video/` | Some pipeline stubs |

## Why It Matters

Library consumers need clear documentation of what works and what doesn't. Silent stubs that fail at runtime erode trust. Clear documentation:

- Sets expectations accurately
- Prevents wasted debugging on features that are explicitly not implemented
- Makes contribution opportunities visible

## Proposed Changes

### Phase 1: Document Each Stub

For each stub, ensure the header documentation clearly states the limitation:

```objc
// PDSSMTPEmailProvider.h
/// SMTP-based email delivery.
///
/// @warning SMTP delivery is **not implemented**. All send attempts fail
///          with PDSEmailErrorNotImplemented. Use ResendEmailProvider
///          or MockEmailProvider for working email delivery.
```

### Phase 2: Add Build-Time Warnings

For stubs that are likely to be encountered at compile time (e.g., someone trying to configure SMTP), add deprecation attributes or `#warning` directives:

```objc
@interface PDSSMTPEmailProvider : PDSEmailProvider
#pragma message "SMTP email is not implemented — use ResendEmailProvider"
```

### Phase 3: Runtime Diagnostics

Enhance the existing warnings in `PDSEmailProviderFactory.m:90` and `PDSCLIInitCommand.m:96` to:
- Log at startup if a stub provider is configured
- Include the provider name in the warning
- Suggest the working alternative

### Phase 4: Validate All TODOs

Audit the remaining TODO/FIXME markers to determine which are:
- Planned features (keep as TODO with tracking issue)
- Technical debt (promote to FIXME with description)
- Outdated (remove)

## Files to Modify

| File | Change |
|------|--------|
| `Sources/Email/PDSSMTPEmailProvider.h` | Add `@warning not implemented` to header doc |
| `Sources/Email/PDSSMTPEmailProvider.m` | Add `#pragma message` for compile-time warning |
| `Sources/Registration/PDSCaptchaRegistrationGate.m` | TODO → documented limitation |
| `Sources/Auth/YubiKeyOATH.h` | Add header doc for not-implemented status |
| `Sources/Repository/STAR.m:974` | Expand TODO comment to describe the gap |
| `Sources/CLI/PDSCLIInitCommand.m:96` | Ensure warning is user-visible |

## Non-Goals

- Do NOT implement any of these features
- Do NOT remove the stubs — failing closed is the correct behavior for unimplemented features
- Only document the gap more clearly

## Dependencies

None — self-contained documentation cleanup.

## Confidence: High

Documentation changes carry no behavioral risk.
