# Content Updater Module

This module documents `content-updater.js`, which rewrites markdown content during doc migrations.

## Responsibilities

- Update cross-references after file moves.
- Rewrite relative markdown links safely.
- Preserve link anchors while changing path segments.

## Usage

```bash
node scripts/docs/lib/content-updater.js
```

## Related

- [Migration Mapping](./README-migration-mapping.md)
- [Link Parser](./README-link-parser.md)
- [Path Resolver](./README-path-resolver.md)
- [Git Operations](./README-git-operations.md)
