---
title: Documentation Update Checklist
---

# Documentation Update Checklist

Documentation must stay synchronized with code changes. Use this checklist for every PR.

## When to Update

- **API Changes:** New or modified XRPC endpoints.
- **Service Layer:** New services or modified service APIs.
- **Persistence:** Database schema changes or new migrations.
- **Security:** Changes to auth, rotation, or identity resolution.
- **Infrastructure:** Configuration or build process updates.

## Pre-Commit Checklist

### 1. Code & Examples
- [ ] Examples reflect current API signatures.
- [ ] Line references to source files are accurate.
- [ ] Code snippets follow the standard format (with source file paths).

### 2. Technical Accuracy
- [ ] Architecture diagrams match current component structure.
- [ ] Service interaction patterns are up-to-date.
- [ ] [Glossary](GLOSSARY) terms are consistent with the implementation.

### 3. Verification
- [ ] Internal links work (run `deno run -A scripts/test/test-doc-links.ts`).
- [ ] Site builds without errors (`npm run docs:build`).
- [ ] Critical [Diagrams](12-diagrams/index) reflect architectural changes.

## Update Process

1. **Identify:** Grep for references to changed components in `docs/`.
2. **Revise:** Update prose and code examples.
3. **Diagrams:** Modify SVGs in `docs/12-diagrams/` if architecture changed.
4. **Cross-Link:** Ensure new concepts link to the [Glossary](GLOSSARY) or related guides.

## PR Submission

Include a summary of documentation changes in your PR description:
```markdown
## Documentation Updates
- Updated [API Reference](11-reference/api-reference) for new `com.atproto.*` endpoint.
- Adjusted [System Architecture](12-diagrams/index#system-architecture) diagram.
- Added migration steps to [Migration Strategy](05-database-layer/migration-strategy).
```

## Related

- [Maintenance Guide](MAINTENANCE)
- [Versioning Strategy](VERSIONING_STRATEGY)
- [Testing Guide](TESTING)
