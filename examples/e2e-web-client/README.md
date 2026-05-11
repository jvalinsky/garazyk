# Programmable E2E Web Client

This is a zero-build, vanilla JavaScript AT Protocol client designed for **programmatic E2E testing** while providing **visual feedback** for engineers.

## Usage in Test Harnesses

The client is designed to be driven by frameworks like **Playwright** or **Puppeteer**.

### 1. Launching the Client
Serve the `examples/e2e-web-client/` directory using any static file server (e.g., `python3 -m http.server 8000`).

Inject your dynamic service URLs via query parameters:
`http://localhost:8000/?pds=http://localhost:2583&appview=http://localhost:3200&chat=http://localhost:2585&germ=http://localhost:8082`

### 2. Driving the Client via JavaScript
The client exposes a global `window.GarazykE2E` object. Your test script can execute actions directly:

```javascript
// Example Playwright script snippet
await page.goto('http://localhost:8000/?pds=http://localhost:2583...');

// Trigger login
await page.evaluate(async () => {
  await window.GarazykE2E.login('luna.test', 'password');
});

// Send a DM
await page.evaluate(async () => {
  await window.GarazykE2E.sendDM('did:plc:recipient...', 'Hello from the test harness!');
});

// Play a video from the CDN
await page.evaluate(async () => {
  await window.GarazykE2E.playVideo('did:plc:user...', 'bafyreicid...');
});
```

## Features
- **AppView Integration:** Fetches and renders the timeline.
- **Chat Service:** Supports both vanilla plaintext DMs and simulated Germ E2EE envelopes.
- **Video CDN:** Integrated HLS.js player for testing the video pipeline.
- **URL Configuration:** Completely dynamic service binding for parallel CI runs.
