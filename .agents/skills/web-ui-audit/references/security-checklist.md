# Frontend Security Checklist

Use this checklist when reviewing browser-facing authentication, rendering, and data handling.

## XSS and HTML Injection

- Prefer `textContent` and safe DOM construction over `innerHTML`.
- If HTML insertion is required, restrict inputs and sanitize at the boundary.
- Never render server-provided error text or user content as trusted markup.

## Auth and Session Handling

- Avoid storing high-value tokens in `localStorage`.
- Preserve OAuth state, nonce, and PKCE verification where applicable.
- Do not expose credentials, cookies, authorization headers, or secrets in logs.
- Ensure logout clears client state that could authorize future requests.

## Requests and Boundaries

- Use CSRF protection for cookie-authenticated mutating requests.
- Validate redirects and return URLs against an allowlist.
- Keep admin-only UI paths backed by server-side authorization.
- Avoid leaking sensitive data through URLs, query strings, analytics, or browser history.
