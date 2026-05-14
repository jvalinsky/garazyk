// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/**
 * SkyLab XrpcBridge — Service-aware XRPC client with auth, event bus,
 * and Control Bridge integration.
 *
 * Routes XRPC calls to the correct service (PDS for writes, AppView for
 * reads, Chat for DMs, Video for uploads, Germ for E2EE). Manages JWT
 * and DPoP auth. Provides an event bus for reactive UI panels.
 */

// ============================================================================
// Service Routing
// ============================================================================

const METHOD_ROUTES = {
    'chat.bsky': 'chat',
    'app.bsky.video': 'video',
    'com.germnetwork': 'germ',
};

const APPVIEW_READ_METHODS = new Set([
    'app.bsky.feed.getTimeline',
    'app.bsky.feed.getAuthorFeed',
    'app.bsky.feed.getPostThread',
    'app.bsky.feed.getLikes',
    'app.bsky.feed.getRepostedBy',
    'app.bsky.feed.getPosts',
    'app.bsky.feed.getActorLikes',
    'app.bsky.feed.getFeed',
    'app.bsky.feed.getFeedGenerator',
    'app.bsky.feed.getFeedGenerators',
    'app.bsky.feed.getSuggestions',
    'app.bsky.actor.getProfile',
    'app.bsky.actor.getProfiles',
    'app.bsky.actor.searchActors',
    'app.bsky.actor.searchActorsTypeahead',
    'app.bsky.graph.getFollows',
    'app.bsky.graph.getFollowers',
    'app.bsky.graph.getBlocks',
    'app.bsky.graph.getMutes',
    'app.bsky.graph.getRelationships',
    'app.bsky.graph.getStarterPack',
    'app.bsky.graph.getActorStarterPacks',
    'app.bsky.graph.getStarterPacks',
    'app.bsky.graph.getList',
    'app.bsky.graph.getLists',
    'app.bsky.graph.getListMutes',
    'app.bsky.notification.listNotifications',
    'app.bsky.notification.getUnreadCount',
    'app.bsky.unspecced.searchActorsSkeleton',
    'app.bsky.unspecced.searchPostsSkeleton',
    'app.bsky.unspecced.searchStarterPacksSkeleton',
]);

/**
 * Lexicon `query` methods are invoked with HTTP GET and query-string params.
 * The NSID ends with a segment such as getTimeline or listNotifications — not
 * a prefix on the full NSID (e.g. app.bsky.feed.getTimeline starts with "app").
 */
function xrpcMethodUsesHttpGet(method) {
    if (!method || typeof method !== 'string') return false;
    const seg = method.includes('.') ? method.slice(method.lastIndexOf('.') + 1) : method;
    const s = seg.toLowerCase();
    if (s.startsWith('get') || s.startsWith('list') || s.startsWith('search') || s.startsWith('describe')) {
        return true;
    }
    if (s.startsWith('resolve') && s !== 'resolvereport') {
        return true;
    }
    return false;
}

// ============================================================================
// SkyLabBridge
// ============================================================================

class SkyLabBridge {
    /**
     * @param {Object} config
     * @param {Object} config.services - Service URL map { pds, appview, chat, video, germ, relay, plc }
     * @param {boolean} [config.useProxy=true] - Use CORS proxy instead of direct service URLs
     * @param {string} [config.proxyBase='/skylab/proxy'] - CORS proxy base path
     * @param {string} [config.controlBridgeUrl] - WebSocket URL for control bridge
     */
    constructor(config = {}) {
        this.services = config.services || {};
        this.useProxy = config.useProxy !== false;
        this.proxyBase = config.proxyBase || '/skylab/proxy';
        this.controlBridgeUrl = config.controlBridgeUrl ||
            `ws://${window.location.host}/skylab/api/ws`;

        // Auth state
        this.auth = null; // { accessJwt, refreshJwt, did, handle, email }

        // Event bus
        this._listeners = {};

        // Firehose
        this._firehose = null;
        this._firehoseSeq = 0;

        // Control bridge
        this._controlWs = null;
        this._pendingCommands = {};
        this._cmdCounter = 0;

        // State snapshot (pushed to server periodically)
        this.state = {
            auth: null,
            profile: null,
            timeline: [],
            chats: [],
            firehose: { connected: false, seq: 0 },
        };
    }

    // ========================================================================
    // Service Routing
    // ========================================================================

    /**
     * Determine which service handles a given XRPC method.
     */
    routeMethod(method) {
        for (const [prefix, service] of Object.entries(METHOD_ROUTES)) {
            if (method.startsWith(prefix)) return service;
        }
        if (APPVIEW_READ_METHODS.has(method)) return 'appview';
        return 'pds';
    }

    /**
     * Get the base URL for a service, using proxy if configured.
     */
    serviceUrl(service) {
        if (this.useProxy) {
            return `${this.proxyBase}/${service}`;
        }
        return this.services[service] || this.services.pds;
    }

    // ========================================================================
    // Auth
    // ========================================================================

