---
title: OAuth2 Web UI (Consent Screen)
---

# OAuth2 Web UI (Consent Screen)

## Overview

The OAuth2 consent screen provides a two-step authorization flow with Classic Mac aesthetics, implementing CSRF protection and session token binding for secure user authorization.

## Implementation Files

| File | Purpose |
|------|---------|
| `Garazyk/Sources/Auth/Assets/authorize.html` | Consent screen HTML/JS template |
| `Garazyk/Sources/Auth/OAuth2Handler.m` | Server-side handler (`serveAuthorizePage`) |

## UI Flow Diagram

```

┌─────────────────────────────────────────────────────────────────────┐
│                    GET /oauth/authorize                             │
│  client_id, redirect_uri, scope, state, code_challenge, login_hint  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    SERVER: serveAuthorizePage                       │
│  • Generate CSRF token (UUID)                                       │
│  • Set HttpOnly cookie: csrf_token                                  │
│  • Inject token into HTML meta tag                                  │
│  • Template replacement with HTML escaping                          │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     STEP 1: SIGN IN                                 │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │  Authorization                                               │    │
│  │  ┌─────────────────────────────────────────────────────┐    │    │
│  │  │  [Client Name]                                       │    │    │
│  │  │  wants to access your ATProto account.               │    │    │
│  │  │  Please sign in to continue.                         │    │    │
│  │  └─────────────────────────────────────────────────────┘    │    │
│  │                                                              │    │
│  │  Handle:   [________________] (pre-filled from login_hint)  │    │
│  │  Password: [________________]                                │    │
│  │                                                              │    │
│  │  [Cancel]                              [Sign In]             │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
                                    │
          ┌─────────────────────────┼─────────────────────────┐
          │                         │                         │
          ▼                         ▼                         ▼
   ┌─────────────┐         ┌─────────────────┐        ┌─────────────┐
   │   Cancel    │         │ POST /oauth/    │        │   Error     │
   │   Button    │         │ authorize/sign-in│       │   Display   │
   └─────────────┘         └─────────────────┘        └─────────────┘
          │                         │
          │                         ▼
          │               ┌─────────────────────┐
          │               │ Validate CSRF       │
          │               │ X-CSRF-Token header │
          │               │ == csrf_token cookie│
          │               └─────────────────────┘
          │                         │
          │                         ▼
          │               ┌─────────────────────┐
          │               │ Authenticate User   │
          │               │ via PDSAccountService│
          │               └─────────────────────┘
          │                    │         │
          │              Success      Failure
          │                    │         │
          │                    ▼         ▼
          │              ┌─────────┐ ┌───────────┐
          │              │ Session │ │ 401 Error │
          │              │ Token   │ └───────────┘
          │              │ (UUID)  │
          │              └─────────┘
          │                    │
          │                    ▼
          ▼              ┌─────────────────────────────────────────────┐
   ┌──────────────────┐  │              STEP 2: CONSENT               │
   │ Redirect to      │  │  ┌─────────────────────────────────────┐    │
   │ redirect_uri     │  │  │  [Client Name]                       │    │
   │ ?error=          │  │  │  would like to access your account.  │    │
   │ access_denied    │  │  └─────────────────────────────────────┘    │
   └──────────────────┘  │                                             │
                         │  ┌─────────────────────────────────────┐    │
                         │  │  Signed in as [handle]              │    │
                         │  └─────────────────────────────────────┘    │
                         │                                             │
                         │  This application will be able to:          │
                         │  ✓ Full access to your account              │
                         │  ✓ Write to your repository                 │
                         │  ✓ Read your repository                     │
                         │                                             │
                         │  [Cancel]                      [Authorize]  │
                         └─────────────────────────────────────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ▼                         ▼                         │
             ┌─────────────┐         ┌─────────────────┐               │
             │ POST /oauth │         │ POST /oauth     │               │
             │ /authorize  │         │ /authorize      │               │
             │ /confirm    │         │ /confirm        │               │
             │ decision=   │         │ decision=allow  │               │
             │ deny        │         │ session_token   │               │
             └─────────────┘         └─────────────────┘               │
                    │                         │                         │
                    ▼                         ▼                         │
             ┌─────────────┐         ┌─────────────────┐               │
             │ Redirect    │         │ Validate        │               │
             │ error=      │         │ session_token   │               │
             │ access_denied│        │ from pending    │               │
             └─────────────┘         │ consents dict   │               │
                                     └─────────────────┘               │
                                              │                         │
                                              ▼                         │
                                     ┌─────────────────┐               │
                                     │ Generate        │               │
                                     │ authorization   │               │
                                     │ code            │               │
                                     └─────────────────┘               │
                                              │                         │
                                              ▼                         │
                                     ┌─────────────────────────────────┤
                                     │ 302 Redirect to redirect_uri   │
                                     │ ?code=AUTHORIZATION_CODE        │
                                     │ &state=STATE                    │
                                     └─────────────────────────────────┘
```

