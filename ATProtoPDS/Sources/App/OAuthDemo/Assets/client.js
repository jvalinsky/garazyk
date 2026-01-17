const CONFIG = {
    clientId: 'test-client',
    redirectUri: window.location.origin + '/oauth-demo/callback',
    scope: 'atproto',
    issuer: window.location.origin // Assuming demo client is served by PDS
};

const STORAGE_KEYS = {
    state: 'oauth_state',
    codeVerifier: 'oauth_code_verifier',
    accessToken: 'access_token'
};

let inMemoryKeyPair = null;
let storageWarningShown = false;

const elements = {
    handle: document.getElementById('handle'),
    btnLogin: document.getElementById('btn-login'),
    loginSection: document.getElementById('login-section'),
    callbackSection: document.getElementById('callback-section'),
    sessionSection: document.getElementById('session-section'),
    tokenStatus: document.getElementById('token-status'),
    tokenDisplay: document.getElementById('token-display'),
    btnTestSession: document.getElementById('btn-test-session'),
    btnLogout: document.getElementById('btn-logout'),
    apiResult: document.getElementById('api-result'),
    debugLog: document.getElementById('debug-log'),
    storageWarning: document.getElementById('storage-warning')
};

function log(msg) {
    console.log(msg);
    elements.debugLog.textContent += `[${new Date().toLocaleTimeString()}] ${msg}\n`;
}

function showStorageWarning(message) {
    if (storageWarningShown) return;
    storageWarningShown = true;
    elements.storageWarning.textContent = message;
    elements.storageWarning.classList.remove('hidden');
}

// --- PKCE Helpers ---
function generateRandomString(length) {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    let result = '';
    const values = new Uint32Array(length);
    crypto.getRandomValues(values);
    for (let i = 0; i < length; i++) {
        result += charset[values[i] % charset.length];
    }
    return result;
}

async function sha256(plain) {
    const encoder = new TextEncoder();
    const data = encoder.encode(plain);
    return crypto.subtle.digest('SHA-256', data);
}

