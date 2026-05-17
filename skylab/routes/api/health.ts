// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract GET /skylab/api/health
 * @discussion Health check endpoint returning server status.
 */

import { Handlers } from "$fresh/server.ts";
import { SERVICE_URLS } from "../../services/config.ts";
import { getBrowserClientCount, getEventCount } from "../../services/control_bridge.ts";

export const handler: Handlers = {
  GET() {
    return Response.json({
      status: "ok",
      browsers_connected: getBrowserClientCount(),
      events_logged: getEventCount(),
      services: { ...SERVICE_URLS },
    });
  },
};