    /**
     * Login with handle/email and password (createSession).
     */
    async login(identifier, password) {
        const resp = await this.xrpc('com.atproto.server.createSession', null, {
            identifier,
            password,
        }, { service: 'pds' });

        if (resp.ok) {
            this.auth = {
                accessJwt: resp.data.accessJwt,
                refreshJwt: resp.data.refreshJwt,
                did: resp.data.did,
                handle: resp.data.handle,
                email: resp.data.email,
            };
            this.state.auth = this.auth;
            this.emit('auth_change', this.auth);
            this._pushState();
            await this.loadProfile();
        }
        return resp;
    }

    /**
     * Logout (deleteSession).
     */
    async logout() {
        if (this.auth) {
            await this.xrpc('com.atproto.server.deleteSession', null, null, {
                service: 'pds',
                auth: true,
            });
        }
        this.auth = null;
        this.state.auth = null;
        this.state.profile = null;
        this.emit('auth_change', null);
        this._pushState();
    }

    /**
     * Refresh the access token.
     */
    async refreshSession() {
        if (!this.auth?.refreshJwt) return;
        const resp = await this.xrpc('com.atproto.server.refreshSession', null, null, {
            service: 'pds',
            auth: 'refresh',
        });
        if (resp.ok) {
            this.auth.accessJwt = resp.data.accessJwt;
            this.auth.refreshJwt = resp.data.refreshJwt;
            this.state.auth = this.auth;
            this.emit('auth_change', this.auth);
            this._pushState();
        }
        return resp;
    }

    /**
     * Load current user profile.
     */
    async loadProfile() {
        if (!this.auth?.did) return;
        const resp = await this.xrpc('app.bsky.actor.getProfile', {
            actor: this.auth.did,
        }, null, { service: 'appview', auth: true });
        if (resp.ok) {
            this.state.profile = resp.data;
            this.emit('profile_update', resp.data);
            this._pushState();
        }
        return resp;
    }

    // ========================================================================
    // XRPC
    // ========================================================================

    /**
     * Execute an XRPC call.
     *
     * @param {string} method - NSID method name (e.g. 'app.bsky.feed.getTimeline')
     * @param {Object|null} params - Query parameters (for queries)
     * @param {Object|null} body - Request body (for procedures)
     * @param {Object} options
     * @param {string} [options.service] - Override service routing
     * @param {boolean} [options.auth=false] - Include Authorization header
     * @param {string} [options.auth='refresh'] - Use refresh token
     * @returns {Promise<{ok: boolean, status: number, data: any, headers: Headers}>}
     */
    async xrpc(method, params = null, body = null, options = {}) {
        const service = options.service || this.routeMethod(method);
        const baseUrl = this.serviceUrl(service);
        const isQuery = xrpcMethodUsesHttpGet(method);

        let url;
        if (isQuery && !body) {
            const queryStr = params ? '?' + new URLSearchParams(params).toString() : '';
            url = `${baseUrl}/xrpc/${method}${queryStr}`;
        } else {
            url = `${baseUrl}/xrpc/${method}`;
        }

        const headers = { 'Content-Type': 'application/json' };

        // Auth
        if (options.auth || options.auth === '') {
            if (options.auth === 'refresh' && this.auth?.refreshJwt) {
                headers['Authorization'] = `Bearer ${this.auth.refreshJwt}`;
            } else if (this.auth?.accessJwt) {
                headers['Authorization'] = `Bearer ${this.auth.accessJwt}`;
            }
        }

        const fetchOptions = {
            method: (isQuery && !body) ? 'GET' : 'POST',
            headers,
        };

        if (body || (!isQuery && params)) {
            fetchOptions.body = JSON.stringify(body || params);
        }

        try {
            const response = await fetch(url, fetchOptions);
            let data = null;
            const contentType = response.headers.get('content-type') || '';
            if (contentType.includes('application/json')) {
                data = await response.json();
            } else {
                data = await response.text();
            }

            const result = {
                ok: response.ok,
                status: response.status,
                data,
                headers: Object.fromEntries(response.headers.entries()),
            };

            // Emit event for UI
            this.emit('xrpc_response', { method, service, result });

            return result;
        } catch (error) {
            const result = {
                ok: false,
                status: 0,
                data: { error: 'network_error', message: error.message },
                headers: {},
            };
            this.emit('xrpc_error', { method, service, error: error.message });
            return result;
        }
    }

    // ========================================================================
    // Firehose
    // ========================================================================

