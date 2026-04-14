const OAUTH_CONFIG = {
    clientId: 'test-client',
    redirectUri: window.location.origin + '/?oauth_callback=1',
    scope: 'atproto',
    issuer: window.location.origin
};

const OAUTH_KEYS = {
    state: 'poster_oauth_state',
    codeVerifier: 'poster_code_verifier',
    accessToken: 'poster_access_token',
    sessionDid: 'poster_session_did'
};

let dpopKeyPair = null;

// --- Crypto helpers ---

function randomString(len) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    const values = new Uint32Array(len);
    crypto.getRandomValues(values);
    let out = '';
    for (let i = 0; i < len; i++) out += chars[values[i] % chars.length];
    return out;
}

function b64url(buf) {
    const bytes = new Uint8Array(buf);
    let s = '';
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlStr(str) {
    return b64url(new TextEncoder().encode(str));
}

async function sha256(plain) {
    return crypto.subtle.digest('SHA-256', new TextEncoder().encode(plain));
}

// --- DPoP ---

async function getOrCreateKey() {
    if (dpopKeyPair) return dpopKeyPair;
    dpopKeyPair = await crypto.subtle.generateKey(
        { name: 'ECDSA', namedCurve: 'P-256' },
        true, ['sign']
    );
    return dpopKeyPair;
}

async function makeDpopProof(kp, method, url, opts) {
    const header = {
        typ: 'dpop+jwt',
        alg: 'ES256',
        jwk: await crypto.subtle.exportKey('jwk', kp.publicKey)
    };
    const payload = {
        jti: randomString(16),
        htm: method.toUpperCase(),
        htu: new URL(url).origin + new URL(url).pathname,
        iat: Math.floor(Date.now() / 1000)
    };
    if (opts.nonce) payload.nonce = opts.nonce;
    if (opts.accessToken) {
        payload.ath = b64url(await sha256(opts.accessToken));
    }
    const unsigned = b64urlStr(JSON.stringify(header)) + '.' + b64urlStr(JSON.stringify(payload));
    const sig = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        kp.privateKey,
        new TextEncoder().encode(unsigned)
    );
    return unsigned + '.' + b64url(sig);
}

function nonceKey() { return 'poster_dpop_nonce'; }

function captureNonce(headers) {
    const n = headers.get('DPoP-Nonce');
    if (n) sessionStorage.setItem(nonceKey(), n);
    return n;
}

async function dpopFetch(url, init, kp, opts) {
    const method = (init.method || 'GET').toUpperCase();
    const nonce = sessionStorage.getItem(nonceKey());
    const proof = await makeDpopProof(kp, method, url, { nonce, ...opts });
    const headers = new Headers(init.headers || {});
    headers.set('DPoP', proof);
    const resp = await fetch(url, { ...init, headers });
    captureNonce(resp.headers);

    if ((resp.status === 400 || resp.status === 401) && resp.headers.get('DPoP-Nonce')) {
        const retry = await makeDpopProof(kp, method, url, {
            nonce: sessionStorage.getItem(nonceKey()), ...opts
        });
        headers.set('DPoP', retry);
        const resp2 = await fetch(url, { ...init, headers });
        captureNonce(resp2.headers);
        return resp2;
    }
    return resp;
}

// --- OAuth flow ---

export async function resolveHandle(handle) {
    if (!handle || !handle.includes('.')) return null;
    try {
        const url = new URL('/xrpc/com.atproto.identity.resolveHandle', OAUTH_CONFIG.issuer);
        url.searchParams.set('handle', handle);
        const resp = await fetch(url.href);
        if (!resp.ok) return null;
        const data = await resp.json();
        return data.did;
    } catch (e) {
        console.error('Handle resolution failed:', e);
        return null;
    }
}

export async function startLogin(handle) {
    const kp = await getOrCreateKey();
    const state = randomString(32);
    const verifier = randomString(64);
    const challenge = b64url(await sha256(verifier));

    sessionStorage.setItem(OAUTH_KEYS.state, state);
    sessionStorage.setItem(OAUTH_KEYS.codeVerifier, verifier);

    const url = new URL('/oauth/authorize', OAUTH_CONFIG.issuer);
    url.searchParams.set('client_id', OAUTH_CONFIG.clientId);
    url.searchParams.set('redirect_uri', OAUTH_CONFIG.redirectUri);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('scope', OAUTH_CONFIG.scope);
    url.searchParams.set('state', state);
    url.searchParams.set('code_challenge', challenge);
    url.searchParams.set('code_challenge_method', 'S256');
    if (handle) url.searchParams.set('login_hint', handle);

    window.location.href = url.href;
}

