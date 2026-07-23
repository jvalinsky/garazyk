// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcRepoPack.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Network/XrpcRepoPack+Records.h"
#import "Network/XrpcRepoPack+Blobs.h"
#import "Network/XrpcRepoPack+Import.h"
#import "Network/XrpcRepoPack+Describe.h"
#import "Network/XrpcRoutePackServices.h"
#import "Network/HttpResponse.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabaseAccount.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"

NSString * const PDSRepoPackValidationErrorDomain = @"com.atproto.pds.xrpc.repo.validation";

BOOL isReplyNotAllowedError(NSError *error) {
    return [error.localizedDescription containsString:@"ReplyNotAllowed"];
}

BOOL rejectUnavailableRepoDid(NSString *did,
                              PDSServiceDatabases *serviceDatabases,
                              id<PDSAdminController> adminController,
                              HttpResponse *response) {
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
        return YES;
    }

    PDSServiceDatabases *resolvedDatabases = serviceDatabases ?: [PDSController sharedController].serviceDatabases;
    id<PDSAdminController> resolvedAdminController = adminController ?: [PDSController sharedController].adminController;

    NSError *accountError = nil;
    PDSDatabaseAccount *account = [resolvedDatabases getAccountByDid:did error:&accountError];
    if (!account) {
        GZ_LOG_WARN(@"repo availability: account lookup failed for did=%@ error=%@",
                    did, accountError.localizedDescription ?: @"none");
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
        return YES;
    }

    NSString *status = [account.status lowercaseString];
    if (status.length > 0 && ![status isEqualToString:@"active"]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"AccountInactive", @"message": @"Account is not active"}];
        return YES;
    }

    NSError *takedownError = nil;
    if ([resolvedAdminController isAccountTakedownActive:did error:&takedownError]) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"AccountTakedown",
            @"message": @"Repository has been taken down by the host",
        }];
        return YES;
    }

    return NO;
}

BOOL rejectUnavailableRepoDidIfKnown(NSString *did,
                                     PDSServiceDatabases *serviceDatabases,
                                     id<PDSAdminController> adminController,
                                     HttpResponse *response) {
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
        return YES;
    }

    PDSServiceDatabases *resolvedDatabases = serviceDatabases ?: [PDSController sharedController].serviceDatabases;
    id<PDSAdminController> resolvedAdminController = adminController ?: [PDSController sharedController].adminController;

    NSError *accountError = nil;
    PDSDatabaseAccount *account = [resolvedDatabases getAccountByDid:did error:&accountError];
    if (!account) {
        GZ_LOG_WARN(@"repo availability: allowing existing record with missing account row did=%@ error=%@",
                    did, accountError.localizedDescription ?: @"none");
        return NO;
    }

    NSString *status = [account.status lowercaseString];
    if (status.length > 0 && ![status isEqualToString:@"active"]) {
        response.statusCode = HttpStatusForbidden;
        [response setJsonBody:@{@"error": @"AccountInactive", @"message": @"Account is not active"}];
        return YES;
    }

    NSError *takedownError = nil;
    if ([resolvedAdminController isAccountTakedownActive:did error:&takedownError]) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"AccountTakedown",
            @"message": @"Repository has been taken down by the host",
        }];
        return YES;
    }

    return NO;
}

BOOL rejectRecordTakedown(NSString *uri,
                          PDSServiceDatabases *serviceDatabases,
                          HttpResponse *response) {
    NSError *dbError = nil;
    PDSDatabase *database = [serviceDatabases serviceDatabaseWithError:&dbError];
    if (!database) {
        return NO;
    }
    NSError *takedownError = nil;
    if ([database isRecordTakedownActive:uri error:&takedownError]) {
        response.statusCode = HttpStatusGone;
        [response setJsonBody:@{
            @"error": @"RecordTakedown",
            @"message": @"Record has been taken down by the host",
        }];
        return YES;
    }
    return NO;
}

