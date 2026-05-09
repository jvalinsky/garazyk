#import "Network/XrpcLabelMethods.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcAuthHelper.h"
#import "Network/XrpcIdentityHelper.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Database/Service/ServiceDatabases.h"
#import "Database/PDSDatabase.h"
#import "Admin/PDSAdminController.h"
#import "App/PDSConfiguration.h"
#import "Services/Core/PDSPhoneVerificationProvider.h"
#import "Email/PDSEnvironmentSecretsProvider.h"
#import "Identity/ATProtoHandleValidator.h"

// Deprecation constants for temp.fetchLabels
static NSString *const kTempFetchLabelsDeprecationWarning =
    @"299 - \"com.atproto.temp.fetchLabels is deprecated; use com.atproto.label.queryLabels or com.atproto.label.subscribeLabels\"";
static NSString *const kTempFetchLabelsSunsetDate = @"2027-12-31T00:00:00Z";
static NSString *const kTempFetchLabelsSuccessorLink =
    @"</xrpc/com.atproto.label.queryLabels>; rel=\"successor-version\", </xrpc/com.atproto.label.subscribeLabels>; rel=\"successor-version\"";

#pragma mark - Helper Functions

static BOOL parseStrictIntegerString(NSString *value, NSInteger *outValue) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    NSInteger parsed = 0;
    if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
        return NO;
    }
    if (outValue) {
        *outValue = parsed;
    }
    return YES;
}

static void setSubscribeLabelsUpgradeRequired(HttpResponse *response) {
    response.statusCode = 426;
    [response setHeader:@"websocket" forKey:@"Upgrade"];
    [response setHeader:@"Upgrade" forKey:@"Connection"];
    [response setJsonBody:@{
        @"error": @"UpgradeRequired",
        @"message": @"WebSocket upgrade required for subscribeLabels"
    }];
    response.keepAlive = NO;
}

static BOOL isLikelyPhoneNumber(NSString *phoneNumber) {
    if (![phoneNumber isKindOfClass:[NSString class]]) {
        return NO;
    }

    NSString *trimmed = [phoneNumber stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length < 7 || trimmed.length > 32) {
        return NO;
    }

    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"+0123456789 -()."];
    NSCharacterSet *disallowed = [allowed invertedSet];
    if ([trimmed rangeOfCharacterFromSet:disallowed].location != NSNotFound) {
        return NO;
    }

    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSUInteger digitCount = 0;
    for (NSUInteger index = 0; index < trimmed.length; index += 1) {
        unichar character = [trimmed characterAtIndex:index];
        if ([digits characterIsMember:character]) {
            digitCount += 1;
        }
    }
    return digitCount >= 7;
}

static NSArray<NSDictionary *> *loadFetchedLabels(PDSServiceDatabases *serviceDatabases,
                                                  BOOL hasSince,
                                                  NSInteger sinceSeconds,
                                                  NSInteger limit,
                                                  NSError **error) {
    PDSDatabase *db = [serviceDatabases serviceDatabaseWithError:error];
    if (!db) {
        return nil;
    }

    NSArray<NSDictionary *> *rows = nil;
    if (hasSince) {
        rows = [db executeParameterizedQuery:@"SELECT src, uri, cid, val, neg, cts, exp FROM labels "
                                         "WHERE CAST(COALESCE(strftime('%s', cts), '0') AS INTEGER) >= ? "
                                         "ORDER BY id ASC LIMIT ?"
                                      params:@[@(sinceSeconds), @(limit)]
                                       error:error];
    } else {
        rows = [db executeParameterizedQuery:@"SELECT src, uri, cid, val, neg, cts, exp FROM labels "
                                         "ORDER BY id ASC LIMIT ?"
                                      params:@[@(limit)]
                                       error:error];
    }

    [db close];
    return rows;
}

static NSArray<NSString *> *queryArrayValues(HttpRequest *request, NSString *key) {
    NSString *value = [request queryParamForKey:key];
    if (!value || value.length == 0) {
        return @[];
    }
    return [value componentsSeparatedByString:@","];
}

