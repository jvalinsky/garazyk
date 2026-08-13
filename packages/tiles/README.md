# `@garazyk/tiles`

Deno client helpers for the [DASL Web Tiles](https://dasl.ing/tiles.html)
data protocol and mothership `resolve-path` mediation.

This package complements the ObjC Admin UI host:

| Concern | ObjC | Deno |
| --- | --- | --- |
| postMessage actions | `UITileDataProtocol` | `protocol.ts` |
| Unique-origin host / CSP | `UITileLoadingHost` | (host only) |
| resolve-path mediation | `ATProtoWebTileMothership` | `MothershipClient` + stubs |
| CAR / `.tile` wire load | `ATProtoWebTile+CAR` | logical MASL fixture map |

## Imports

```ts
import {
  demoTileFixture,
  fixtureMothershipHandler,
  isValidTilesProtocolMessage,
  MothershipClient,
  readyMessage,
} from "@garazyk/tiles";
```

## JSR publish

**Out of scope** while workstream Phase 5 publication remains deferred. Prefer
the workspace import `@garazyk/tiles` (not an upstream `@dasl/tiles` claim).

## License

Unlicense OR CC0-1.0 (see `LICENSE`).
