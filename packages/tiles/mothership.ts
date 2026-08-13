// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

/**
 * Mothership resolve-path client shapes (mirrors ObjC `ATProtoWebTileMothership`).
 *
 * @module
 */

/** Normative path response returned inside a successful mothership reply. */
export type TilePathResponse = {
  status: number;
  headers: Record<string, string>;
  body: Uint8Array | string;
};

export type ResolvePathRequest = {
  type: "resolve-path";
  path: string;
  requestId?: string | number;
};

export type MothershipSuccess = {
  requestId?: string | number;
  response: TilePathResponse;
};

export type MothershipError = {
  requestId?: string | number;
  error: string;
};

export type MothershipReply = MothershipSuccess | MothershipError;

/** Handler that answers mothership requests (in-process stub or HTTP adapter). */
export type MothershipHandler = (
  request: Record<string, unknown>,
) => MothershipReply | Promise<MothershipReply>;

/**
 * Client that posts resolve-path requests to a mothership handler.
 */
export class MothershipClient {
  #handler: MothershipHandler;

  constructor(handler: MothershipHandler) {
    this.#handler = handler;
  }

  /** Resolve a tile path via the mothership. */
  async resolvePath(
    path: string,
    requestId?: string | number,
  ): Promise<MothershipReply> {
    const request: ResolvePathRequest = {
      type: "resolve-path",
      path,
    };
    if (requestId !== undefined) request.requestId = requestId;
    return await this.#handler(request as unknown as Record<string, unknown>);
  }
}

/**
 * HTTP mothership adapter: POST JSON to `endpoint` (e.g. Admin UI
 * `/lab/tiles/mothership`).
 */
export function httpMothershipHandler(endpoint: string): MothershipHandler {
  return async (request) => {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(request),
    });
    if (!res.ok) {
      return { error: `mothership HTTP ${res.status}` };
    }
    return await res.json() as MothershipReply;
  };
}
