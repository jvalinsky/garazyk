// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract GET/POST /skylab/api/events
 * @discussion Get event log or record a new event from the browser.
 */

import { Handlers } from "$fresh/server.ts";
import {
  getEvents,
  getEventCount,
  recordEvent,
} from "../../services/control_bridge.ts";

export const handler: Handlers = {
  GET() {
    const events = getEvents();
    return Response.json({ events, total: getEventCount() });
  },

  async POST(req) {
    const body = await req.json();
    const entry = recordEvent(body);
    return Response.json({ ok: true, seq: entry.seq });
  },
};
