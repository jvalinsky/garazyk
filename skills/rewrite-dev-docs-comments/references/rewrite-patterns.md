# Rewrite Patterns

Use this reference to convert low-signal prose into concise engineering writing.

## Fast Rubric
- Keep: facts, constraints, tradeoffs, invariants, failure modes, and decisions.
- Cut: hype, filler, repeated obvious statements, and anthropomorphic assistant voice.
- Replace: vague adjectives with measurable or falsifiable detail.

## Common Anti-Patterns
| Anti-pattern | Why it hurts | Rewrite target |
| --- | --- | --- |
| "robust / comprehensive / seamless / powerful" | Says quality without evidence | Describe behavior, scope, and limits |
| "it is important to note that" | Adds no content | Delete and state the fact directly |
| "simply / just / easy" | Hides complexity and edge cases | State exact required steps or preconditions |
| Repeating the same point in 2-3 sentences | Inflates size, lowers signal | Keep one precise sentence |
| Comment restates code | Adds maintenance cost | Remove, or explain why/constraint |
| Marketing claims ("game-changing", "best-in-class") | Non-technical, non-verifiable | Replace with measured outcomes |

## Rewrite Moves
1. Lead with the concrete claim.
2. Add mechanism ("how") if needed for implementation decisions.
3. Add boundary conditions (when it fails, what it does not cover).
4. Remove redundant transitions and conversational filler.
5. Prefer short sentences with specific nouns.

## Examples
Bad:
```text
This robust endpoint implementation seamlessly handles requests and ensures excellent reliability for users.
```

Better:
```text
The endpoint enforces a 2s upstream timeout, retries once on network resets, and returns 503 for persistent failures.
```

Bad:
```text
// This function increments the counter by one.
counter++;
```

Better:
```text
// Keep the counter monotonic so cursor ordering stays stable across reconnects.
counter++;
```

Bad:
```text
It is important to note that we basically just validate input here.
```

Better:
```text
Validate `did` format and reject unsupported key types before DB writes.
```

## Comment-Specific Rules
- Explain why a line exists, not what the syntax already shows.
- Name invariants and side effects when they are non-obvious.
- Keep comments close to the risky branch or unusual contract.
- Delete stale comments immediately when behavior changes.
