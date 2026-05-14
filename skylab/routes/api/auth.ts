// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract POST /skylab/api/auth
 * @discussion Set auth tokens (for pre-authenticated test scenarios).
 * Forwards auth_update to all connected browser clients.
 */

import { Handlers } from "$fresh/server.ts";
import {
  updateState,
  broadcastToBrowsers,
} from "../../services/control_bridge.ts";

export const handler: Handlers = {
  async POST(req) {
    const body = await req.json();
    updateState({ auth: body });

    // Forward to connected browsers
    broadcastToBrowsers({ type: "auth_update", auth: body });

    return Response.json({ ok: true });
  },
};