    /**
     * Subscribe to the firehose via WebSocket.
     */
    subscribeFirehose(service = 'relay') {
        const wsUrl = this.services[service] || this.services.relay;
        const wsProtocol = wsUrl.replace(/^http/, 'ws');
        const url = `${wsProtocol}/xrpc/com.atproto.sync.subscribeRepos`;

        this._firehose = new WebSocket(url);
        this._firehose.binaryType = 'arraybuffer';

        this._firehose.onopen = () => {
            this.state.firehose.connected = true;
            this.emit('firehose_open', {});
            this._pushState();
        };

        this._firehose.onmessage = (event) => {
            this._firehoseSeq++;
            this.state.firehose.seq = this._firehoseSeq;

            // Parse the frame (header + payload)
            try {
                const data = event.data;
                if (data instanceof ArrayBuffer) {
                    // Binary frame — CBOR/CAR format
                    this.emit('firehose_frame', {
                        seq: this._firehoseSeq,
                        type: 'binary',
                        size: data.byteLength,
                        raw: data,
                    });
                } else {
                    // Text frame (unlikely for subscribeRepos, but handle it)
                    this.emit('firehose_frame', {
                        seq: this._firehoseSeq,
                        type: 'text',
                        data: data,
                    });
                }
            } catch (e) {
                // Ignore parse errors
            }
        };

        this._firehose.onclose = () => {
            this.state.firehose.connected = false;
            this.emit('firehose_close', {});
            this._pushState();
        };

        this._firehose.onerror = (error) => {
            this.emit('firehose_error', { error });
        };
    }

    /**
     * Unsubscribe from the firehose.
     */
    unsubscribeFirehose() {
        if (this._firehose) {
            this._firehose.close();
            this._firehose = null;
        }
    }

    // ========================================================================
    // Control Bridge (WebSocket to Python test harness)
    // ========================================================================

    /**
     * Connect to the Control Bridge WebSocket.
     */
    connectControlBridge() {
        this._controlWs = new WebSocket(this.controlBridgeUrl);

        this._controlWs.onopen = () => {
            this.emit('control_bridge_open', {});
        };

        this._controlWs.onmessage = (event) => {
            try {
                const msg = JSON.parse(event.data);
                this._handleControlMessage(msg);
            } catch (e) {
                // Ignore parse errors
            }
        };

        this._controlWs.onclose = () => {
            this.emit('control_bridge_close', {});
            // Auto-reconnect after 3s
            setTimeout(() => this.connectControlBridge(), 3000);
        };

        this._controlWs.onerror = () => {
            // Error is handled by onclose
        };
    }

    /**
     * Handle incoming control bridge message.
     */
    async _handleControlMessage(msg) {
        const type = msg.type;

        if (type === 'execute') {
            // Python harness wants us to execute an XRPC call
            const result = await this.xrpc(msg.method, msg.params, msg.body, {
                service: msg.service,
                auth: true,
            });

            // Send result back
            this._controlWs.send(JSON.stringify({
                type: 'result',
                id: msg.id,
                status: result.ok ? 'success' : 'error',
                data: result.data,
                statusCode: result.status,
            }));
        } else if (type === 'auth_update') {
            // Python harness set auth tokens
            this.auth = msg.auth;
            this.state.auth = this.auth;
            this.emit('auth_change', this.auth);
        } else if (type === 'reset') {
            this.auth = null;
            this.state = {
                auth: null, profile: null, timeline: [],
                chats: [], firehose: { connected: false, seq: 0 },
            };
            this.emit('reset', {});
        }
    }

    // ========================================================================
    // Event Bus
    // ========================================================================

    /**
     * Subscribe to an event.
     * @param {string} event
     * @param {Function} callback
     * @returns {Function} Unsubscribe function
     */
    on(event, callback) {
        if (!this._listeners[event]) {
            this._listeners[event] = [];
        }
        this._listeners[event].push(callback);
        return () => {
            this._listeners[event] = this._listeners[event].filter(cb => cb !== callback);
        };
    }

    /**
     * Emit an event.
     * @param {string} event
     * @param {*} data
     */
    emit(event, data) {
        if (this._listeners[event]) {
            for (const cb of this._listeners[event]) {
                try { cb(data); } catch (e) { console.error('Event handler error:', e); }
            }
        }

        // Record event on server
        this._recordEvent(event, data);

        // Forward to control bridge
        if (this._controlWs?.readyState === WebSocket.OPEN) {
            try {
                this._controlWs.send(JSON.stringify({
                    type: 'event',
                    event: { type: event, data },
                }));
            } catch (e) {
                // Ignore
            }
        }
    }

    // ========================================================================
    // State Management
    // ========================================================================

    /**
     * Push current state to the server.
     */
    async _pushState() {
        try {
            await fetch('/skylab/api/state', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(this.state),
            });
        } catch (e) {
            // Ignore — server may not be running
        }
    }

    /**
     * Record an event on the server.
     */
    async _recordEvent(event, data) {
        try {
            await fetch('/skylab/api/events', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type: event, data }),
            });
        } catch (e) {
            // Ignore
        }
    }

    /**
     * Get the current state snapshot (for test assertions).
     */
    getState() {
        return { ...this.state };
    }
}

// ============================================================================
// Export
// ============================================================================

// Make available globally for standalone HTML usage
if (typeof window !== 'undefined') {
    window.SkyLabBridge = SkyLabBridge;
}

// ES module export
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { SkyLabBridge };
}
