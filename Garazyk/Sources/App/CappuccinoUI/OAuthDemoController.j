/*
 * OAuthDemoController.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation OAuthDemoController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    CPTextField _handleField;
    CPTextField _didField;
    CPTextField _postTextField;
    CPTextView _resultTextView;
    CPTextView _debugTextView;

    id _dpopKeyPair;
    CPString _accessToken;
    CPString _sessionDid;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _dpopKeyPair = nil;
        _accessToken = nil;
        _sessionDid = nil;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 900.0, 28.0)];
    [title setStringValue:@"OAuth Demo"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 1040.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Ready."];

    var handleLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 74.0, 48.0, 18.0)];
    [handleLabel setStringValue:@"Handle:"];
    [handleLabel setEditable:NO];
    [handleLabel setBezeled:NO];
    [handleLabel setDrawsBackground:NO];

    _handleField = [[CPTextField alloc] initWithFrame:CGRectMake(70.0, 70.0, 190.0, 24.0)];
    [_handleField setPlaceholderString:@"alice.example.com"];

    var loginButton = [[CPButton alloc] initWithFrame:CGRectMake(268.0, 68.0, 86.0, 28.0)];
    [loginButton setTitle:@"Login"];
    [loginButton setTarget:self];
    [loginButton setAction:@selector(handleStartLogin:)];

    var logoutButton = [[CPButton alloc] initWithFrame:CGRectMake(360.0, 68.0, 86.0, 28.0)];
    [logoutButton setTitle:@"Logout"];
    [logoutButton setTarget:self];
    [logoutButton setAction:@selector(handleLogout:)];

    var testSessionButton = [[CPButton alloc] initWithFrame:CGRectMake(454.0, 68.0, 120.0, 28.0)];
    [testSessionButton setTitle:@"Test Session"];
    [testSessionButton setTarget:self];
    [testSessionButton setAction:@selector(handleTestSession:)];

    var listRecordsButton = [[CPButton alloc] initWithFrame:CGRectMake(582.0, 68.0, 108.0, 28.0)];
    [listRecordsButton setTitle:@"List Records"];
    [listRecordsButton setTarget:self];
    [listRecordsButton setAction:@selector(handleListRecords:)];

    var didLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 106.0, 30.0, 18.0)];
    [didLabel setStringValue:@"DID:"];
    [didLabel setEditable:NO];
    [didLabel setBezeled:NO];
    [didLabel setDrawsBackground:NO];

    _didField = [[CPTextField alloc] initWithFrame:CGRectMake(52.0, 102.0, 638.0, 24.0)];
    [_didField setEditable:NO];
    [_didField setStringValue:@"(none)"];

    _postTextField = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 134.0, 590.0, 24.0)];
    [_postTextField setPlaceholderString:@"Post text"];

    var createPostButton = [[CPButton alloc] initWithFrame:CGRectMake(618.0, 132.0, 90.0, 28.0)];
    [createPostButton setTitle:@"Create Post"];
    [createPostButton setTarget:self];
    [createPostButton setAction:@selector(handleCreatePost:)];

    _resultTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(20.0, 168.0, 690.0, 502.0)
                                                     inView:_rootView];
    _debugTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(720.0, 70.0, 340.0, 600.0)
                                                    inView:_rootView];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];
    [_rootView addSubview:handleLabel];
    [_rootView addSubview:_handleField];
    [_rootView addSubview:loginButton];
    [_rootView addSubview:logoutButton];
    [_rootView addSubview:testSessionButton];
    [_rootView addSubview:listRecordsButton];
    [_rootView addSubview:didLabel];
    [_rootView addSubview:_didField];
    [_rootView addSubview:_postTextField];
    [_rootView addSubview:createPostButton];

    [self restoreSessionFromStorage];
    [self handleOAuthCallbackIfPresent];
    [self appendDebug:@"Ready."];
    [self setTextView:_resultTextView content:@"OAuth demo initialized.\nUse Login to begin OAuth flow."];

    return _rootView;
}

- (CPTextView)buildReadOnlyTextViewWithFrame:(CGRect)frame inView:(CPView)parent
{
    var textView = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, 0.0, frame.size.width, frame.size.height)];
    [textView setEditable:NO];
    [textView setSelectable:YES];
    [textView setString:@""];
    [textView setFont:[CPFont systemFontOfSize:12.0]];

    var scroll = [[CPScrollView alloc] initWithFrame:frame];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setDocumentView:textView];
    [parent addSubview:scroll];

    return textView;
}

- (void)setStatus:(CPString)message
{
    [_statusLabel setStringValue:(message || @"")];
}

- (void)setTextView:(CPTextView)textView content:(CPString)content
{
    if (!textView)
        return;
    [textView setString:(content || @"")];
}

- (void)appendDebug:(CPString)line
{
    if (!_debugTextView)
        return;

    var existing = [_debugTextView string] || @"",
        timestamp = new Date().toLocaleTimeString();
    [self setTextView:_debugTextView content:(existing + "[" + timestamp + "] " + (line || @"") + "\n")];
}

- (CPString)trimmedString:(CPString)value
{
    if (!value)
        return @"";
    return String(value).replace(/^\s+|\s+$/g, "");
}

- (CPString)safeString:(id)value
{
    if (value === nil || value === undefined)
        return @"";
    if (typeof value === "string")
        return value;
    return String(value);
}

- (CPString)prettyJSON:(id)object
{
    if (object === nil || object === undefined)
        return @"";
    try
    {
        return JSON.stringify(object, null, 2);
    }
    catch (e)
    {
        return String(object);
    }
}

- (CPString)storageKeyState
{
    return @"oauth_demo_state";
}

- (CPString)storageKeyVerifier
{
    return @"oauth_demo_code_verifier";
}

- (CPString)storageKeyAccessToken
{
    return @"oauth_demo_access_token";
}

- (CPString)storageKeySessionDid
{
    return @"oauth_demo_session_did";
}

- (CPString)storageKeyDPoPNonce
{
    return @"oauth_demo_dpop_nonce";
}

- (void)setSessionStorageValue:(CPString)value forKey:(CPString)key
{
    if (!key)
        return;

    try
    {
        if (value === nil || value === undefined)
            sessionStorage.removeItem(String(key));
        else
            sessionStorage.setItem(String(key), String(value));
    }
    catch (e)
    {
    }
}

- (CPString)sessionStorageValueForKey:(CPString)key
{
    if (!key)
        return nil;

    try
    {
        return sessionStorage.getItem(String(key));
    }
    catch (e)
    {
    }
    return nil;
}

- (void)setLocalStorageValue:(CPString)value forKey:(CPString)key
{
    if (!key)
        return;

    try
    {
        if (value === nil || value === undefined)
            localStorage.removeItem(String(key));
        else
            localStorage.setItem(String(key), String(value));
    }
    catch (e)
    {
    }
}

- (CPString)localStorageValueForKey:(CPString)key
{
    if (!key)
        return nil;

    try
    {
        return localStorage.getItem(String(key));
    }
    catch (e)
    {
    }
    return nil;
}

- (void)syncSessionUI
{
    [_didField setStringValue:(_sessionDid && _sessionDid.length ? _sessionDid : @"(none)")];
    if (_sessionDid && _sessionDid.length)
        [_sessionState setCurrentDID:_sessionDid];
}

- (void)setSessionDid:(CPString)did persist:(BOOL)persist
{
    _sessionDid = did;
    [self syncSessionUI];
    if (persist)
        [self setLocalStorageValue:did forKey:[self storageKeySessionDid]];
}

- (void)restoreSessionFromStorage
{
    _accessToken = [self sessionStorageValueForKey:[self storageKeyAccessToken]];
    [self setSessionDid:[self localStorageValueForKey:[self storageKeySessionDid]] persist:NO];
}

- (CPString)oauthIssuer
{
    if (window && window.location && window.location.origin)
        return String(window.location.origin);
    return @"";
}

- (CPString)oauthClientID
{
    return @"test-client";
}

- (CPString)oauthRedirectURI
{
    return [self oauthIssuer] + @"/ui/oauth-demo/callback?oauth_demo_callback=1";
}

- (CPString)randomOAuthStringWithLength:(int)length
{
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
        out = "";

    if (window && window.crypto && window.Uint32Array && window.crypto.getRandomValues)
    {
        var values = new Uint32Array(length);
        window.crypto.getRandomValues(values);
        for (var i = 0; i < length; i++)
            out += chars.charAt(values[i] % chars.length);
        return out;
    }

    for (var j = 0; j < length; j++)
        out += chars.charAt(Math.floor(Math.random() * chars.length));
    return out;
}

- (CPString)base64URLEncodeBytes:(id)bytesBuffer
{
    if (!(window && window.btoa))
        return @"";

    var bytes = new Uint8Array(bytesBuffer),
        binary = "";
    for (var i = 0; i < bytes.length; i++)
        binary += String.fromCharCode(bytes[i]);

    return window.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

- (CPString)base64URLEncodeString:(CPString)stringValue
{
    if (!(window && window.TextEncoder))
        return @"";

    var encoder = new TextEncoder(),
        encoded = encoder.encode(String(stringValue || @""));
    return [self base64URLEncodeBytes:encoded];
}

- (void)sha256ForString:(CPString)value completion:(Function)completion
{
    if (!(window && window.crypto && window.crypto.subtle && window.TextEncoder))
    {
        completion(nil, @"WebCrypto unavailable");
        return;
    }

    var encoder = new TextEncoder(),
        encoded = encoder.encode(String(value || @""));

    window.crypto.subtle.digest("SHA-256", encoded)
        .then(function(hashBuffer)
    {
        completion(hashBuffer, nil);
    })
        .catch(function(error)
    {
        completion(nil, (error && error.message) ? error.message : @"SHA-256 failed");
    });
}

- (void)getOrCreateDPoPKeyWithCompletion:(Function)completion
{
    if (_dpopKeyPair)
    {
        completion(_dpopKeyPair, nil);
        return;
    }

    if (!(window && window.crypto && window.crypto.subtle))
    {
        completion(nil, @"WebCrypto unavailable");
        return;
    }

    window.crypto.subtle.generateKey({name: "ECDSA", namedCurve: "P-256"}, YES, ["sign"])
        .then(function(keyPair)
    {
        _dpopKeyPair = keyPair;
        completion(keyPair, nil);
    })
        .catch(function(error)
    {
        completion(nil, (error && error.message) ? error.message : @"Failed to create DPoP key");
    });
}

- (CPString)normalizedDPoPHTU:(CPString)urlString
{
    try
    {
        var u = new URL(String(urlString));
        return u.origin + u.pathname;
    }
    catch (e)
    {
        return urlString;
    }
}

- (void)makeDPoPProofWithKeyPair:(id)keyPair
                          method:(CPString)method
                             url:(CPString)url
                           nonce:(CPString)nonce
                     accessToken:(CPString)accessToken
                      completion:(Function)completion
{
    if (!(window && window.crypto && window.crypto.subtle && window.TextEncoder))
    {
        completion(nil, @"WebCrypto unavailable");
        return;
    }

    var httpMethod = String(method || @"GET"),
        htu = [self normalizedDPoPHTU:url];

    window.crypto.subtle.exportKey("jwk", keyPair.publicKey).then(function(jwk)
    {
        var header = {
                typ: "dpop+jwt",
                alg: "ES256",
                jwk: jwk
            },
            payload = {
                jti: [self randomOAuthStringWithLength:16],
                htm: httpMethod.toUpperCase(),
                htu: htu,
                iat: Math.floor(Date.now() / 1000)
            },
            finalize = function(ath)
            {
                if (nonce && nonce.length)
                    payload.nonce = nonce;
                if (ath && ath.length)
                    payload.ath = ath;

                var unsignedToken = [self base64URLEncodeString:JSON.stringify(header)] + "." + [self base64URLEncodeString:JSON.stringify(payload)];
                var signEncoder = new TextEncoder(),
                    unsignedBytes = signEncoder.encode(unsignedToken);

                window.crypto.subtle.sign({name: "ECDSA", hash: {name: "SHA-256"}},
                                          keyPair.privateKey,
                                          unsignedBytes)
                    .then(function(signature)
                {
                    completion(unsignedToken + "." + [self base64URLEncodeBytes:signature], nil);
                })
                    .catch(function(signError)
                {
                    completion(nil, (signError && signError.message) ? signError.message : @"DPoP signing failed");
                });
            };

        if (accessToken && accessToken.length)
        {
            [self sha256ForString:accessToken completion:function(hashBuffer, hashError)
            {
                if (hashError)
                {
                    completion(nil, hashError);
                    return;
                }
                finalize([self base64URLEncodeBytes:hashBuffer]);
            }];
        }
        else
        {
            finalize(nil);
        }
    }).catch(function(exportError)
    {
        completion(nil, (exportError && exportError.message) ? exportError.message : @"DPoP key export failed");
    });
}

- (id)parsedJSONFromResponseText:(CPString)text
{
    if (!text || !text.length)
        return {};

    try
    {
        return JSON.parse(text);
    }
    catch (e)
    {
        return {rawText: text};
    }
}

- (void)dpopFetchJSONWithURL:(CPString)url
                      method:(CPString)method
                     headers:(id)headers
                        body:(id)body
                 accessToken:(CPString)accessToken
                  completion:(Function)completion
{
    if (!(window && window.fetch))
    {
        completion(0, nil, @"Fetch unavailable");
        return;
    }

    [self getOrCreateDPoPKeyWithCompletion:function(keyPair, keyError)
    {
        if (keyError)
        {
            completion(0, nil, keyError);
            return;
        }

        var executeAttempt = function(allowRetry)
        {
            var nonce = [self sessionStorageValueForKey:[self storageKeyDPoPNonce]];
            [self makeDPoPProofWithKeyPair:keyPair
                                    method:method
                                       url:url
                                     nonce:nonce
                               accessToken:accessToken
                                completion:function(proof, proofError)
            {
                if (proofError)
                {
                    completion(0, nil, proofError);
                    return;
                }

                var fetchHeaders = {};
                if (headers)
                {
                    for (var key in headers)
                    {
                        if (headers.hasOwnProperty(key))
                            fetchHeaders[key] = headers[key];
                    }
                }
                fetchHeaders.DPoP = proof;

                var options = {method: String(method || @"GET"), headers: fetchHeaders};
                if (body !== nil && body !== undefined)
                    options.body = body;

                window.fetch(String(url), options).then(function(response)
                {
                    var responseNonce = response.headers ? response.headers.get("DPoP-Nonce") : nil;
                    if (responseNonce)
                        [self setSessionStorageValue:responseNonce forKey:[self storageKeyDPoPNonce]];

                    response.text().then(function(responseText)
                    {
                        var payload = [self parsedJSONFromResponseText:responseText];

                        if ((response.status === 400 || response.status === 401) && responseNonce && allowRetry)
                        {
                            executeAttempt(NO);
                            return;
                        }

                        var errorMessage = nil;
                        if (!response.ok)
                            errorMessage = (payload && (payload.error_description || payload.error || payload.message)) || ("HTTP " + response.status);

                        completion(response.status, payload, errorMessage);
                    }).catch(function()
                    {
                        completion(response.status, nil, @"Failed reading response body");
                    });
                }).catch(function(fetchError)
                {
                    completion(0, nil, (fetchError && fetchError.message) ? fetchError.message : @"Network error");
                });
            }];
        };

        executeAttempt(YES);
    }];
}

- (void)handleOAuthCallbackIfPresent
{
    if (!(window && window.location && window.URLSearchParams))
        return;

    var search = String(window.location.search || @""),
        params = new URLSearchParams(search),
        code = params.get("code"),
        state = params.get("state"),
        callbackFlag = params.get("oauth_demo_callback"),
        pathname = String(window.location.pathname || @"");

    var isDemoCallback = (pathname.indexOf("/ui/oauth-demo/callback") >= 0) || (callbackFlag === "1");
    if (!isDemoCallback)
        return;

    var savedState = [self sessionStorageValueForKey:[self storageKeyState]],
        verifier = [self sessionStorageValueForKey:[self storageKeyVerifier]];

    if (!code || !state || !savedState || state !== savedState)
    {
        [self appendDebug:@"OAuth callback failed: state mismatch or missing code."];
        [self setStatus:@"OAuth callback validation failed."];
        return;
    }

    var tokenURL = [self oauthIssuer] + @"/oauth/token",
        formBody = new URLSearchParams();
    formBody.set("grant_type", "authorization_code");
    formBody.set("code", code);
    formBody.set("redirect_uri", [self oauthRedirectURI]);
    formBody.set("client_id", [self oauthClientID]);
    formBody.set("code_verifier", verifier || @"");

    [self appendDebug:@"Exchanging callback code for tokens..."];
    [self setStatus:@"Exchanging callback code..."];
    [self dpopFetchJSONWithURL:tokenURL
                        method:@"POST"
                       headers:{"Content-Type": "application/x-www-form-urlencoded"}
                          body:formBody
                   accessToken:nil
                    completion:function(statusCode, payload, errorMessage)
                    {
                        if (errorMessage || !payload || !payload.access_token)
                        {
                            [self setStatus:@"Token exchange failed."];
                            [self appendDebug:("Token exchange failed: " + (errorMessage || @"missing access_token"))];
                            [self setTextView:_resultTextView content:[self prettyJSON:(payload || {error: errorMessage || "Token exchange failed"})]];
                            return;
                        }

                        _accessToken = payload.access_token;
                        [self setSessionStorageValue:_accessToken forKey:[self storageKeyAccessToken]];
                        [self setSessionStorageValue:nil forKey:[self storageKeyState]];
                        [self setSessionStorageValue:nil forKey:[self storageKeyVerifier]];

                        [self setSessionDid:(payload.sub || _sessionDid) persist:YES];
                        [self setTextView:_resultTextView content:[self prettyJSON:payload]];
                        [self appendDebug:@"Token exchange successful."];
                        [self setStatus:@"OAuth session established."];

                        if (window && window.history && window.history.replaceState)
                            window.history.replaceState({}, "", "/ui");
                    }];
}

- (void)startOAuthLoginWithHandle:(CPString)handle
{
    var trimmedHandle = [self trimmedString:handle];
    if (!trimmedHandle || trimmedHandle.length === 0)
    {
        [self setStatus:@"Handle required for login."];
        return;
    }

    var state = [self randomOAuthStringWithLength:32],
        verifier = [self randomOAuthStringWithLength:64];

    [self sha256ForString:verifier completion:function(hashBuffer, hashError)
    {
        if (hashError)
        {
            [self setStatus:@"OAuth login failed before redirect."];
            [self appendDebug:("PKCE challenge generation failed: " + hashError)];
            return;
        }

        var challenge = [self base64URLEncodeBytes:hashBuffer],
            authURL = new URL("/oauth/authorize", [self oauthIssuer]);

        [self setSessionStorageValue:state forKey:[self storageKeyState]];
        [self setSessionStorageValue:verifier forKey:[self storageKeyVerifier]];

        authURL.searchParams.set("client_id", [self oauthClientID]);
        authURL.searchParams.set("redirect_uri", [self oauthRedirectURI]);
        authURL.searchParams.set("response_type", "code");
        authURL.searchParams.set("scope", "atproto");
        authURL.searchParams.set("state", state);
        authURL.searchParams.set("code_challenge", challenge);
        authURL.searchParams.set("code_challenge_method", "S256");
        authURL.searchParams.set("login_hint", trimmedHandle);

        [self appendDebug:("Redirecting to OAuth authorize for " + trimmedHandle + "...")];
        [self setStatus:@"Redirecting to OAuth authorize..."];
        window.location.href = authURL.href;
    }];
}

- (void)logoutSession
{
    _accessToken = nil;
    _dpopKeyPair = nil;
    [self setSessionDid:nil persist:YES];

    [self setSessionStorageValue:nil forKey:[self storageKeyAccessToken]];
    [self setSessionStorageValue:nil forKey:[self storageKeyState]];
    [self setSessionStorageValue:nil forKey:[self storageKeyVerifier]];
    [self setSessionStorageValue:nil forKey:[self storageKeyDPoPNonce]];

    [self setTextView:_resultTextView content:@"Session cleared."];
    [self appendDebug:@"Logged out."];
    [self setStatus:@"Logged out."];
}

- (void)testSession
{
    if (!_accessToken || _accessToken.length === 0)
    {
        [self setStatus:@"No access token. Login first."];
        [self setTextView:_resultTextView content:@"No access token available."];
        return;
    }

    var url = [self oauthIssuer] + @"/xrpc/com.atproto.server.getSession";
    [self appendDebug:@"Testing authenticated session..."];
    [self dpopFetchJSONWithURL:url
                        method:@"GET"
                       headers:{Authorization: ("DPoP " + _accessToken)}
                          body:nil
                   accessToken:_accessToken
                    completion:function(statusCode, payload, errorMessage)
                    {
                        [self setTextView:_resultTextView content:[self prettyJSON:(payload || {error: errorMessage || "Unknown error"})]];
                        if (errorMessage)
                        {
                            [self setStatus:@"Session test failed."];
                            [self appendDebug:("Session test failed: " + errorMessage)];
                            return;
                        }

                        if (payload && payload.did)
                            [self setSessionDid:payload.did persist:YES];

                        [self setStatus:@"Session test successful."];
                        [self appendDebug:@"Session test successful."];
                    }];
}

- (void)createPostWithText:(CPString)text
{
    var trimmedText = [self trimmedString:text];
    if (!_accessToken || _accessToken.length === 0)
    {
        [self setStatus:@"No access token. Login first."];
        return;
    }
    if (!_sessionDid || _sessionDid.length === 0)
    {
        [self setStatus:@"No DID available. Run session test first."];
        return;
    }
    if (!trimmedText || trimmedText.length === 0)
    {
        [self setStatus:@"Post text is empty."];
        return;
    }

    var url = [self oauthIssuer] + @"/xrpc/com.atproto.repo.createRecord",
        createdAt = new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
        body = {
            repo: _sessionDid,
            collection: "app.bsky.feed.post",
            record: {
                $type: "app.bsky.feed.post",
                text: trimmedText,
                createdAt: createdAt
            }
        };

    [self appendDebug:("Creating post for " + _sessionDid + "...")];
    [self dpopFetchJSONWithURL:url
                        method:@"POST"
                       headers:{"Content-Type": "application/json", Authorization: ("DPoP " + _accessToken)}
                          body:JSON.stringify(body)
                   accessToken:_accessToken
                    completion:function(statusCode, payload, errorMessage)
                    {
                        [self setTextView:_resultTextView content:[self prettyJSON:(payload || {error: errorMessage || "Unknown error"})]];
                        if (errorMessage)
                        {
                            [self setStatus:@"Create post failed."];
                            [self appendDebug:("Create post failed: " + errorMessage)];
                            return;
                        }

                        [self setStatus:@"Post created."];
                        [self appendDebug:@"Post created successfully."];
                    }];
}

- (void)listRecords
{
    if (!_sessionDid || _sessionDid.length === 0)
    {
        [self setStatus:@"No DID available. Run session test first."];
        return;
    }

    [self appendDebug:("Listing recent records for " + _sessionDid + "...")];
    [_apiClient getJSONWithPath:@"/com.atproto.repo.listRecords"
                  endpointGroup:@"xrpc"
                    queryParams:{repo: _sessionDid, collection: "app.bsky.feed.post", limit: 10}
                     completion:function(statusCode, payload, errorMessage)
                     {
                         [self setTextView:_resultTextView content:[self prettyJSON:(payload || {error: errorMessage || "Unknown error"})]];
                         if (errorMessage)
                         {
                             [self setStatus:@"List records failed."];
                             [self appendDebug:("List records failed: " + errorMessage)];
                             return;
                         }

                         [self setStatus:@"Records loaded."];
                         [self appendDebug:@"Records loaded successfully."];
                     }];
}

#pragma mark - Actions

- (void)handleStartLogin:(id)sender
{
    [self startOAuthLoginWithHandle:[_handleField stringValue]];
}

- (void)handleLogout:(id)sender
{
    [self logoutSession];
}

- (void)handleTestSession:(id)sender
{
    [self testSession];
}

- (void)handleCreatePost:(id)sender
{
    [self createPostWithText:[_postTextField stringValue]];
}

- (void)handleListRecords:(id)sender
{
    [self listRecords];
}

@end
