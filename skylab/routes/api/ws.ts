// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract WebSocket /skylab/api/ws
 * @discussion Bidirectional command channel between test harness and browser.
 *
 * Protocol:
 * - Harness → Browser: {"type": "execute", "id": "...", "method": "...", ...}
 * - Browser → Harness: {"type": "result", "id": "...", "status": "success", "data": ...}
 * - Browser → Harness: {"type": "event", "event": "...", ...}
 * - Browser → Harness: {"type": "state_update", "state": {...}}
 * - Harness → Browser: {"type": "auth_update", "auth": {...}}
 * - Harness → Browser: {"type": "reset"}
 */

import { Handlers } from "$fresh/server.ts";
import {
  recordEvent,
  registerClient,
  resolveCommand,
  unregisterClient,
  updateState,
} from "../../services/control_bridge.ts";

export const handler: Handlers = {
  GET(req: Request) {
    // Upgrade the HTTP connection to WebSocket
    const { response, socket } = Deno.upgradeWebSocket(req);

    let clientId = "";

    socket.onopen = () => {
      clientId = registerClient(socket);
      console.log(`[skylab] Browser client connected: ${clientId}`);
    };

    socket.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data as string);
        const msgType = msg.type;

        if (msgType === "result") {
          // Response to a pending command
          const cmdId = msg.id;
          if (cmdId) {
            resolveCommand(cmdId, msg);
          }
        } else if (msgType === "event") {
          // Browser event (post created, message received, etc.)
          recordEvent(msg.event || {});
        } else if (msgType === "state_update") {
          // Browser pushing state changes
          const state = msg.state || {};
          updateState(state);
        }
      } catch {
        // Ignore parse errors
      }
    };

    socket.onclose = () => {
      if (clientId) {
        unregisterClient(clientId);
        console.log(`[skylab] Browser client disconnected: ${clientId}`);
      }
    };

    socket.onerror = () => {
      // Error is handled by onclose
    };

    return response;
  },
};
