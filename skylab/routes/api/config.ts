// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract GET /skylab/api/config
 * @discussion Return service URLs and configuration to the browser client.
 */

import { Handlers } from "$fresh/server.ts";
import {
  APPVIEW_READ_METHODS,
  METHOD_ROUTES,
  SERVICE_URLS,
  VIDEO_SERVICE_DID,
} from "../../services/config.ts";

export const handler: Handlers = {
  GET() {
    return Response.json({
      services: SERVICE_URLS,
      videoServiceDid: VIDEO_SERVICE_DID,
      methodRoutes: METHOD_ROUTES,
      appviewReadMethods: [...APPVIEW_READ_METHODS],
    });
  },
};
