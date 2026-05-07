# WebAuthn OAuth2 Integration - Complete Implementation Plan

> **For Claude:** Use superpowers:executing-plans to implement task-by-task.

**Goal:** Complete WebAuthn integration into OAuth2 token exchange flow by storing/retrieving WebAuthn challenges in OAuth sessions, then verifying assertions at token endpoint.

**Architecture:** Add WebAuthn challenge storage to OAuthSession, integrate with OAuth2 authorize endpoint, verify at token endpoint.

---

## Problem Analysis

Currently, the OAuth2 token endpoint cannot verify WebAuthn assertions because:
1. The WebAuthn challenge is issued at `/auth/webauthn/register/begin` (separate from OAuth flow)
2. No way to retrieve the challenge during token exchange
3. Need to tie WebAuthn into the OAuth authorization flow

**Solution:** Extend OAuthSession to store WebAuthn challenge, integrate with OAuth2 authorize endpoint, verify at token endpoint.

---

## Required Changes

### 1. Add WebAuthn fields to OAuthSession

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuthSession.h:100-105`
- Modify: `ATProtoPDS/Sources/Auth/OAuthSession.m`

**Add to OAuthSession interface:**

```objc
/*! WebAuthn challenge issued for this session. */
@property (nonatomic, copy, nullable) NSData *webauthnChallenge;

/*! WebAuthn challenge expiration. */
@property (nonatomic, strong, nullable) NSDate *webauthnChallengeExpiresAt;

/*! Whether WebAuthn authentication is required. */
@property (nonatomic, assign) BOOL webauthnRequired;
```

**Modify OAuthSession.m** - Add init to clear these fields:
```objc
session.webauthnChallenge = nil;
session.webauthnChallengeExpiresAt = nil;
session.webauthnRequired = NO;
```

---

### 2. Generate/Store WebAuthn Challenge in OAuth Flow

**Flow:**
1. Client requests `/oauth/authorize` with `webauthn=true` parameter
2. Server generates WebAuthn challenge, stores in OAuthSession
3. Server includes challenge in authorization form (hidden field or JavaScript)
4. User completes WebAuthn at client side
5. Client submits assertion with token request

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m` - `/oauth/authorize` endpoint (or sign-in confirm)

**Step in OAuth2Handler.m (handleAuthorizeConfirm or sign-in):**

```objc
// Check if webauthn requested
if ([request parameterForKey:@"webauthn"]) {
    NSData *webauthnChallenge = [CryptoUtils randomBytes:32];
    session.webauthnChallenge = webauthnChallenge;
    session.webauthnChallengeExpiresAt = [NSDate dateWithIntervalSinceNow:300];
    session.webauthnRequired = YES;
    
    // Include in form as hidden field for client JS to read
    [form setHiddenField:base64URLEncode(webauthnChallenge) forKey:@"webauthn_challenge"];
}
```

---

### 3. Return WebAuthn Challenge in OAuth Metadata/Form

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m` - authorization form builder

**In authorize form (HTML), add script:**

```javascript
// If webauthn_challenge present, use it to create credential
const challenge = document.getElementById('webauthn_challenge');
if (challenge) {
    // Use WebAuthn API to get assertion
    const cred = await navigator.credentials.get({
        publicKey: {
            challenge: base64UrlDecode(challenge.value),
            rpId: window.location.hostname,
        }
    });
    // Add assertion to form
    document.getElementById('oauth_form').insertAdjacentHTML(
        'beforeend', 
        `<input type="hidden" name="webauthn_assertion" value="${base64URLEncode(cred)}">`
    );
}
```

For MVP: Client handles WebAuthn separately, sends assertion to token endpoint.

---

### 4. Parse WebAuthn Assertion in Token Request

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2Handler.m` - token endpoint body parsing

**In OAuth2Handler.m (token endpoint):**

```objc
// Parse webauthn_assertion from form body
NSString *assertionStr = [request formParameterForKey:@"webauthn_assertion"];
if (assertionStr) {
    NSData *assertionData = [[NSData alloc] initWithBase64URLEncodedString:assertionStr options:0];
    request.webauthnAssertion = [NSJSONSerialization JSONObjectWithData:assertionData options:0 error:nil];
}
```

