# Rewrite Patterns

Use this reference to rewrite docs/comments into high-signal engineering prose.

## Signal-First Rubric
- Keep: behavior, constraints, invariants, failure modes, tradeoffs, and operator actions.
- Cut: hype, filler, time-sensitive qualifiers, and assistant-style narration.
- Replace: vague claims with measurable detail or explicit uncertainty.

## Low-Signal to High-Signal Replacements
| Low-signal phrasing | Why it hurts | Rewrite target |
| --- | --- | --- |
| robust / comprehensive / powerful / seamless | Claims quality without evidence | State scope, mechanism, and limits |
| game-changing / best-in-class / next-gen / cutting-edge | Marketing, not engineering signal | Replace with measurable behavior |
| it is important to note that / in conclusion | Adds filler, no information | Delete and state the fact directly |
| simply / just / easy | Masks complexity and risks | State prerequisites and exact steps |
| currently / now / latest | Ages quickly in long-lived docs | Write timelessly about present behavior |
| this function increments X | Restates obvious code | Explain why increment matters |

## Rewrite Moves
1. Start with the concrete behavior or decision.
2. Add mechanism only if it helps implementation or operations.
3. Add boundaries: limits, preconditions, and failure handling.
4. Remove duplicate sentences and conversational glue.
5. Keep sentence length short and nouns specific.

## Situational Utility Check
Every paragraph should answer at least one of these:
- What action should the reader take?
- Why does this behavior exist?
- When does it fail or not apply?
- What constraint or invariant must stay true?
- What is the blast radius if this is wrong?

Delete any paragraph that answers none.

## Objective-C Comment Transformations
Bad:
```objc
// This method sets the token.
- (void)setToken:(NSString *)token;
```

Better:
```objc
/// Store the bearer token used for outbound federation requests.
/// Reject empty values and clear cached auth headers.
- (void)setToken:(NSString *)token;
```

Bad:
```objc
/**
 * A robust and comprehensive validator.
 */
- (BOOL)validateDID:(NSString *)did error:(NSError **)error;
```

Better:
```objc
/**
 Validate DID syntax and supported key types before persistence.

 @param did Candidate DID from client input.
 @param error Optional error pointer; receives NSPDSErrorDomain on failure.
 @result YES when DID is accepted for write; NO when validation fails.
 */
- (BOOL)validateDID:(NSString *)did error:(NSError **)error;
```

## Placement Rules
- Public API contracts belong in header declarations.
- Implementation details belong in source near risky code paths.
- Operator steps belong in runbooks/how-to docs.
- Architecture tradeoffs belong in explanation/design docs.

## Comment-Specific Rules
- Explain why and constraints, not syntax.
- Mention side effects, ordering assumptions, and threading expectations when non-obvious.
- Keep comments adjacent to the code they constrain.
- Delete or update stale comments in the same change that modifies behavior.
