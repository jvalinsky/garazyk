const CONFIG = {
    clientId: 'test-client',
    redirectUri: window.location.origin + '/oauth-demo/callback',
    scope: 'atproto',
    issuer: window.location.origin // Assuming demo client is served by PDS
};

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
    debugLog: document.getElementById('debug-log')
};

function log(msg) {
    console.log(msg);
    elements.debugLog.textContent += `[${new Date().toLocaleTimeString()}] ${msg}\n`;
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

// --- DPoP Helpers ---
async function generateDPoPKey() {
    log("Generating DPoP key pair (ES256)...");
    return await crypto.subtle.generateKey(
        { name: "ECDSA", namedCurve: "P-256" },
        true,
        ["sign"]
    );
}

async function createDPoPProof(keyPair, method, url) {
    const header = {
        typ: "dpop+jwt",
        alg: "ES256",
        jwk: await crypto.subtle.exportKey("jwk", keyPair.publicKey)
    };

    const payload = {
        jti: generateRandomString(16),
        htm: method,
        htu: url,
        iat: Math.floor(Date.now() / 1000)
    };

    const headerEnc = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
    const payloadEnc = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
    const unsignedToken = `${headerEnc}.${payloadEnc}`;

    const signature = await crypto.subtle.sign(
        { name: "ECDSA", hash: { name: "SHA-256" } },
        keyPair.privateKey,
        new TextEncoder().encode(unsignedToken)
    );

    const signatureEnc = base64UrlEncode(signature);
    return `${unsignedToken}.${signatureEnc}`;
}

// --- OAuth Flow ---
async function startLogin() {
    const handle = elements.handle.value;
    log(`Starting login for handle: ${handle}`);

    const state = generateRandomString(16);
    const codeVerifier = generateRandomString(64);
    const codeChallenge = base64UrlEncode(await sha256(codeVerifier));

    sessionStorage.setItem('oauth_state', state);
    sessionStorage.setItem('oauth_code_verifier', codeVerifier);

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

    const savedState = sessionStorage.getItem('oauth_state');
    const codeVerifier = sessionStorage.getItem('oauth_code_verifier');

    if (state !== savedState) {
        log("Error: State mismatch!");
        elements.tokenStatus.innerHTML = '<span class="error">State mismatch!</span>';
        return;
    }

    log("Exchanging code for tokens...");
    elements.loginSection.classList.add('hidden');
    elements.callbackSection.classList.remove('hidden');

    // Need a DPoP key for the token request
    const keyPair = await generateDPoPKey();
    // ATProto spec says DPoP is required for token endpoint
    const dpopProof = await createDPoPProof(keyPair, 'POST', new URL('/oauth/token', CONFIG.issuer).href);

    const formData = new URLSearchParams();
    formData.set('grant_type', 'authorization_code');
    formData.set('code', code);
    formData.set('redirect_uri', CONFIG.redirectUri);
    formData.set('client_id', CONFIG.clientId);
    formData.set('code_verifier', codeVerifier);

    try {
        const response = await fetch('/oauth/token', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'DPoP': dpopProof
            },
            body: formData
        });

        const data = await response.json();
        if (data.error) {
            log(`Error: ${data.error_description || data.error}`);
            elements.tokenStatus.innerHTML = `<span class="error">${data.error}</span>`;
            return;
        }

        log("Tokens received successfully!");
        sessionStorage.setItem('access_token', data.access_token);
        // We'd normally save the DPoP key too, to use with the access token
        // For this demo, we'll keep it in memory or just regenerate (might not work if bound)
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
    const token = sessionStorage.getItem('access_token');
    const url = new URL('/xrpc/com.atproto.server.getSession', CONFIG.issuer).href;

    log(`Testing session: GET ${url}`);

    const dpopProof = await createDPoPProof(window.dpopKeyPair, 'GET', url);

    try {
        const response = await fetch(url, {
            headers: {
                'Authorization': `DPoP ${token}`,
                'DPoP': dpopProof
            }
        });
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