function base64UrlEncode(a) {
    var str = "";
    var bytes = new Uint8Array(a);
    var len = bytes.byteLength;
    for (var i = 0; i < len; i++) {
        str += String.fromCharCode(bytes[i]);
    }
    return btoa(str)
        .replace(/\+/g, "-")
        .replace(/\//g, "_")
        .replace(/=+$/, "");
}

function base64UrlEncodeString(str) {
    return base64UrlEncode(new TextEncoder().encode(str));
}

function toUnpaddedUint8(bytes) {
    let start = 0;
    while (start < bytes.length && bytes[start] === 0) start++;
    return bytes.slice(start);
}

function derToJose(signature, keySize) {
    const bytes = new Uint8Array(signature);
    if (bytes[0] !== 0x30) {
        throw new Error('Invalid ECDSA signature');
    }
    let offset = 2;
    if (bytes[1] & 0x80) {
        const lengthBytes = bytes[1] & 0x7f;
        offset = 2 + lengthBytes;
    }
    if (bytes[offset++] !== 0x02) {
        throw new Error('Invalid ECDSA signature');
    }
    let rLen = bytes[offset++];
    let r = bytes.slice(offset, offset + rLen);
    offset += rLen;
    if (bytes[offset++] !== 0x02) {
        throw new Error('Invalid ECDSA signature');
    }
    let sLen = bytes[offset++];
    let s = bytes.slice(offset, offset + sLen);
    r = toUnpaddedUint8(r);
    s = toUnpaddedUint8(s);
    if (r.length > keySize || s.length > keySize) {
        throw new Error('Invalid ECDSA signature size');
    }
    const out = new Uint8Array(keySize * 2);
    out.set(r, keySize - r.length);
    out.set(s, 2 * keySize - s.length);
    return out;
}

async function sha256Bytes(data) {
    return crypto.subtle.digest('SHA-256', data);
}

async function computeAth(accessToken) {
    const hash = await sha256Bytes(new TextEncoder().encode(accessToken));
    return base64UrlEncode(hash);
}

function normalizeDpopUrl(url) {
    const u = new URL(url);
    u.hash = '';
    return u.toString();
}

async function openKeyDb() {
    return new Promise((resolve, reject) => {
        const request = indexedDB.open('oauth-demo', 1);
        request.onupgradeneeded = () => {
            const db = request.result;
            if (!db.objectStoreNames.contains('keys')) {
                db.createObjectStore('keys');
            }
        };
        request.onerror = () => reject(request.error);
        request.onsuccess = () => resolve(request.result);
    });
}

async function saveKeyPair(keyPair) {
    try {
        const db = await openKeyDb();
        return new Promise((resolve, reject) => {
            const tx = db.transaction('keys', 'readwrite');
            tx.oncomplete = () => resolve();
            tx.onerror = () => reject(tx.error);
            tx.objectStore('keys').put(keyPair, 'dpop');
        });
    } catch (err) {
        log(`Warning: DPoP key not persisted (${err.message}).`);
        showStorageWarning('DPoP key is stored in memory only. Refreshing the page will require a new login.');
    }
}

async function loadKeyPair() {
    try {
        const db = await openKeyDb();
        return new Promise((resolve, reject) => {
            const tx = db.transaction('keys', 'readonly');
            const request = tx.objectStore('keys').get('dpop');
            request.onsuccess = () => resolve(request.result || null);
            request.onerror = () => reject(request.error);
        });
    } catch (err) {
        log(`Warning: DPoP key not loaded from storage (${err.message}).`);
        showStorageWarning('DPoP key storage is unavailable. This browser may block persistent storage.');
        return null;
    }
}

// --- DPoP Helpers ---
async function generateDPoPKey() {
    log("Generating DPoP key pair (ES256)...");
    return await crypto.subtle.generateKey(
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign"]
    );
}

async function getOrCreateDPoPKey() {
    const existing = await loadKeyPair();
    if (existing) return existing;
    if (inMemoryKeyPair) return inMemoryKeyPair;

    const keyPair = await generateDPoPKey();
    await saveKeyPair(keyPair);
    inMemoryKeyPair = keyPair;
    return keyPair;
}

async function createDPoPProof(keyPair, method, url, options = {}) {
    const header = {
        typ: "dpop+jwt",
        alg: "ES256",
        jwk: await crypto.subtle.exportKey("jwk", keyPair.publicKey)
    };

    const payload = {
        jti: generateRandomString(16),
        htm: method.toUpperCase(),
        htu: normalizeDpopUrl(url),
        iat: Math.floor(Date.now() / 1000)
    };

    if (options.nonce) {
        payload.nonce = options.nonce;
    }
    if (options.accessToken) {
        payload.ath = await computeAth(options.accessToken);
    }

    const headerEnc = base64UrlEncodeString(JSON.stringify(header));
    const payloadEnc = base64UrlEncodeString(JSON.stringify(payload));
    const unsignedToken = `${headerEnc}.${payloadEnc}`;

    const signature = await crypto.subtle.sign(
        { name: "ECDSA", hash: { name: "SHA-256" } },
        keyPair.privateKey,
        new TextEncoder().encode(unsignedToken)
    );

    const joseSignature = derToJose(signature, 32);
    const signatureEnc = base64UrlEncode(joseSignature);
    return `${unsignedToken}.${signatureEnc}`;
}

function captureDpopNonce(headers) {
    const nonce = headers.get('DPoP-Nonce');
    if (nonce) {
        sessionStorage.setItem(nonceStorageKey(), nonce);
    }
    return nonce;
}

function nonceStorageKey() {
    return `dpop_nonce:${CONFIG.issuer}`;
}

async function fetchWithDpopNonceRetry(url, init, dpopKeyPair, options = {}) {
    const method = (init.method || 'GET').toUpperCase();
    const nonce = sessionStorage.getItem(nonceStorageKey());
    const dpopProof = await createDPoPProof(dpopKeyPair, method, url, {
        nonce,
        accessToken: options.accessToken
    });

    const headers = new Headers(init.headers || {});
    headers.set('DPoP', dpopProof);
    const firstResponse = await fetch(url, { ...init, headers });
    captureDpopNonce(firstResponse.headers);

    if ((firstResponse.status === 400 || firstResponse.status === 401) &&
        firstResponse.headers.get('DPoP-Nonce')) {
        const retryProof = await createDPoPProof(dpopKeyPair, method, url, {
            nonce: sessionStorage.getItem(nonceStorageKey()),
            accessToken: options.accessToken
        });
        headers.set('DPoP', retryProof);
        const retryResponse = await fetch(url, { ...init, headers });
        captureDpopNonce(retryResponse.headers);
        return retryResponse;
    }

    return firstResponse;
}

// --- OAuth Flow ---
async function startLogin() {
    const handle = elements.handle.value;
    if (!handle || handle.trim().length === 0) {
        elements.tokenStatus.innerHTML = '<span class="error">Handle required</span>';
        return;
    }
    log(`Starting login for handle: ${handle}`);

    const state = generateRandomString(16);
    const codeVerifier = generateRandomString(64);
    const codeChallenge = base64UrlEncode(await sha256(codeVerifier));

    sessionStorage.setItem(STORAGE_KEYS.state, state);
    sessionStorage.setItem(STORAGE_KEYS.codeVerifier, codeVerifier);

    const authUrl = new URL('/oauth/authorize', CONFIG.issuer);
    authUrl.searchParams.set('client_id', CONFIG.clientId);
    authUrl.searchParams.set('redirect_uri', CONFIG.redirectUri);
    authUrl.searchParams.set('response_type', 'code');
    authUrl.searchParams.set('scope', CONFIG.scope);
    authUrl.searchParams.set('state', state);
    authUrl.searchParams.set('code_challenge', codeChallenge);
    authUrl.searchParams.set('code_challenge_method', 'S256');
    authUrl.searchParams.set('login_hint', handle);

    log(`Redirecting to: ${authUrl.href}`);
    window.location.href = authUrl.href;
}

async function handleCallback() {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    const state = params.get('state');

    const savedState = sessionStorage.getItem(STORAGE_KEYS.state);
    const codeVerifier = sessionStorage.getItem(STORAGE_KEYS.codeVerifier);

    if (state !== savedState) {
        log("Error: State mismatch!");
        elements.tokenStatus.innerHTML = '<span class="error">State mismatch!</span>';
        return;
    }

    log("Exchanging code for tokens...");
    elements.loginSection.classList.add('hidden');
    elements.callbackSection.classList.remove('hidden');

    // Need a DPoP key for the token request
    const keyPair = await getOrCreateDPoPKey();
    const tokenUrl = new URL('/oauth/token', CONFIG.issuer).href;

    const formData = new URLSearchParams();
    formData.set('grant_type', 'authorization_code');
    formData.set('code', code);
    formData.set('redirect_uri', CONFIG.redirectUri);
    formData.set('client_id', CONFIG.clientId);
    formData.set('code_verifier', codeVerifier);

    try {
        const response = await fetchWithDpopNonceRetry(tokenUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded'
            },
            body: formData
        }, keyPair);

        const data = await response.json();
        if (data.error) {
            log(`Error: ${data.error_description || data.error}`);
            elements.tokenStatus.innerHTML = `<span class="error">${data.error}</span>`;
            return;
        }

        log("Tokens received successfully!");
        sessionStorage.setItem(STORAGE_KEYS.accessToken, data.access_token);
        window.dpopKeyPair = keyPair;

        showSession(data);
    } catch (err) {
        log(`Fetch error: ${err.message}`);
        elements.tokenStatus.innerHTML = `<span class="error">${err.message}</span>`;
    }
}

