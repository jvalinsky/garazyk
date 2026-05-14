// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * @abstract Control Bridge shared state
 * @discussion Manages browser WebSocket clients, pending commands,
 * event log, and client state snapshot. This is the single source of
 * truth for all Control Bridge operations, mirroring the Python
 * server.py module-level globals.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface BrowserClient {
  id: string;
  socket: WebSocket;
}

export interface PendingCommand {
  resolve: (result: unknown) => void;
  reject: (error: Error) => void;
  timer: number;
}

export interface EventLogEntry {
  seq: number;
  timestamp: number;
  [key: string]: unknown;
}

export interface ClientState {
  auth: unknown | null;
  profile: unknown | null;
  timeline: unknown[];
  chats: unknown[];
  firehose: {
    connected: boolean;
    seq: number;
  };
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let _clientIdCounter = 0;

/** Connected browser clients */
const browserClients: BrowserClient[] = [];

/** Pending commands awaiting responses from browser */
const pendingCommands: Map<string, PendingCommand> = new Map();

/** Event log (circular buffer, last 1000 events) */
const eventLog: EventLogEntry[] = [];
const EVENT_LOG_MAX = 1000;

/** Client state snapshot */
let clientState: ClientState = {
  auth: null,
  profile: null,
  timeline: [],
  chats: [],
  firehose: { connected: false, seq: 0 },
};

// ---------------------------------------------------------------------------
// Browser client management
// ---------------------------------------------------------------------------

/**
 * Register a new browser WebSocket client.
 * @returns The client ID string.
 */
export function registerClient(socket: WebSocket): string {
  const id = `ws-${++_clientIdCounter}-${Date.now()}`;
  const client: BrowserClient = { id, socket };
  browserClients.push(client);
  return id;
}

/**
 * Unregister a browser client. Cancels any pending commands.
 */
export function unregisterClient(id: string): void {
  const idx = browserClients.findIndex((c) => c.id === id);
  if (idx !== -1) {
    browserClients.splice(idx, 1);
  }

  // Cancel any pending commands for this client
  for (const [cmdId, pending] of pendingCommands.entries()) {
    if (!pending.resolve) continue;
    clearTimeout(pending.timer);
    pending.reject(new Error("Browser client disconnected"));
    pendingCommands.delete(cmdId);
  }
}

/**
 * Get the number of connected browser clients.
 */
export function getBrowserClientCount(): number {
  return browserClients.length;
}

/**
 * Get the first connected browser client (if any).
 */
export function getFirstBrowserClient(): BrowserClient | undefined {
  return browserClients[0];
}

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------

const COMMAND_TIMEOUT_MS = 30_000;

/**
 * Dispatch a command to the first connected browser client.
 * Returns a promise that resolves with the browser's result.
 * Rejects on timeout or if no browser is connected.
 */
export function dispatchCommand(
  cmd: { type: string; id?: string; method?: string; params?: unknown; body?: unknown; service?: string },
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const client = getFirstBrowserClient();
    if (!client) {
      reject(new Error("No browser client connected"));
      return;
    }

    const cmdId = cmd.id || `cmd-${Date.now()}-${++_clientIdCounter}`;
    const fullCmd = { ...cmd, type: "execute", id: cmdId };

    const timer = setTimeout(() => {
      pendingCommands.delete(cmdId);
      reject(new Error("Browser did not respond within 30s"));
    }, COMMAND_TIMEOUT_MS);

    pendingCommands.set(cmdId, { resolve, reject, timer });

    try {
      client.socket.send(JSON.stringify(fullCmd));
    } catch (err) {
      clearTimeout(timer);
      pendingCommands.delete(cmdId);
      reject(new Error(`Failed to send command to browser: ${err}`));
    }
  });
}

/**
 * Resolve a pending command with a result from the browser.
 */
export function resolveCommand(cmdId: string, result: unknown): void {
  const pending = pendingCommands.get(cmdId);
  if (pending) {
    clearTimeout(pending.timer);
    pending.resolve(result);
    pendingCommands.delete(cmdId);
  }
}

// ---------------------------------------------------------------------------
// Event log
// ---------------------------------------------------------------------------

/**
 * Record an event in the circular event log.
 */
export function recordEvent(event: Record<string, unknown>): EventLogEntry {
  const entry: EventLogEntry = {
    seq: eventLog.length + 1,
    timestamp: Date.now() / 1000,
    ...event,
  };
  eventLog.push(entry);
  if (eventLog.length > EVENT_LOG_MAX) {
    eventLog.shift();
  }
  return entry;
}

/**
 * Get the event log, optionally filtered by sequence number.
 */
export function getEvents(afterSeq = 0): EventLogEntry[] {
  if (afterSeq === 0) return [...eventLog];
  return eventLog.filter((e) => e.seq > afterSeq);
}

/**
 * Get the total number of events in the log.
 */
export function getEventCount(): number {
  return eventLog.length;
}

/**
 * Clear the event log.
 */
export function clearEvents(): void {
  eventLog.length = 0;
}

// ---------------------------------------------------------------------------
// Client state
// ---------------------------------------------------------------------------

/**
 * Get the current client state snapshot.
 */
export function getState(): ClientState {
  return { ...clientState };
}

/**
 * Update client state with a partial object.
 */
export function updateState(partial: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(partial)) {
    (clientState as Record<string, unknown>)[key] = value;
  }
}

/**
 * Reset client state to defaults.
 */
export function resetState(): void {
  clientState = {
    auth: null,
    profile: null,
    timeline: [],
    chats: [],
    firehose: { connected: false, seq: 0 },
  };
}

// ---------------------------------------------------------------------------
// Broadcast to browsers
// ---------------------------------------------------------------------------

/**
 * Send a JSON message to all connected browser clients.
 */
export function broadcastToBrowsers(message: unknown): void {
  const data = JSON.stringify(message);
  for (const client of browserClients) {
    try {
      client.socket.send(data);
    } catch {
      // Ignore send errors — client may have disconnected
    }
  }
}