## Template Structure

### HTML Template Location

```

Garazyk/Sources/Auth/Assets/authorize.html
```

### Template Placeholders

All placeholders are replaced server-side with HTML-escaped values:

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `{{csrf_token}}` | Server-generated UUID | CSRF protection token |
| `{{client_id}}` | Query parameter | OAuth client identifier |
| `{{state}}` | Query parameter | OAuth state (CSRF for client) |
| `{{scope}}` | Query parameter | Space-separated scope list |
| `{{redirect_uri}}` | Query parameter | Client redirect endpoint |
| `{{response_type}}` | Query parameter | Always `"code"` |
| `{{code_challenge}}` | Query parameter | PKCE challenge (S256) |
| `{{code_challenge_method}}` | Query parameter | Always `"S256"` |
| `{{nonce}}` | Query parameter | Optional nonce for replay protection |
| `{{login_hint}}` | Query parameter | Pre-filled handle input |

### Template Replacement (OAuth2Handler.m:358-404)

```objc
- (void)serveAuthorizePage:(HttpResponse *)response params:(NSDictionary *)params {
    // Load HTML template
    NSString *html = [NSString stringWithContentsOfFile:filePath 
                                                encoding:NSUTF8StringEncoding 
                                                   error:&error];
    
    // Generate CSRF token
    NSString *csrfToken = [[NSUUID UUID] UUIDString];
    html = [html stringByReplacingOccurrencesOfString:@"{{csrf_token}}" 
                                           withString:[self escapeHtml:csrfToken]];
    
    // Replace all template placeholders with HTML escaping
    html = [html stringByReplacingOccurrencesOfString:@"{{client_id}}" 
                                           withString:[self escapeHtml:params[@"client_id"]]];
    // ... additional replacements ...
    
    // Set HttpOnly cookie
    [response setHeader:[NSString stringWithFormat:
        @"csrf_token=%@; Path=/oauth; HttpOnly; SameSite=Strict", csrfToken] 
               forKey:@"Set-Cookie"];
}
```

## CSRF Protection

### Token Generation

```objc
// OAuth2Handler.m:375
NSString *csrfToken = [[NSUUID UUID] UUIDString];
```

### Token Distribution

1. **Meta tag** (readable by JavaScript):
   ```html
   <meta name="csrf-token" content="{{csrf_token}}">
   ```text

2. **HttpOnly cookie** (sent automatically with requests):
   ```text
   Set-Cookie: csrf_token=<UUID>; Path=/oauth; HttpOnly; SameSite=Strict
   ```text

### Token Validation (OAuth2Handler.m:507-524)

