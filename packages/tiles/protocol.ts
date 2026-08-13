// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

/**
 * Web Tiles data-protocol message shapes (mirrors ObjC `UITileDataProtocol`).
 *
 * @see https://dasl.ing/tp-data.html
 * @module
 */

/** Tile → parent: ready to receive data. */
export const TILES_PROTOCOL_UP_DATA_READY = "tiles-protocol-up-data-ready";

/** Tile → parent: payload. */
export const TILES_PROTOCOL_UP_DATA_PAYLOAD = "tiles-protocol-up-data-payload";

/** Parent → tile: payload. */
export const TILES_PROTOCOL_DOWN_DATA_PAYLOAD =
  "tiles-protocol-down-data-payload";

export type TilesProtocolReadyMessage = {
  action: typeof TILES_PROTOCOL_UP_DATA_READY;
};

export type TilesProtocolUpPayloadMessage = {
  action: typeof TILES_PROTOCOL_UP_DATA_PAYLOAD;
  payload: unknown;
};

export type TilesProtocolDownPayloadMessage = {
  action: typeof TILES_PROTOCOL_DOWN_DATA_PAYLOAD;
  payload: unknown;
};

export type TilesProtocolMessage =
  | TilesProtocolReadyMessage
  | TilesProtocolUpPayloadMessage
  | TilesProtocolDownPayloadMessage;

/**
 * Validates a structured-clone tiles-protocol envelope.
 *
 * @param message Candidate message object.
 * @param fromHost When true, only the down-payload action is accepted.
 */
export function isValidTilesProtocolMessage(
  message: unknown,
  fromHost: boolean,
): message is TilesProtocolMessage {
  if (message === null || typeof message !== "object") return false;
  const action = (message as { action?: unknown }).action;
  if (typeof action !== "string") return false;
  const hasPayload = Object.prototype.hasOwnProperty.call(message, "payload");

  if (fromHost) {
    return action === TILES_PROTOCOL_DOWN_DATA_PAYLOAD && hasPayload;
  }
  if (action === TILES_PROTOCOL_UP_DATA_READY) {
    return !hasPayload;
  }
  if (action === TILES_PROTOCOL_UP_DATA_PAYLOAD) {
    return hasPayload;
  }
  return false;
}

/** Build a ready message (tile → host). */
export function readyMessage(): TilesProtocolReadyMessage {
  return { action: TILES_PROTOCOL_UP_DATA_READY };
}

/** Build an up-payload message (tile → host). */
export function upPayloadMessage(
  payload: unknown,
): TilesProtocolUpPayloadMessage {
  return { action: TILES_PROTOCOL_UP_DATA_PAYLOAD, payload };
}

/** Build a down-payload message (host → tile). */
export function downPayloadMessage(
  payload: unknown,
): TilesProtocolDownPayloadMessage {
  return { action: TILES_PROTOCOL_DOWN_DATA_PAYLOAD, payload };
}
