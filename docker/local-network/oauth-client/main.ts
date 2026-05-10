import {
  configureOAuth,
  createAuthorizationUrl,
  finalizeAuthorization,
  getSession,
  OAuthUserAgent,
} from '@atcute/oauth-browser-client'
import {
  LocalActorResolver,
  XrpcHandleResolver,
  CompositeDidDocumentResolver,
  PlcDidDocumentResolver,
  WebDidDocumentResolver,
} from '@atcute/identity-resolver'

// Global fetch interceptor for "stealth" requests
const originalFetch = window.fetch;
window.fetch = async (...args) => {
    const url = args[0] instanceof Request ? args[0].url : String(args[0]);
    console.log(`[GLOBAL-FETCH] ${url}`);
    return originalFetch(...args);
};

// Logging fetch wrapper — intercepts every HTTP request the OAuth library
// makes internally so we can see exactly what it fetches and what it gets back.
const loggingFetch: typeof globalThis.fetch = async (input, init) => {
  const url = typeof input === 'string' ? input
    : input instanceof URL ? input.href
    : input instanceof Request ? input.url
    : (input as any).url || (input as any).href || String(input)

  const method = init?.method ?? (input instanceof Request ? input.method : 'GET')
  const reqHeaders: Record<string, string> = {}
  if (init?.headers) {
    if (init.headers instanceof Headers) {
      init.headers.forEach((v, k) => { reqHeaders[k] = v })
    } else if (Array.isArray(init.headers)) {
      for (const [k, v] of init.headers) { reqHeaders[k] = v }
    } else {
      Object.assign(reqHeaders, init.headers as Record<string, string>)
    }
  }

  console.log(`[OAUTH-FETCH] --> ${method} ${url}`)
  console.log(`[OAUTH-FETCH]     request headers:`, JSON.stringify(reqHeaders))

  const startTime = performance.now()
  try {
    const response = await originalFetch(input, init)
    const elapsed = (performance.now() - startTime).toFixed(0)
    console.log(`[OAUTH-FETCH] <-- ${response.status} ${response.statusText} ${url} (${elapsed}ms)`)
    console.log(`[OAUTH-FETCH]     response headers:`, JSON.stringify(Object.fromEntries(response.headers.entries())))

    // Clone and log the body for metadata endpoints (not for large responses)
    if (url && typeof url === 'string' && url.includes('/.well-known/') && response.status === 200) {
      const cloned = response.clone()
      try {
        const body = await cloned.json()
        console.log(`[OAUTH-FETCH]     response body:`, JSON.stringify(body))
      } catch {
        // Not JSON, skip
      }
    }

    return response
  } catch (err) {
    const elapsed = (performance.now() - startTime).toFixed(0)
    console.error(`[OAUTH-FETCH] <-- FAILED ${method} ${url} (${elapsed}ms):`, err)
    throw err
  }
}

console.log('[Test] Configuring atcute OAuth client...')

configureOAuth({
  metadata: {
    client_id: 'http://127.0.0.1:8080/client-metadata.json',
    redirect_uri: 'http://127.0.0.1:8080/',
  },
  identityResolver: new LocalActorResolver({
    handleResolver: new XrpcHandleResolver({
      serviceUrl: 'http://127.0.0.1:2583',
    }),
    didDocumentResolver: new CompositeDidDocumentResolver({
      methods: {
        plc: {
          async resolve(did) {
            console.log(`[Test] Resolving DID ${did} via PLC...`);
            const url = `http://127.0.0.1:2582/${did}`;
            console.log(`[Test] Fetching ${url}`);
            try {
              const resp = await originalFetch(url, {
                headers: { 'Accept': 'application/did+json' }
              });
              console.log(`[Test] PLC response: ${resp.status} ${resp.statusText}`);
              if (!resp.ok) {
                throw new Error(`PLC returned ${resp.status}`);
              }
              const doc = await resp.json();
              console.log(`[Test] PLC document:`, JSON.stringify(doc));
              return doc;
            } catch (err) {
              console.error(`[Test] PLC resolve failed for ${did}:`, err);
              throw err;
            }
          }
        },
        web: new WebDidDocumentResolver(),
      },
    }),
  }),
  fetch: loggingFetch,
})