```objc
- (void)handleAuthorizeSignIn:(HttpRequest *)request response:(HttpResponse *)response {
    // Extract CSRF token from header
    NSString *csrfHeader = [request headerForKey:@"X-CSRF-Token"];
    
    // Extract CSRF token from cookie
    NSString *csrfCookie = nil;
    NSString *cookieHeader = [request headerForKey:@"Cookie"];
    // Parse cookie string to find csrf_token
    
    // Validate match
    if (!csrfHeader || !csrfCookie || ![csrfHeader isEqualToString:csrfCookie]) {
        response.statusCode = 403;
        [response setJsonBody:@{@"ok": @NO, @"error": @"Invalid CSRF token"}];
        return;
    }
}
```

### Client-Side Implementation (authorize.html:234-240)

```javascript
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || '';
const resp = await fetch('/oauth/authorize/sign-in', {
    method: 'POST',
    headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-CSRF-Token': csrfToken
    },
    body: new URLSearchParams({ handle, password }).toString()
});
```

## Session Token Flow

### Purpose

Session tokens bind the sign-in step to the consent step, preventing:
- Substitution attacks between users
- Replay attacks with old consent forms
- Session fixation

### Token Generation (OAuth2Handler.m:546-552)

```objc
NSString *sessionToken = [[NSUUID UUID] UUIDString];
@synchronized (sPendingConsents) {
    sPendingConsents[sessionToken] = @{
        @"did": result[@"did"],
        @"handle": handle,
        @"expires": [NSDate dateWithTimeIntervalSinceNow:300]  // 5-minute TTL
    };
}
```

### Token Storage

In-memory dictionary with synchronized access:
```objc
static NSMutableDictionary *sPendingConsents = nil;
```

### Token Lifecycle

```

┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│    Sign-In       │────▶│  Pending Consents│────▶│     Consent      │
│    Success       │     │    (5 min TTL)   │     │    Validation    │
└──────────────────┘     └──────────────────┘     └──────────────────┘
        │                        │                        │
        │   session_token        │   lookup & validate    │
        └────────────────────────┴────────────────────────┘
```

### Token Validation (OAuth2Handler.m:436-468)

```objc
- (void)handleAuthorizeConfirm:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *sessionToken = params[@"session_token"];
    
    // Lookup in pending consents
    NSDictionary *consentSession = nil;
    @synchronized (sPendingConsents) {
        consentSession = sPendingConsents[sessionToken];
    }
    
    // Validate existence
    if (!consentSession) {
        response.statusCode = 403;
        [response setJsonBody:@{@"error": @"access_denied", 
                                @"error_description": @"Invalid or expired session token"}];
        return;
    }
    
    // Validate expiration
    NSDate *expires = consentSession[@"expires"];
    if ([expires compare:[NSDate date]] == NSOrderedAscending) {
        @synchronized (sPendingConsents) {
            [sPendingConsents removeObjectForKey:sessionToken];
        }
        response.statusCode = 403;
        [response setJsonBody:@{@"error": @"access_denied", 
                                @"error_description": @"Session token expired"}];
        return;
    }
    
    // Clean up used token (single-use)
    @synchronized (sPendingConsents) {
        [sPendingConsents removeObjectForKey:sessionToken];
    }
}
```

### Client-Side Injection (authorize.html:249-252)

```javascript
if (data.ok) {
    // Inject session token into consent forms
    document.querySelectorAll('input[name="session_token"]').forEach(el => {
        el.value = data.session_token || '';
    });
}
```

## Scope Display

### Scope Descriptions (authorize.html:198-210)

```javascript
const scopeDescriptions = {
    'atproto': 'Full access to your account',
    'transition:generic': 'Access to your account data',
    'transition:chat.bsky': 'Access to your chats',
    'repo:write': 'Write to your repository',
    'repo:read': 'Read your repository',
    'email:read': 'Read your email address',
    'email:manage': 'Manage your email settings',
    'identity': 'Access your identity information',
    'account': 'Manage your account settings',
    'chat.bsky.convo': 'Access your conversations',
    'chat.bsky.moderation': 'Moderate chat content'
};
```

