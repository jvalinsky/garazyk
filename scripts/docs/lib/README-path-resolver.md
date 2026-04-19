# Path Resolver Module

This module documents `path-resolver.js`, which computes target paths when documentation files move.

## Responsibilities

- Resolve relative and absolute markdown paths.
- Compute stable relative links after migration.
- Provide normalization helpers for tooling scripts.

## Usage

```bash
node scripts/docs/lib/path-resolver.js
```

## Related

- [Migration Mapping](./README-migration-mapping.md)
- [Content Updater](./README-content-updater.md)
- [Link Parser](./README-link-parser.md)