static NSDictionary *labelLookupParamsFromRequest(HttpRequest *request, NSString **errorMessage) {
    NSInteger limit = 50;
    NSString *limitParam = [request queryParamForKey:@"limit"];
    if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 250)) {
        if (errorMessage) {
            *errorMessage = @"limit must be an integer between 1 and 250";
        }
        return nil;
    }

    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:@(limit) forKey:@"limit"];

    NSArray<NSString *> *uriPatterns = queryArrayValues(request, @"uriPatterns");
    if (uriPatterns.count > 0) {
        params[@"uriPatterns"] = uriPatterns;
    }

    NSArray<NSString *> *sources = queryArrayValues(request, @"sources");
    if (sources.count > 0) {
        params[@"sources"] = sources;
    }

    NSString *cursor = [request queryParamForKey:@"cursor"];
    if (cursor.length > 0) {
        params[@"cursor"] = cursor;
    }

    NSString *collection = [request queryParamForKey:@"collection"];
    if (collection.length > 0) {
        params[@"collection"] = collection;
    }

    NSString *since = [request queryParamForKey:@"since"];
    if (since.length > 0) {
        params[@"since"] = since;
    }

    return params;
}

#pragma mark - XrpcLabelMethods Implementation

@implementation XrpcLabelMethods

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
              serviceDatabases:(PDSServiceDatabases *)serviceDatabases
                     jwtMinter:(JWTMinter *)jwtMinter
               adminController:(id<PDSAdminController>)adminController
                 configuration:(PDSConfiguration *)configuration {
    
    // Non-standard internal extensions for admin label management
    // com.atproto.label.createLabel and com.atproto.label.getLabels are internal admin-only methods
    // not part of the public AT Protocol lexicon. Use tools.ozone.* for production moderation.

    // com.atproto.label.queryLabels - Public label query endpoint
    [dispatcher registerComAtprotoLabelQueryLabels:^(HttpRequest *request, HttpResponse *response) {
        NSString *paramError = nil;
        NSDictionary *params = labelLookupParamsFromRequest(request, &paramError);
        if (!params) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": paramError ?: @"Invalid query parameters"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [adminController getLabels:params error:&error];

        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // com.atproto.label.createLabel - Admin-only label creation
    [dispatcher registerComAtprotoLabelCreateLabel:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                          response:response
                                  serviceDatabases:serviceDatabases
                                         jwtMinter:jwtMinter
                                   adminController:adminController]) {
            return;
        }
        
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = [request.jsonBody isKindOfClass:[NSDictionary class]] ? request.jsonBody : nil;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [adminController createLabel:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LabelCreationFailed", @"message": error.localizedDescription ?: @"Failed to create label"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    // com.atproto.label.getLabels - Admin-only label lookup
    [dispatcher registerComAtprotoLabelGetLabels:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                          response:response
                                  serviceDatabases:serviceDatabases
                                         jwtMinter:jwtMinter
                                   adminController:adminController]) {
            return;
        }
        
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSDictionary *params = [request.jsonBody isKindOfClass:[NSDictionary class]] ? request.jsonBody : nil;
        if (!params || params.count == 0) {
            NSString *paramError = nil;
            params = labelLookupParamsFromRequest(request, &paramError);
            if (!params) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": paramError ?: @"Invalid query parameters"}];
                return;
            }
        }

        NSError *error = nil;
        NSDictionary *result = [adminController getLabels:params error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": error.localizedDescription ?: @"Failed to fetch labels"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // com.atproto.label.subscribeLabels - WebSocket subscription endpoint
    [dispatcher registerComAtprotoLabelSubscribeLabels:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *cursorParam = [request queryParamForKey:@"cursor"];
        if (cursorParam.length > 0) {
            NSInteger cursor = 0;
            if (!parseStrictIntegerString(cursorParam, &cursor) || cursor < 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"cursor must be a non-negative integer"}];
                return;
            }
            if (cursor > 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"FutureCursor", @"message": @"Requested cursor is ahead of available label events"}];
                return;
            }
        }

        setSubscribeLabelsUpgradeRequired(response);
    }];
    
    // com.atproto.temp.fetchLabels - Deprecated label fetching
    [dispatcher registerMethod:@"com.atproto.temp.fetchLabels" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSInteger limit = 50;
        NSString *limitParam = [request queryParamForKey:@"limit"];
        if (limitParam.length > 0 && (!parseStrictIntegerString(limitParam, &limit) || limit < 1 || limit > 250)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"limit must be an integer between 1 and 250"}];
            return;
        }

        NSInteger sinceSeconds = 0;
        BOOL hasSince = NO;
        NSString *sinceParam = [request queryParamForKey:@"since"];
        if (sinceParam.length > 0) {
            hasSince = YES;
            if (!parseStrictIntegerString(sinceParam, &sinceSeconds) || sinceSeconds < 0) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"since must be a non-negative integer"}];
                return;
            }
        }

        NSError *queryError = nil;
        NSArray<NSDictionary *> *labels = loadFetchedLabels(serviceDatabases, hasSince, sinceSeconds, limit, &queryError);
        if (!labels) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": queryError.localizedDescription ?: @"Failed to fetch labels"}];
            return;
        }

        // Set deprecation headers
        [response setHeader:@"true" forKey:@"Deprecation"];
        [response setHeader:kTempFetchLabelsSunsetDate forKey:@"Sunset"];
        [response setHeader:kTempFetchLabelsSuccessorLink forKey:@"Link"];
        [response setHeader:kTempFetchLabelsDeprecationWarning forKey:@"Warning"];
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"labels": labels ?: @[]}];
    }];
    
    // com.atproto.temp.requestPhoneVerification - Phone verification
    [dispatcher registerMethod:@"com.atproto.temp.requestPhoneVerification" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *phoneNumber = body[@"phoneNumber"];
        if (!isLikelyPhoneNumber(phoneNumber)) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing or invalid phoneNumber"}];
            return;
        }

        NSError *providerError = nil;
        NSString *providerName = configuration.phoneVerificationProvider ?: @"none";
        PDSEnvironmentSecretsProvider *secretsProvider = [[PDSEnvironmentSecretsProvider alloc] init];
        id<PDSPhoneVerificationProvider> provider = [PDSPhoneVerificationProviderFactory providerWithName:providerName
                                                                                           configuration:@{}
                                                                                          secretsProvider:secretsProvider
                                                                                                    error:&providerError];
        if (!provider) {
            if ([providerError.domain isEqualToString:PDSPhoneVerificationProviderErrorDomain]
                && providerError.code == PDSPhoneVerificationProviderErrorNotConfigured) {
                response.statusCode = HttpStatusNotImplemented;
                [response setJsonBody:@{
                    @"error": @"PhoneVerificationNotConfigured",
                    @"message": providerError.localizedDescription ?: @"Phone verification provider is not configured"
                }];
                return;
            }
            if ([providerError.domain isEqualToString:PDSPhoneVerificationProviderErrorDomain]
                && providerError.code == PDSPhoneVerificationProviderErrorUnsupportedProvider) {
                response.statusCode = HttpStatusNotImplemented;
                [response setJsonBody:@{
                    @"error": @"UnsupportedPhoneVerificationProvider",
                    @"message": providerError.localizedDescription ?: @"Unsupported phone verification provider"
                }];
                return;
            }

            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"PhoneVerificationProviderError",
                @"message": providerError.localizedDescription ?: @"Failed to initialize phone verification provider"
            }];
            return;
        }

        NSError *requestError = nil;
        NSString *sessionID = [provider requestVerificationForPhoneNumber:phoneNumber error:&requestError];
        if (!sessionID) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{
                @"error": @"PhoneVerificationRequestFailed",
                @"message": requestError.localizedDescription ?: @"Failed to request phone verification"
            }];
            return;
        }

        response.statusCode = HttpStatusOK;
        NSMutableDictionary *responseBody = [NSMutableDictionary dictionary];
        if (sessionID.length > 0) {
            responseBody[@"sessionID"] = sessionID;
        }
        [response setJsonBody:responseBody];
    }];
    
    // com.atproto.temp.addReservedHandle - Admin endpoint to reserve handles
    [dispatcher registerMethod:@"com.atproto.temp.addReservedHandle" handler:^(HttpRequest *request, HttpResponse *response) {
        if (![XrpcAuthHelper authorizeAdminRequest:request
                                           response:response
                                   serviceDatabases:serviceDatabases
                                          jwtMinter:jwtMinter
                                    adminController:adminController]) {
            return;
        }
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *handle = body[@"handle"];
        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&handleError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidHandle", @"message": handleError.localizedDescription ?: @"Invalid handle"}];
            return;
        }

        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];
        NSError *reserveError = nil;
        if (![serviceDatabases reserveHandle:normalizedHandle error:&reserveError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"PersistenceFailed", @"message": reserveError.localizedDescription ?: @"Failed to reserve handle"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
    
    // com.atproto.temp.checkHandleAvailability - Check if handle is available
    [dispatcher registerMethod:@"com.atproto.temp.checkHandleAvailability" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *handle = [request queryParamForKey:@"handle"];
        NSError *handleError = nil;
        if (![ATProtoHandleValidator validateHandle:handle error:&handleError]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": handleError.localizedDescription ?: @"Invalid handle"}];
            return;
        }
        NSString *normalizedHandle = [ATProtoHandleValidator normalizeHandle:handle];

        NSString *email = [request queryParamForKey:@"email"];
        if (email.length > 0 && ![email containsString:@"@"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidEmail", @"message": @"Invalid email"}];
            return;
        }

        NSError *reservedError = nil;
        BOOL unavailable = ([serviceDatabases getAccountByHandle:normalizedHandle error:nil] != nil)
            || [serviceDatabases isHandleReserved:normalizedHandle error:&reservedError];
        if (reservedError) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"QueryFailed", @"message": reservedError.localizedDescription ?: @"Failed to check reserved handles"}];
            return;
        }

        NSDictionary *result = nil;
        if (unavailable) {
            // Build suggestions
            NSArray<NSString *> *parts = [normalizedHandle componentsSeparatedByString:@"."];
            NSMutableArray<NSDictionary *> *suggestions = [NSMutableArray array];
            if (parts.count >= 2) {
                NSString *stem = parts.firstObject.length > 0 ? parts.firstObject : @"user";
                NSString *domain = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"."];
                
                for (NSInteger suffix = 1; suffix <= 25 && suggestions.count < 3; suffix += 1) {
                    NSString *candidate = [NSString stringWithFormat:@"%@%ld.%@", stem, (long)suffix, domain];
                    NSError *candidateError = nil;
                    if (![ATProtoHandleValidator validateHandle:candidate error:&candidateError]) {
                        continue;
                    }
                    NSError *candidateReservedError = nil;
                    if ([serviceDatabases isHandleReserved:candidate error:&candidateReservedError] || candidateReservedError) {
                        continue;
                    }
                    if ([serviceDatabases getAccountByHandle:candidate error:nil]) {
                        continue;
                    }
                    [suggestions addObject:@{
                        @"handle": candidate,
                        @"method": @"numeric-suffix"
                    }];
                }
            }
            result = @{@"suggestions": suggestions ?: @[]};
        } else {
            result = @{};
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{
            @"handle": normalizedHandle,
            @"result": result
        }];
    }];
    
    // com.atproto.temp.checkSignupQueue - Check signup queue status
    [dispatcher registerMethod:@"com.atproto.temp.checkSignupQueue" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"activated": @YES}];
    }];
    
    // com.atproto.temp.dereferenceScope - Dereference OAuth scope references
    [dispatcher registerMethod:@"com.atproto.temp.dereferenceScope" handler:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodGET) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"GET" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected GET"}];
            return;
        }

        NSString *scopeReference = [request queryParamForKey:@"scope"];
        if (![scopeReference isKindOfClass:[NSString class]] || scopeReference.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing scope"}];
            return;
        }
        if (![scopeReference hasPrefix:@"ref:"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidScopeReference", @"message": @"scope must start with ref:"}];
            return;
        }

        NSString *resolvedScope = [scopeReference substringFromIndex:4];
        if (resolvedScope.length == 0
            || [resolvedScope rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidScopeReference", @"message": @"Invalid scope reference"}];
            return;
        }

        // Scope reference mapping
        NSDictionary<NSString *, NSString *> *mapping = @{
            @"com.atproto.transition:generic": @"atproto transition:generic",
            @"com.atproto.transition:email": @"atproto transition:email",
            @"com.atproto.transition:chat.bsky": @"atproto transition:generic transition:chat.bsky"
        };
        
        NSString *mappedScope = mapping[resolvedScope];
        if (![mappedScope isKindOfClass:[NSString class]] || mappedScope.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidScopeReference", @"message": @"Unknown scope reference"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"scope": mappedScope}];
    }];
    
    // com.atproto.temp.revokeAccountCredentials - Revoke all credentials for an account
    [dispatcher registerComAtprotoTempRevokeAccountCredentials:^(HttpRequest *request, HttpResponse *response) {
        if (request.method != HttpMethodPOST) {
            response.statusCode = HttpStatusMethodNotAllowed;
            [response setHeader:@"POST" forKey:@"Allow"];
            [response setJsonBody:@{@"error": @"MethodNotAllowed", @"message": @"Expected POST"}];
            return;
        }

        NSString *authHeader = [request headerForKey:@"Authorization"];
        NSString *did = [XrpcAuthHelper extractDIDFromAuthHeader:authHeader
                                                       jwtMinter:jwtMinter
                                                 adminController:adminController
                                                         request:request
                                                        response:response];
        if (!did) {
            if (response.statusCode == HttpStatusOK) {
                response.statusCode = HttpStatusUnauthorized;
                [response setJsonBody:@{@"error": @"AuthRequired", @"message": @"Valid authorization required"}];
            }
            return;
        }

        NSDictionary *body = request.jsonBody ?: @{};
        NSString *accountIdentifier = body[@"account"];
        NSString *targetDid = nil;
        NSError *resolveError = nil;
        if (![XrpcIdentityHelper resolveAccountIdentifierToDid:accountIdentifier
                                              serviceDatabases:serviceDatabases
                                                        outDid:&targetDid
                                                         error:&resolveError]) {
            if (resolveError.code == 404) {
                response.statusCode = HttpStatusNotFound;
                [response setJsonBody:@{@"error": @"AccountNotFound", @"message": resolveError.localizedDescription ?: @"Account not found"}];
            } else {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"InvalidRequest", @"message": resolveError.localizedDescription ?: @"Invalid account identifier"}];
            }
            return;
        }

        if (![targetDid isEqualToString:did]) {
            response.statusCode = HttpStatusForbidden;
            [response setJsonBody:@{@"error": @"Forbidden", @"message": @"Cannot revoke credentials for other accounts"}];
            return;
        }

        NSError *deleteError = nil;
        if (![serviceDatabases deleteRefreshTokensForAccount:targetDid error:&deleteError]) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"CredentialRevocationFailed", @"message": deleteError.localizedDescription ?: @"Failed to revoke sessions"}];
            return;
        }

        NSError *listError = nil;
        NSArray<NSDictionary *> *appPasswords = [serviceDatabases listAppPasswordsForAccount:targetDid error:&listError];
        if (listError) {
            response.statusCode = HttpStatusInternalServerError;
            [response setJsonBody:@{@"error": @"CredentialRevocationFailed", @"message": listError.localizedDescription ?: @"Failed to list app passwords"}];
            return;
        }

        for (NSDictionary *entry in appPasswords) {
            NSString *name = entry[@"name"];
            if (name.length == 0) {
                continue;
            }

            NSError *revokeError = nil;
            BOOL revoked = [serviceDatabases revokeAppPasswordForAccount:targetDid name:name error:&revokeError];
            if (!revoked && revokeError) {
                response.statusCode = HttpStatusInternalServerError;
                [response setJsonBody:@{@"error": @"CredentialRevocationFailed", @"message": revokeError.localizedDescription ?: @"Failed to revoke app passwords"}];
                return;
            }
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}

@end
