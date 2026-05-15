---
title: AT Protocol Lexicon Compliance
description: Status and sources for AT Protocol lexicon compliance in Garazyk PDS.
---

# AT Protocol Lexicon Compliance

Garazyk PDS maintains compliance with the AT Protocol through automated coverage reporting and integration tests.

## Lexicon Sources

- **Bluesky Social**: [github.com/bluesky-social/atproto](https://github.com/bluesky-social/atproto)
- **Local Namespace**: `whitewind` (custom local lexicons)

## Verification

- **XRPC Coverage**: Verified by `scripts/docs/generate_xrpc_coverage_report.cjs`.
- **Protocol Conformance**: Validated by the `tests/AllTests` suite.

## Related Resources

- [XRPC Namespace Packs](../04-network-layer/xrpc-namespace-packs)
- [Lexicon Validation](../04-network-layer/lexicon-validation)
- [Testing Map](./testing-map)
- [Documentation Map](documentation-map.md)