PDSValidationMode validationModeFromValidateParameter(id validateParam) {
    if (!validateParam || validateParam == (id)[NSNull null]) {
        // Per lexicon: unset -> validate only for known Lexicons.
        return PDSValidationModeOptimistic;
    }
    if ([validateParam isKindOfClass:[NSNumber class]]) {
        return [validateParam boolValue] ? PDSValidationModeRequired : PDSValidationModeOff;
    }
    if ([validateParam isKindOfClass:[NSString class]]) {
        NSString *lower = [(NSString *)validateParam lowercaseString];
        if ([lower isEqualToString:@"true"]) return PDSValidationModeRequired;
        if ([lower isEqualToString:@"false"]) return PDSValidationModeOff;
    }
    // Default to optimistic to avoid surprising hard failures on unknown types.
    return PDSValidationModeOptimistic;
}

NSString *normalizedMimeType(NSString *contentType) {
    NSString *lowerContentType = [[contentType ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[lowerContentType componentsSeparatedByString:@";"].firstObject ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

BOOL isActiveUploadMimeType(NSString *contentType) {
    static NSSet<NSString *> *activeTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeTypes = [NSSet setWithArray:@[
            @"text/html",
            @"text/css",
            @"text/javascript",
            @"application/javascript",
            @"application/xhtml+xml",
            @"application/xml",
            @"image/svg+xml",
            @"application/postscript",
        ]];
    });
    return [activeTypes containsObject:normalizedMimeType(contentType)];
}

NSError *repoPackValidationError(PDSRepoPackValidationErrorCode code, NSString *message) {
    return [NSError errorWithDomain:PDSRepoPackValidationErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Invalid request"}];
}

BOOL validateApplyWritesPayload(id writes, NSError **error) {
    static const NSUInteger kPDSApplyWritesMaxCount = 200;
    static const NSUInteger kPDSApplyWritesMaxRecordBytes = 256 * 1024;
    static const NSUInteger kPDSApplyWritesMaxAggregateRecordBytes = 4 * 1024 * 1024;

    if (![writes isKindOfClass:[NSArray class]]) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Missing or invalid writes array");
        return NO;
    }

    NSArray *writesArray = (NSArray *)writes;
    if (writesArray.count > kPDSApplyWritesMaxCount) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Too many writes in batch");
        return NO;
    }

    NSUInteger aggregateBytes = 0;
    for (id write in writesArray) {
        if (![write isKindOfClass:[NSDictionary class]]) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Each write must be an object");
            return NO;
        }

        id value = ((NSDictionary *)write)[@"value"];
        if (!value || value == (id)[NSNull null]) {
            value = ((NSDictionary *)write)[@"record"];
        }
        if (!value || value == (id)[NSNull null]) {
            continue;
        }
        if (![NSJSONSerialization isValidJSONObject:value]) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Write record value must be JSON-serializable");
            return NO;
        }

        NSError *jsonError = nil;
        NSData *recordData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&jsonError];
        if (!recordData) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, jsonError.localizedDescription ?: @"Invalid record value");
            return NO;
        }
        if (recordData.length > kPDSApplyWritesMaxRecordBytes) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Record payload too large");
            return NO;
        }
        aggregateBytes += recordData.length;
        if (aggregateBytes > kPDSApplyWritesMaxAggregateRecordBytes) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Aggregate write payload too large");
            return NO;
        }
    }

    return YES;
}

NSString *normalizedAtHandleFromAlsoKnownAs(NSArray<NSString *> *alsoKnownAs) {
    if (!alsoKnownAs || alsoKnownAs.count == 0) {
        return nil;
    }
    
    for (NSString *aka in alsoKnownAs) {
        if (![aka isKindOfClass:[NSString class]]) {
            continue;
        }
        if ([aka hasPrefix:@"at://"]) {
            NSString *handle = [aka substringFromIndex:5];
            return [handle lowercaseString];
        }
    }
    return nil;
}

@implementation XrpcRepoPack

+ (NSString *)routePackIdentifier {
  return @"com.atproto.repo";
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    [self registerRecordRoutesWithDispatcher:dispatcher services:services];
    [self registerBlobRoutesWithDispatcher:dispatcher services:services];
    [self registerImportRoutesWithDispatcher:dispatcher services:services];
    [self registerDescribeRoutesWithDispatcher:dispatcher services:services];
}

@end
