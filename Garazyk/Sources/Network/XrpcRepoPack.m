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
#import "Core/ATProtoValidator.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabaseAccount.h"
#import "Debug/GZLogger.h"

NSString * const PDSRepoPackValidationErrorDomain = @"com.atproto.pds.xrpc.repo.validation";

BOOL isReplyNotAllowedError(NSError *error) {
    return [error.localizedDescription containsString:@"ReplyNotAllowed"];
}

BOOL rejectUnavailableRepoDid(NSString *did,
                              id<XrpcRoutePackServices> services,
                              ATProtoHttpResponse *response) {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    id<PDSAdminController> adminController = services.adminController;
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
        return YES;
    }

    PDSServiceDatabases *resolvedDatabases = serviceDatabases;
    id<PDSAdminController> resolvedAdminController = adminController;

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
                                     id<XrpcRoutePackServices> services,
                                     ATProtoHttpResponse *response) {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
    id<PDSAdminController> adminController = services.adminController;
    if (did.length == 0) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"RepoNotFound", @"message": @"Repository not found"}];
        return YES;
    }

    PDSServiceDatabases *resolvedDatabases = serviceDatabases;
    id<PDSAdminController> resolvedAdminController = adminController;

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
                          id<XrpcRoutePackServices> services,
                          ATProtoHttpResponse *response) {
    PDSServiceDatabases *serviceDatabases = services.serviceDatabases;
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

NSString *normalizedApplyWriteAction(NSDictionary *write) {
    static NSDictionary<NSString *, NSString *> *actionsByType;
    static NSSet<NSString *> *validActions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        actionsByType = @{
            @"com.atproto.repo.applyWrites#create": @"create",
            @"com.atproto.repo.applyWrites#update": @"update",
            @"com.atproto.repo.applyWrites#delete": @"delete",
        };
        validActions = [NSSet setWithArray:@[@"create", @"update", @"delete"]];
    });

    NSString *type = [write[@"$type"] isKindOfClass:[NSString class]]
        ? write[@"$type"]
        : nil;
    NSString *typeAction = type.length > 0 ? actionsByType[type] : nil;
    if (type.length > 0 && !typeAction) {
        return nil;
    }

    NSString *legacyAction = [write[@"action"] isKindOfClass:[NSString class]]
        ? write[@"action"]
        : nil;
    if (legacyAction.length > 0 && ![validActions containsObject:legacyAction]) {
        return nil;
    }
    if (typeAction && legacyAction && ![typeAction isEqualToString:legacyAction]) {
        return nil;
    }
    return typeAction ?: legacyAction;
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

        NSDictionary *writeObject = (NSDictionary *)write;
        NSString *action = normalizedApplyWriteAction(writeObject);
        if (action.length == 0) {
            if (error) {
                *error = repoPackValidationError(
                    PDSRepoPackValidationErrorInvalidRequest,
                    @"Each write must have a valid applyWrites $type discriminator");
            }
            return NO;
        }

        NSString *collection = [writeObject[@"collection"] isKindOfClass:[NSString class]]
            ? writeObject[@"collection"]
            : nil;
        NSError *collectionError = nil;
        if (collection.length == 0 ||
            ![ATProtoValidator validateNSID:collection error:&collectionError]) {
            if (error) {
                *error = repoPackValidationError(
                    PDSRepoPackValidationErrorInvalidRequest,
                    collectionError.localizedDescription ?: @"Each write must have a valid collection NSID");
            }
            return NO;
        }

        NSString *rkey = [writeObject[@"rkey"] isKindOfClass:[NSString class]]
            ? writeObject[@"rkey"]
            : nil;
        if (([action isEqualToString:@"update"] || [action isEqualToString:@"delete"]) &&
            rkey.length == 0) {
            if (error) {
                *error = repoPackValidationError(
                    PDSRepoPackValidationErrorInvalidRequest,
                    [NSString stringWithFormat:@"%@ writes require rkey", action]);
            }
            return NO;
        }
        if (rkey.length > 0) {
            NSError *rkeyError = nil;
            // Record keys are 1-512 characters for every action; createRecord
            // applies no extra cap, so applyWrites#create must not either.
            if (![ATProtoValidator validateRkey:rkey error:&rkeyError]) {
                if (error) {
                    *error = repoPackValidationError(
                        PDSRepoPackValidationErrorInvalidRequest,
                        rkeyError.localizedDescription ?: @"Invalid record key");
                }
                return NO;
            }
        }

        id value = writeObject[@"value"];
        if (!value || value == (id)[NSNull null]) {
            value = writeObject[@"record"];
        }
        if (!value || value == (id)[NSNull null]) {
            if (![action isEqualToString:@"delete"]) {
                if (error) {
                    *error = repoPackValidationError(
                        PDSRepoPackValidationErrorInvalidRequest,
                        [NSString stringWithFormat:@"%@ writes require a record value", action]);
                }
                return NO;
            }
            continue;
        }
        if (![value isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = repoPackValidationError(
                    PDSRepoPackValidationErrorInvalidRequest,
                    @"Write record value must be an object");
            }
            return NO;
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

@implementation ATProtoXrpcRepoPack

+ (NSString *)routePackIdentifier {
  return @"com.atproto.repo";
}

+ (void)registerWithDispatcher:(ATProtoXrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
    [self registerRecordRoutesWithDispatcher:dispatcher services:services];
    [self registerBlobRoutesWithDispatcher:dispatcher services:services];
    [self registerImportRoutesWithDispatcher:dispatcher services:services];
    [self registerDescribeRoutesWithDispatcher:dispatcher services:services];
}

@end
