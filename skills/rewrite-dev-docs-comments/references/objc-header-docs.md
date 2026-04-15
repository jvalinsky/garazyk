# Objective-C Header Docs

Use this guide when documenting Objective-C APIs and comments around them.

## Placement
- Document public API contracts at declarations in `.h`.
- Keep `.m` comments for non-obvious implementation rationale (lock ordering, parser assumptions, state transitions).
- Do not split one contract across many files; keep caller-facing details adjacent to declarations.

## Contract Checklist
Include only fields that matter for that symbol:
- Summary of behavior.
- Preconditions and postconditions.
- Parameter meaning, units, and accepted ranges.
- Return semantics.
- Error behavior and domain/codes when known.
- Nullability, ownership, and lifetime expectations.
- Threading and side effects.

## Style Choice
- Match repository conventions first.
- If no convention exists, use one consistent style:
1. `/** ... */` with `@param` and `@result`/`@return` tags.
2. `///` with `- Parameters:` and `- Returns:` blocks for Xcode Quick Help markup.

## Templates
### HeaderDoc/Doxygen-style Block
```objc
/**
 Validate DID syntax and accepted key types before persistence.

 @discussion Reject unsupported methods early to keep repository state canonical.
 @param did Candidate DID string from client input.
 @param error Optional pointer that receives NSPDSErrorDomain codes.
 @result YES when the DID can be written; NO on validation failure.
 */
- (BOOL)validateDID:(NSString *)did error:(NSError **)error;
```

### Quick Help-style Line Comments
```objc
/// Persist a session token for outbound requests.
///
/// - Parameter token: Non-empty token string. Pass `nil` to clear.
/// - Returns: `YES` when token is accepted and cached; otherwise `NO`.
- (BOOL)setSessionToken:(nullable NSString *)token;
```

## Red Flags
- Summary repeats method name without additional information.
- Parameters are named but not described.
- Returns says only "success/failure" without conditions.
- Comment describes internals that callers do not need.
- Comment omits side effects (cache invalidation, network calls, durable writes).
