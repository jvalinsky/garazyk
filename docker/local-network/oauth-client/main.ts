import { BrowserOAuthClient } from '@atproto/oauth-client-browser'

const client = new BrowserOAuthClient({
  handleResolver: 'http://localhost:2583', // PDS
  clientMetadata: {
    client_id: 'http://localhost:8080/client-metadata.json',
    client_name: 'Garazyk E2E Test Client',
    client_uri: 'http://localhost:8080',
    logo_uri: 'http://localhost:8080/logo.png',
    redirect_uris: [
        'http://localhost:8080/callback'
    ],
    scope: 'atproto transition:generic',
    grant_types: [
        'authorization_code',
        'refresh_token'
    ],
    response_types: [
        'code'
    ],
    token_endpoint_auth_method: 'none',
    application_type: 'web',
    dpop_bound_access_tokens: true
  }
})

const statusEl = document.getElementById('status')!
const loginFormEl = document.getElementById('login-form')!
const profileEl = document.getElementById('profile')!
const handleInput = document.getElementById('handle') as HTMLInputElement
const loginBtn = document.getElementById('login-btn')!
const logoutBtn = document.getElementById('logout-btn')!
const displayNameEl = document.getElementById('display-name')!
const userHandleEl = document.getElementById('user-handle')!

async function init() {
  try {
    const result = await client.init()
    
    if (result) {
      // Logged in
      const { session } = result
      statusEl.innerText = 'Logged in!'
      loginFormEl.style.display = 'none'
      profileEl.style.display = 'block'
      
      // Fetch profile using the session (AppView)
      const agent = {
          // Mock agent or use @atproto/api if available
          // For simplicity in this test, we just show the DID/Handle from session
      }
      
      displayNameEl.innerText = session.did
      userHandleEl.innerText = 'Sub: ' + session.sub
    } else {
      statusEl.innerText = 'Please sign in.'
      loginFormEl.style.display = 'block'
      profileEl.style.display = 'none'
    }
  } catch (err) {
    statusEl.innerText = 'Error: ' + (err as Error).message
    console.error(err)
  }
}

loginBtn.onclick = async () => {
  const handle = handleInput.value
  statusEl.innerText = `Signing in as ${handle}...`
  try {
    await client.signIn(handle)
  } catch (err) {
    statusEl.innerText = 'Sign in failed: ' + (err as Error).message
  }
}

logoutBtn.onclick = async () => {
  // Simple reload for mock
  window.location.href = '/'
}

init()
