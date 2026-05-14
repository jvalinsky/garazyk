// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract POST /skylab/api/reset
 * @discussion Clear all client state and event log.
 * Forwards reset to all connected browser clients.
 */

import { Handlers } from "$fresh/server.ts";
import {
  resetState,
  clearEvents,
  broadcastToBrowsers,
} from "../../services/control_bridge.ts";

export const handler: Handlers = {
  POST() {
    resetState();
    clearEvents();

    // Forward to connected browsers
    broadcastToBrowsers({ type: "reset" });

    return Response.json({ ok: true });
  },
};
