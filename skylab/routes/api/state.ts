// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract GET/POST /skylab/api/state
 * @discussion Get or update the client state snapshot.
 */

import { Handlers } from "$fresh/server.ts";
import {
  getState,
  updateState,
} from "../../services/control_bridge.ts";

export const handler: Handlers = {
  GET() {
    return Response.json(getState());
  },

  async POST(req) {
    const body = await req.json();
    updateState(body);
    return Response.json({ ok: true });
  },
};
