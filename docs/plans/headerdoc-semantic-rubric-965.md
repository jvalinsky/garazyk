# Semantic HeaderDoc Rubric for Node #965 (Network Core)

This rubric defines acceptance criteria for upgrading file-level HeaderDoc comments from boilerplate to meaningful technical documentation.

## Required fields
Each target file must include:
- `@file` matching basename
- `@abstract` (1 sentence, concrete responsibility)
- `@discussion` (2–6 lines, implementation-relevant behavior)

## Quality requirements

### 1) Specific responsibility (must)
`@abstract` must name the file’s concrete role, e.g. parser, route registration pack, retry policy, SSRF validator.

### 2) Behavioral detail (must)
`@discussion` must describe at least one concrete behavior:
- parser state/error handling
- route registration scope
- retry decision semantics
- security guard boundaries
- queueing/streaming contract

### 3) Boundary clarity (must)
Document what the file does **not** own when relevant (e.g., transport vs auth, route registration vs business logic).

### 4) No misleading claims (must)
Comments must match current code behavior and avoid stale references to removed components.

### 5) Anti-boilerplate threshold (must)
- No shared `@abstract` text across unrelated file roles.
- Shared phrasing is allowed only for same-role families and must still include role-specific detail.

## Disallowed patterns
- Generic `@abstract` such as “Network core component.”
- Generic `@discussion` that could apply to any file.
- Marketing/subjective language.
- TODO-style placeholders in final comments.

## Role-specific guidance

### Parsing / protocol files
Mention parse model, error signaling, and protocol assumptions.

### Routing / dispatch files
Mention routing precedence, matching strategy, and dispatch ownership.

### Policy/security files
Mention threat/policy boundary and decision criteria (e.g., SSRF public-IP checks, retry eligibility).

### Route packs
Mention endpoint namespace and registration intent only (not service business logic internals).

### Transport/session files
Mention connection lifecycle, I/O flow, and timeout/backpressure interactions where applicable.

## Review checklist
- [ ] `@abstract` is role-specific
- [ ] `@discussion` includes concrete behavior
- [ ] boundaries are clear
- [ ] no stale/misleading claims
- [ ] no generic boilerplate text
- [ ] wording is direct and technical