const statusEl = document.getElementById('status')!
const loginFormEl = document.getElementById('login-form')!
const handleInputEl = document.getElementById('handle')! as HTMLInputElement
const loginBtn = document.getElementById('login-btn')!
const logoutBtn = document.getElementById('logout-btn')!
const profileEl = document.getElementById('profile')!
const displayNameEl = document.getElementById('display-name')!
const userHandleEl = document.getElementById('user-handle')!

let currentDid: string | null = null

async function init() {
  console.log('[Test] Initializing OAuth client...')

  // Check if we're on the callback page with hash fragment params
  const hash = location.hash
  if (hash && hash.length > 1 && hash.includes('code=')) {
    console.log('[Test] Detected callback hash params, finalizing authorization...')
    try {
      const params = new URLSearchParams(hash.slice(1))
      // Scrub params from URL to prevent replay
      history.replaceState(null, '', location.pathname + location.search)

      const { session } = await finalizeAuthorization(params)
      const did = session.info.sub
      console.log('[Test] Authorization finalized, session DID:', did)
      currentDid = did
      showProfile(did, did)
      return
    } catch (err) {
      console.error('[Test] finalizeAuthorization error:', err)
      statusEl.innerText = 'Authorization failed: ' + (err as Error).message
    }
  }

  // Try to resume an existing session
  try {
    // atcute stores sessions internally; try to find one
    // We iterate by checking if there's a stored DID we can resume
    // For the test client, we'll just check if we have a currentDid
    if (currentDid) {
      const session = await getSession(currentDid, { allowStale: true })
      const agent = new OAuthUserAgent(session)
      console.log('[Test] Resumed session for:', session.did)
      showProfile(session.did, session.did)
      return
    }
  } catch (err) {
    console.log('[Test] No existing session to resume:', err)
  }

  // Not logged in — show login form
  console.log('[Test] Not logged in')
  statusEl.innerText = 'Not logged in'
  profileEl.style.display = 'none'
  loginFormEl.style.display = 'block'
}

function showProfile(did: string, handle: string) {
  statusEl.innerText = 'Logged in as ' + did
  profileEl.style.display = 'block'
  loginFormEl.style.display = 'none'
  displayNameEl.innerText = did
  userHandleEl.innerText = handle
}

loginBtn.onclick = async () => {
  const handle = handleInputEl.value
  if (!handle) return

  statusEl.innerText = 'Signing in as ' + handle + '...'

  try {
    console.log(`[Test] Signing in as ${handle}...`)
    console.log(`[Test] About to call createAuthorizationUrl — the library will now:`)
    console.log(`[Test]   1. Resolve handle -> DID via PDS`)
    console.log(`[Test]   2. Fetch DID document from PLC`)
    console.log(`[Test]   3. Extract PDS URL from DID document`)
    console.log(`[Test]   4. Fetch /.well-known/oauth-protected-resource from PDS`)
    console.log(`[Test]   5. Fetch /.well-known/oauth-authorization-server from PDS`)
    console.log(`[Test]   6. Submit PAR request to PDS`)
    console.log(`[Test]   7. Redirect browser to PDS authorize page`)

    const authUrl = await createAuthorizationUrl({
      target: { type: 'account', identifier: handle },
      scope: 'atproto transition:generic',
    })

    console.log(`[Test] Authorization URL created, redirecting...`)
    // Small delay to let browser persist local storage
    await new Promise(resolve => setTimeout(resolve, 200))
    window.location.assign(authUrl)
  } catch (err: any) {
    console.error(`[Test] Sign in failed:`, err)
    console.error(`[Test] Error name: ${err?.name}`)
    console.error(`[Test] Error message: ${err?.message}`)
    console.error(`[Test] Error cause: ${JSON.stringify(err?.cause)}`)
    if (err?.stack) {
      console.error(`[Test] Stack trace:`, err.stack)
    }
    statusEl.innerText = 'Sign in failed: ' + (err as Error).message
  }
}

logoutBtn.onclick = async () => {
  // Simple reload for mock
  window.location.href = '/'
}

init()
