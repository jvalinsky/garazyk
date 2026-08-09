// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  XrpcErrorHelper.m
//  ATProtoPDS
//
//  Error response helper implementation for XRPC endpoints.
//

#import "Network/XrpcErrorHelper.h"

@implementation XrpcErrorHelper

#pragma mark - Standard Error Responses

+ (void)setAuthenticationError:(ATProtoHttpResponse *)response
                       message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusUnauthorized
         errorCode:@"AuthRequired"
           message:message ?: @"Authentication required"];
}

+ (void)setAuthorizationError:(ATProtoHttpResponse *)response
                      message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusForbidden
         errorCode:@"Forbidden"
           message:message ?: @"Forbidden"];
}

+ (void)setValidationError:(ATProtoHttpResponse *)response
                   message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusBadRequest
         errorCode:@"InvalidRequest"
           message:message ?: @"Invalid request"];
}

+ (void)setNotFoundError:(ATProtoHttpResponse *)response
                 message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusNotFound
         errorCode:@"NotFound"
           message:message ?: @"Not found"];
}

+ (void)setInternalServerError:(ATProtoHttpResponse *)response
                       message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusInternalServerError
         errorCode:@"InternalServerError"
           message:message ?: @"Internal server error"];
}

+ (void)setMethodNotAllowedError:(ATProtoHttpResponse *)response
                   allowedMethod:(NSString *)allowedMethod
                         message:(NSString *)message {
    response.statusCode = HttpStatusMethodNotAllowed;
    if (allowedMethod.length > 0) {
        [response setHeader:allowedMethod forKey:@"Allow"];
    }
    [response setJsonBody:@{
        @"error": @"MethodNotAllowed",
        @"message": message ?: [NSString stringWithFormat:@"Expected %@", allowedMethod]
    }];
}

#pragma mark - Custom Error Response

+ (void)setError:(ATProtoHttpResponse *)response
      statusCode:(HttpStatusCode)statusCode
       errorCode:(NSString *)errorCode
         message:(NSString *)message {
    response.statusCode = statusCode;
    [response setJsonBody:@{
        @"error": errorCode,
        @"message": message
    }];
}

#pragma mark - Convenience Methods

+ (void)setInvalidRequestError:(ATProtoHttpResponse *)response
                       message:(NSString *)message {
    [self setError:response
        statusCode:HttpStatusBadRequest
         errorCode:@"InvalidRequest"
           message:message];
}

+ (void)setAccountNotFoundError:(ATProtoHttpResponse *)response
                     identifier:(NSString *)identifier {
    [self setError:response
        statusCode:HttpStatusNotFound
         errorCode:@"AccountNotFound"
           message:[NSString stringWithFormat:@"Account not found: %@", identifier]];
}

+ (void)setLexiconNotFoundError:(ATProtoHttpResponse *)response
                           nsid:(NSString *)nsid {
    [self setError:response
        statusCode:HttpStatusNotFound
         errorCode:@"LexiconNotFound"
           message:[NSString stringWithFormat:@"Lexicon not found: %@", nsid]];
}

@end