### Scope List Rendering (authorize.html:211-215)

```javascript
const scopeStr = params.get('scope') || 'atproto';
scopeStr.split(' ').forEach(s => {
    const li = document.createElement('li');
    li.textContent = scopeDescriptions[s] || s;  // Fallback to raw scope
    scopeList.appendChild(li);
});
```

### Visual Display

```

This application will be able to:
┌─────────────────────────────────────────────┐
│ ✓ Full access to your account               │
│ ✓ Write to your repository                  │
│ ✓ Read your repository                      │
└─────────────────────────────────────────────┘
```

## HTML Escaping

### Escape Implementation (OAuth2Handler.m:960-969)

```objc
- (NSString *)escapeHtml:(NSString *)input {
    if (!input) return @"";
    NSString *escaped = input;
    escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
    return escaped;
}
```

### Escaped Characters

| Character | Entity | Context |
|-----------|--------|---------|
| `&` | `&amp;` | All contexts |
| `<` | `&lt;` | Prevents tag injection |
| `>` | `&gt;` | Prevents tag injection |
| `"` | `&quot;` | Attribute values |
| `'` | `&#39;` | Attribute values |

## Error Handling

### Sign-In Errors

| Error | HTTP Status | Description |
|-------|-------------|-------------|
| Missing credentials | 400 | Handle or password not provided |
| Invalid CSRF | 403 | CSRF header/cookie mismatch |
| Auth unavailable | 500 | No accountService configured |
| Invalid credentials | 401 | Wrong handle/password |

### Consent Errors

| Error | HTTP Status | Description |
|-------|-------------|-------------|
| Missing session token | 403 | No session_token in request |
| Invalid session token | 403 | Token not in pending consents |
| Expired session token | 403 | Token TTL exceeded (5 min) |
| Access denied | 302 | User clicked Cancel |

### Error Display (authorize.html:222-227)

```javascript
if (!handle || !password) {
    errorEl.textContent = 'Please enter your handle and password.';
    errorEl.style.display = 'block';
    return;
}
```

## Responsive Design

### Classic Mac Aesthetics

Uses `system.css` for authentic retro styling:
- Window chrome with title bar
- Outer/inner border pattern
- Standard dialog appearance
- Classic button styling

### Container Sizing

```css
.auth-container {
    width: 420px;
}

body {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
}
```

## Login Hint Handling

### Pre-filled Handle (authorize.html:189-194)

```javascript
const loginHint = params.get('login_hint');
const handleInput = document.getElementById('auth-handle');
if (loginHint) {
    handleInput.value = loginHint;
    handleInput.readOnly = true;
    handleInput.style.background = '#e0e0e0';
}
```

When `login_hint` is provided:
- Handle input is pre-filled
- Input becomes read-only
- Background grays out to indicate non-editable

## Routes Summary

| Route | Method | Handler | Purpose |
|-------|--------|---------|---------|
| `/oauth/authorize` | GET | `handleAuthorizeRequest` | Display consent screen |
| `/oauth/authorize/sign-in` | POST | `handleAuthorizeSignIn` | Authenticate user |
| `/oauth/authorize/confirm` | POST | `handleAuthorizeConfirm` | Process consent decision |

## Security Checklist

- [x] CSRF token in HttpOnly cookie + meta tag
- [x] CSRF validation on sign-in POST
- [x] Session token binding sign-in to consent
- [x] Session token single-use (deleted after validation)
- [x] Session token expiration (5-minute TTL)
- [x] HTML escaping on all template values
- [x] State parameter required (client CSRF)
- [x] PKCE required for public clients
- [x] Redirect URI exact match validation
- [x] HTTPS required in production

## Related Documentation

- [Authorization Flow](authorization-flow) - Full authorization code flow
- [Security](security) - Security considerations for the consent flow
- [Overview](README) - OAuth2 implementation overview
