// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

/**
 * `@garazyk/tiles` — Web Tiles protocol + mothership client for Deno.
 *
 * Complements the ObjC Admin UI host (`UITileDataProtocol`,
 * `ATProtoWebTileMothership`). JSR publish is out of scope while Phase 5
 * publication remains deferred.
 *
 * @module
 */

export {
  downPayloadMessage,
  isValidTilesProtocolMessage,
  readyMessage,
  TILES_PROTOCOL_DOWN_DATA_PAYLOAD,
  TILES_PROTOCOL_UP_DATA_PAYLOAD,
  TILES_PROTOCOL_UP_DATA_READY,
  upPayloadMessage,
} from "./protocol.ts";
export type {
  TilesProtocolDownPayloadMessage,
  TilesProtocolMessage,
  TilesProtocolReadyMessage,
  TilesProtocolUpPayloadMessage,
} from "./protocol.ts";

export {
  httpMothershipHandler,
  MothershipClient,
} from "./mothership.ts";
export type {
  MothershipError,
  MothershipHandler,
  MothershipReply,
  MothershipSuccess,
  ResolvePathRequest,
  TilePathResponse,
} from "./mothership.ts";

export {
  demoTileFixture,
  fixtureMothershipHandler,
  resolveFixturePath,
} from "./fixture.ts";
export type { TileFixture, TileResource } from "./fixture.ts";