function showSession(data) {
    elements.callbackSection.classList.add('hidden');
    elements.sessionSection.classList.remove('hidden');
    elements.tokenDisplay.textContent = JSON.stringify(data, null, 2);
}

async function testSession() {
    const token = sessionStorage.getItem(STORAGE_KEYS.accessToken);
    if (!token) {
        elements.apiResult.classList.remove('hidden');
        elements.apiResult.textContent = 'No access token - login first.';
        return;
    }
    if (!window.dpopKeyPair) {
        window.dpopKeyPair = await getOrCreateDPoPKey();
    }
    const url = new URL('/xrpc/com.atproto.server.getSession', CONFIG.issuer).href;

    log(`Testing session: GET ${url}`);

    try {
        const response = await fetchWithDpopNonceRetry(url, {
            headers: {
                'Authorization': `DPoP ${token}`
            }
        }, window.dpopKeyPair, { accessToken: token });
        const data = await response.json();
        elements.apiResult.classList.remove('hidden');
        elements.apiResult.textContent = JSON.stringify(data, null, 2);
        log("API call successful!");
    } catch (err) {
        log(`API error: ${err.message}`);
    }
}

function logout() {
    sessionStorage.clear();
    window.location.href = '/oauth-demo';
}

// --- Initialization ---
elements.btnLogin.addEventListener('click', startLogin);
elements.btnTestSession.addEventListener('click', testSession);
elements.btnLogout.addEventListener('click', logout);

if (window.location.pathname.endsWith('/callback')) {
    handleCallback();
} else {
    log("Ready.");
}
