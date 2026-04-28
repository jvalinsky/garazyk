---
name: better-code-opencode
description: "Engineering excellence principles for agentic development: Correctness, Clarity, Changeability, and Primitives over Features."
---

# Better Code: Opencode Excellence

This skill translates core engineering excellence principles into actionable heuristics for agentic interaction.

## The Three Invariants

Every change MUST simultaneously satisfy these three criteria:

1. **Correctness**: The code handles all edge cases (null, empty, error states) and fails explicitly.
2. **Clarity**: The intent is understood in <30 seconds by a peer. If logic is complex, it is either refactored or documented via a `deciduous` goal node.
3. **Changeability**: The blast radius of a change is proportional to its semantic scope. Abstractions should not couple unrelated domains.

## Core Heuristics

### 1. Parse, Don't Validate
Avoid "shotgun validation" (checking invariants in every function). Instead:
- Push validation to system boundaries (input entry points).
- Produce typed objects that are **correct by construction**.
- Internal logic should rely on the type system rather than re-checking nullability or range.

### 2. Fail Fast & Early Returns
Keep the "happy path" at the minimum indentation level.
- Use guard clauses at the top of functions.
- If a precondition fails, return or throw immediately.

### 3. Primitives over Features
Build **Primitives** (reusable building blocks) rather than **Features** (one-off solutions).
- If you find yourself writing "glue code" for the third time, abstract it into a primitive.
- Logic should be data-driven or configuration-driven where possible.

### 4. Decision Tracking
Excellence requires a record of *why* choices were made.
- Every significant architectural decision MUST be logged in the `deciduous` graph.
- Attach verbatim user prompts to `goal` nodes to maintain the source of truth.

## Checklist for Every Task
- [ ] Does this change maintain all Three Invariants?
- [ ] Is validation pushed to the boundary?
- [ ] Is the happy path easily identifiable (minimal indentation)?
- [ ] Has the decision been logged in the graph?