export async function handleOAuthCallback() {
    const params = new URLSearchParams(window.location.search);
    if (!params.get('oauth_callback')) return false;

    const code = params.get('code');
    const state = params.get('state');
    const saved = sessionStorage.getItem(OAUTH_KEYS.state);

    if (!code || state !== saved) {
        return { error: 'State mismatch or missing code' };
    }

    const kp = await getOrCreateKey();
    const verifier = sessionStorage.getItem(OAUTH_KEYS.codeVerifier);
    const tokenUrl = new URL('/oauth/token', OAUTH_CONFIG.issuer).href;

    const body = new URLSearchParams();
    body.set('grant_type', 'authorization_code');
    body.set('code', code);
    body.set('redirect_uri', OAUTH_CONFIG.redirectUri);
    body.set('client_id', OAUTH_CONFIG.clientId);
    body.set('code_verifier', verifier);

    const resp = await dpopFetch(tokenUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body
    }, kp, {});

    const data = await resp.json();
    if (data.error) return { error: data.error_description || data.error };

    sessionStorage.setItem(OAUTH_KEYS.accessToken, data.access_token);
    if (data.sub) sessionStorage.setItem(OAUTH_KEYS.sessionDid, data.sub);

    // Clean URL
    window.history.replaceState({}, '', '/');
    return { did: data.sub, token: data };
}

export function getSession() {
    const token = sessionStorage.getItem(OAUTH_KEYS.accessToken);
    const did = sessionStorage.getItem(OAUTH_KEYS.sessionDid);
    if (token && did) return { token, did };
    return null;
}

export function logout() {
    sessionStorage.removeItem(OAUTH_KEYS.accessToken);
    sessionStorage.removeItem(OAUTH_KEYS.sessionDid);
    sessionStorage.removeItem(OAUTH_KEYS.state);
    sessionStorage.removeItem(OAUTH_KEYS.codeVerifier);
    dpopKeyPair = null;
}

export async function createPost(text, replyTo) {
    const token = sessionStorage.getItem(OAUTH_KEYS.accessToken);
    const did = sessionStorage.getItem(OAUTH_KEYS.sessionDid);

    if (!token || !did) {
        throw new Error('You must be logged in to post. Please sign in via OAuth first.');
    }

    const trimmedText = text.trim();
    if (!trimmedText) {
        throw new Error('Post content cannot be empty.');
    }

    if (trimmedText.length > 300) {
        throw new Error(`Post is too long (${trimmedText.length}/300 characters). Please shorten it.`);
    }

    const kp = await getOrCreateKey();
    const url = new URL('/xrpc/com.atproto.repo.createRecord', OAUTH_CONFIG.issuer).href;

    const record = {
        $type: 'app.bsky.feed.post',
        text: trimmedText,
        createdAt: new Date().toISOString()
    };

    if (replyTo && replyTo.startsWith('at://')) {
        const parts = replyTo.replace('at://', '').split('/');
        if (parts.length >= 3) {
            record.reply = {
                root: { uri: replyTo, cid: '' },
                parent: { uri: replyTo, cid: '' }
            };
        }
    }

    try {
        const resp = await dpopFetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': 'DPoP ' + token
            },
            body: JSON.stringify({
                repo: did,
                collection: 'app.bsky.feed.post',
                record
            })
        }, kp, { accessToken: token });

        const data = await resp.json();

        if (!resp.ok) {
            console.error('Post failed:', data);
            const errorMsg = data.message || data.error || `Server returned ${resp.status}`;
            if (resp.status === 401) {
                throw new Error('Your session has expired. Please log in again.');
            }
            throw new Error(`Failed to create post: ${errorMsg}`);
        }

        return data;
    } catch (err) {
        if (err.name === 'TypeError' && err.message === 'Failed to fetch') {
            throw new Error('Network error: Could not reach the PDS. Please check your connection.');
        }
        throw err;
    }
}

export async function loadRecentPosts() {
    const token = sessionStorage.getItem(OAUTH_KEYS.accessToken);
    const did = sessionStorage.getItem(OAUTH_KEYS.sessionDid);
    if (!token || !did) return [];

    try {
        const url = new URL('/xrpc/com.atproto.repo.listRecords', OAUTH_CONFIG.issuer);
        url.searchParams.set('repo', did);
        url.searchParams.set('collection', 'app.bsky.feed.post');
        url.searchParams.set('limit', '5');
        const resp = await fetch(url.href);
        if (!resp.ok) return [];
        const data = await resp.json();
        return data.records || [];
    } catch (e) {
        console.error('Failed to load recent posts:', e);
        return [];
    }
}

export async function testSession() {
    const token = sessionStorage.getItem(OAUTH_KEYS.accessToken);
    if (!token) throw new Error('Not logged in');

    const kp = await getOrCreateKey();
    const url = new URL('/xrpc/com.atproto.server.getSession', OAUTH_CONFIG.issuer).href;

    const resp = await dpopFetch(url, {
        headers: { 'Authorization': 'DPoP ' + token }
    }, kp, { accessToken: token });

    return await resp.json();
}