---

### 5. Verify WebAuthn Assertion at Token Endpoint

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuth2.m:758-780`

**Replace placeholder with actual verification:**

```objc
if (account && account.webauthnEnabled && !request.tfaCode) {
    if (!request.webauthnAssertion) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                      code:OAuth2ErrorInteractionRequired
                                  userInfo:@{NSLocalizedDescriptionKey: @"WebAuthn authentication required", 
                                             @"error": @"webauthn_required"}];
        completion(nil, error);
        return;
    }

    // Get session to retrieve challenge
    NSString *authCode = request.code;
    OAuthSession *session = [self.oauthService sessionForAuthCode:authCode];
    if (!session.webauthnChallenge) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                      code:OAuth2ErrorInvalidGrant
                                  userInfo:@{NSLocalizedDescriptionKey: @"No WebAuthn challenge found"}];
        completion(nil, error);
        return;
    }

    // Get credentials
    NSError *webauthnError = nil;
    NSArray<NSDictionary *> *credentials = [self.database getWebAuthnCredentialsForDid:session.accountDid error:&webauthnError];
    if (credentials.count == 0) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                      code:OAuth2ErrorInvalidGrant
                                  userInfo:@{NSLocalizedDescriptionKey: @"No WebAuthn credentials found"}];
        completion(nil, error);
        return;
    }

    // Verify assertion
    BOOL verified = NO;
    NSString *origin = [PDSConfiguration sharedConfiguration].issuer;

    for (NSDictionary *cred in credentials) {
        uint32_t storedSignCount = [cred[@"signCount"] unsignedIntValue];
        uint32_t newCount = 0;

        verified = [WebAuthnVerifier verifyAssertionResponse:request.webauthnAssertion
                                           challenge:session.webauthnChallenge
                                              origin:origin
                                           publicKey:cred[@"publicKey"]
                                           signCount:storedSignCount
                                        newSignCount:&newCount
                                               error:&webauthnError];
        if (verified) {
            // Update sign count
            [self.database updateWebAuthnCredentialSignCount:cred[@"credentialId"]
                                          forDid:session.accountDid
                                       signCount:newCount
                                           error:nil];
            break;
        }
    }

    if (!verified) {
        NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                      code:OAuth2ErrorInvalidGrant
                                  userInfo:@{NSLocalizedDescriptionKey: @"WebAuthn verification failed"}];
        completion(nil, error);
        return;
    }
}
```

---

### 6. Add Helper to Get OAuthSession from Auth Code

**Files:**
- Modify: `ATProtoPDS/Sources/Auth/OAuthSession.m` or `OAuth2.m`

**In OAuthSession (PARService or existing method):**

```objc
- (nullable OAuthSession *)sessionForAuthCode:(NSString *)authCode {
    __block OAuthSession *session = nil;
    dispatch_sync(self.sessionQueue, ^{
        session = self.authCodes[authCode];
    });
    return session;
}
```

Or in OAuth2.m, access existing authCodes dictionary.

---

## Test Coverage

**Files:**
- Create: `ATProtoPDS/Tests/Auth/WebAuthnOAuthIntegrationTests.m`

```objc
// Test webauthn challenge stored in session
// Test webauthn assertion parsed from token request  
// Test successful verification
// Test reject without assertion
// Test reject invalid assertion
// Test sign count updates
// Test cloned authenticator rejected
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | OAuthSession WebAuthn fields | OAuthSession.h, OAuthSession.m |
| 2 | Generate challenge in OAuth flow | OAuth2Handler.m |
| 3 | Return challenge in form | OAuth2Handler.m (HTML) |
| 4 | Parse assertion at token | OAuth2Handler.m |
| 5 | Verify at token endpoint | OAuth2.m |
| 6 | OAuthSession helper | OAuthSession.m |
| 7 | Tests | WebAuthnOAuthIntegrationTests.m |

**Commit sequence:** 4-7 commits (TDD per task)