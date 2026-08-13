// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

/**
 * In-memory MASL-style tile resource map + mothership stub.
 *
 * Full CAR/wire decode stays on the ObjC mothership; this package exercises the
 * protocol and resolve-path client against a golden logical fixture.
 *
 * @module
 */

import type {
  MothershipHandler,
  MothershipReply,
  TilePathResponse,
} from "./mothership.ts";

/** One declared tile resource. */
export type TileResource = {
  "content-type": string;
  body: string;
};

/** Logical Web Tile fixture (MASL resources map without CAR framing). */
export type TileFixture = {
  name: string;
  resources: Record<string, TileResource>;
};

import fixtureJson from "./fixtures/demo_tile.json" with { type: "json" };

/** Golden demo tile used by unit tests. */
export const demoTileFixture: TileFixture = fixtureJson as TileFixture;

/**
 * Resolve a path against a logical tile fixture (query/fragment stripped).
 */
export function resolveFixturePath(
  fixture: TileFixture,
  path: string,
): TilePathResponse {
  const clean = path.split("?")[0]?.split("#")[0] ?? path;
  const resource = fixture.resources[clean];
  if (!resource) {
    return { status: 404, headers: {}, body: "" };
  }
  return {
    status: 200,
    headers: { "content-type": resource["content-type"] },
    body: resource.body,
  };
}

/** In-process mothership over a logical fixture. */
export function fixtureMothershipHandler(
  fixture: TileFixture = demoTileFixture,
): MothershipHandler {
  return (request): MothershipReply => {
    const requestId = request["requestId"] as string | number | undefined;
    if (request["type"] !== "resolve-path") {
      const err: MothershipReply = { error: "unknown request type" };
      if (requestId !== undefined) {
        (err as { requestId?: string | number }).requestId = requestId;
      }
      return err;
    }
    const path = request["path"];
    if (typeof path !== "string") {
      const err: MothershipReply = { error: "path required" };
      if (requestId !== undefined) {
        (err as { requestId?: string | number }).requestId = requestId;
      }
      return err;
    }
    const response = resolveFixturePath(fixture, path);
    const ok: MothershipReply = { response };
    if (requestId !== undefined) {
      (ok as { requestId?: string | number }).requestId = requestId;
    }
    return ok;
  };
}
