// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

import { assert, assertEquals, assertFalse } from "@std/assert";
import {
  demoTileFixture,
  downPayloadMessage,
  fixtureMothershipHandler,
  isValidTilesProtocolMessage,
  MothershipClient,
  readyMessage,
  resolveFixturePath,
  TILES_PROTOCOL_DOWN_DATA_PAYLOAD,
  TILES_PROTOCOL_UP_DATA_PAYLOAD,
  TILES_PROTOCOL_UP_DATA_READY,
  upPayloadMessage,
} from "./mod.ts";

Deno.test("protocol: ready / up / down message shapes", () => {
  assert(isValidTilesProtocolMessage(readyMessage(), false));
  assertFalse(isValidTilesProtocolMessage(readyMessage(), true));
  assert(
    isValidTilesProtocolMessage(upPayloadMessage({ hello: 1 }), false),
  );
  assertFalse(isValidTilesProtocolMessage(upPayloadMessage({ hello: 1 }), true));
  assert(
    isValidTilesProtocolMessage(downPayloadMessage("x"), true),
  );
  assertFalse(
    isValidTilesProtocolMessage(downPayloadMessage("x"), false),
  );
  assertFalse(
    isValidTilesProtocolMessage(
      { action: TILES_PROTOCOL_UP_DATA_READY, payload: 1 },
      false,
    ),
  );
  assertFalse(
    isValidTilesProtocolMessage(
      { action: TILES_PROTOCOL_UP_DATA_PAYLOAD },
      false,
    ),
  );
  assertEquals(
    TILES_PROTOCOL_DOWN_DATA_PAYLOAD,
    "tiles-protocol-down-data-payload",
  );
});

Deno.test("fixture: resolve / and nested /app.js", () => {
  const root = resolveFixturePath(demoTileFixture, "/");
  assertEquals(root.status, 200);
  assert(String(root.body).includes("Demo Tile"));

  const js = resolveFixturePath(demoTileFixture, "/app.js");
  assertEquals(js.status, 200);
  assert(String(js.body).includes("garazyk-demo-tile"));

  const missing = resolveFixturePath(demoTileFixture, "/nope");
  assertEquals(missing.status, 404);
});

Deno.test("mothership client: stub resolve-path echoes requestId", async () => {
  const client = new MothershipClient(fixtureMothershipHandler());
  const ok = await client.resolvePath("/app.js", 42);
  assertEquals((ok as { requestId: number }).requestId, 42);
  assertEquals((ok as { response: { status: number } }).response.status, 200);

  const bad = await fixtureMothershipHandler()({ type: "ping", requestId: 9 });
  assertEquals((bad as { error: string }).error, "unknown request type");
  assertEquals((bad as { requestId: number }).requestId, 9);
});
