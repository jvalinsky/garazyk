// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Core/ATProtoMASLDocument.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/CID.h"
#import "Core/CID+DASL.h"
#include <string.h>

NSString * const ATProtoMASLErrorDomain = @"com.atproto.masl";

static NSError *MASLError(ATProtoMASLErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoMASLErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL MASLIsCID(id value) {
    return [value isKindOfClass:[ATProtoCID class]] &&
           [(ATProtoCID *)value isDASLConformantForProfile:ATProtoDASLCIDProfileBig];
}

static BOOL MASLIsStringMap(id value) {
    if (![value isKindOfClass:[NSDictionary class]]) return NO;
    for (id key in (NSDictionary *)value) {
        if (![key isKindOfClass:[NSString class]]) return NO;
    }
    return YES;
}

static BOOL MASLIsIntegerOne(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    const char *type = [(NSNumber *)value objCType];
    // Exclude BOOL/char encodings explicitly. The remaining scalar encodings
    // are integral on both Apple Foundation and GNUstep.
    if (!type || strlen(type) != 1 || strchr("islqiuILQ", type[0]) == NULL) return NO;
    return [(NSNumber *)value longLongValue] == 1;
}

static NSSet<NSString *> *MASLHTTPHeaderAllowList(void) {
    static NSSet<NSString *> *headers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        headers = [NSSet setWithArray:@[
            @"content-disposition", @"content-encoding", @"content-language",
            @"content-security-policy", @"content-type", @"link",
            @"permissions-policy", @"referrer-policy", @"service-worker-allowed",
            @"sourcemap", @"speculation-rules", @"supports-loading-mode",
            @"x-content-type-options"
        ]];
    });
    return headers;
}

static BOOL MASLIsAbsoluteResourcePath(NSString *path) {
    return [path isKindOfClass:[NSString class]] &&
           path.length > 0 && [path hasPrefix:@"/"] &&
           ![path containsString:@"?"] && ![path containsString:@"#"];
}

static BOOL MASLPathExists(NSDictionary<NSString *, NSDictionary *> *resources,
                           NSString *path) {
    return MASLIsAbsoluteResourcePath(path) && resources[path] != nil;
}

static void MASLSetError(NSError **error, ATProtoMASLErrorCode code, NSString *message) {
    if (error) *error = MASLError(code, message);
}

static BOOL MASLValidateManifestReferences(NSDictionary *map,
                                           NSDictionary<NSString *, NSDictionary *> *resources,
                                           NSError **error) {
    for (NSString *field in @[@"icons", @"screenshots"]) {
        id entries = map[field];
        if (!entries) continue;
        if (![entries isKindOfClass:[NSArray class]]) {
            MASLSetError(error, ATProtoMASLErrorInvalidField,
                         [NSString stringWithFormat:@"MASL %@ must be an array", field]);
            return NO;
        }
        for (id entry in (NSArray *)entries) {
            if (![entry isKindOfClass:[NSDictionary class]]) {
                MASLSetError(error, ATProtoMASLErrorInvalidReference,
                             [NSString stringWithFormat:@"MASL %@ entries must be maps", field]);
                return NO;
            }
            id path = entry[@"src"];
            if (!MASLPathExists(resources, path)) {
                MASLSetError(error, ATProtoMASLErrorInvalidReference,
                             [NSString stringWithFormat:@"MASL %@ src must name a bundle resource", field]);
                return NO;
            }
        }
    }
    return YES;
}

@implementation ATProtoMASLDocument

+ (nullable instancetype)documentWithObject:(id)object error:(NSError **)error {
    if (![object isKindOfClass:[NSDictionary class]]) {
        MASLSetError(error, ATProtoMASLErrorInvalidDocument, @"MASL document must be a DRISL map");
        return nil;
    }
    NSDictionary *map = object;
    for (id key in map) {
        if (![key isKindOfClass:[NSString class]]) {
            MASLSetError(error, ATProtoMASLErrorInvalidDocument,
                         @"MASL object keys must be text strings");
            return nil;
        }
    }

    id type = map[@"$type"];
    if (type && (![type isKindOfClass:[NSString class]] ||
                 ![type isEqualToString:@"ing.dasl.masl"])) {
        MASLSetError(error, ATProtoMASLErrorInvalidField,
                     @"MASL $type, when present, must be ing.dasl.masl");
        return nil;
    }

    id srcValue = map[@"src"];

    id prevValue = map[@"prev"];
    if (prevValue && !MASLIsCID(prevValue)) {
        MASLSetError(error, ATProtoMASLErrorInvalidField, @"MASL prev must be a DASL CID link");
        return nil;
    }

    id resourcesValue = map[@"resources"];
    NSDictionary<NSString *, NSDictionary *> *resources = nil;
    if (resourcesValue) {
        if (!MASLIsStringMap(resourcesValue)) {
            MASLSetError(error, ATProtoMASLErrorInvalidResource, @"MASL resources must be a string-keyed map");
            return nil;
        }
        resources = resourcesValue;
        if (!resources[@"/"]) {
            MASLSetError(error, ATProtoMASLErrorInvalidResourcePath,
                         @"MASL bundle resources must contain the root path /");
            return nil;
        }
        for (NSString *path in resources) {
            if (!MASLIsAbsoluteResourcePath(path)) {
                MASLSetError(error, ATProtoMASLErrorInvalidResourcePath,
                             [NSString stringWithFormat:@"MASL resource path is not absolute: %@", path]);
                return nil;
            }
            id resource = resources[path];
            if (![resource isKindOfClass:[NSDictionary class]]) {
                MASLSetError(error, ATProtoMASLErrorInvalidResource,
                             [NSString stringWithFormat:@"MASL resource %@ must be a map", path]);
                return nil;
            }
            id resourceSrc = resource[@"src"];
            if (!MASLIsCID(resourceSrc)) {
                MASLSetError(error, ATProtoMASLErrorInvalidResource,
                             [NSString stringWithFormat:@"MASL resource %@ must contain a DASL src CID", path]);
                return nil;
            }
        }
    }

    if (resources && !MASLValidateManifestReferences(map, resources, error)) {
        return nil;
    }

    // MASL's processing rule is that resources wins when both are present;
    // retaining src is useful for round-trip fidelity but does not alter mode.
    if (!resources && srcValue && !MASLIsCID(srcValue)) {
        MASLSetError(error, ATProtoMASLErrorInvalidField, @"MASL src must be a DASL CID link");
        return nil;
    }
    ATProtoMASLDocument *document = [[self alloc] init];
    document->_object = [map copy];
    document->_bundle = resources != nil;
    document->_src = resources ? nil : [srcValue copy];
    document->_prev = [prevValue copy];
    document->_resources = [resources copy];
    return document;
}

+ (nullable instancetype)documentWithDRISLData:(NSData *)data error:(NSError **)error {
    NSError *decodeError = nil;
    id object = [ATProtoDagCBOR decodeData:data profile:ATProtoDRISLProfileDRISL error:&decodeError];
    if (!object) {
        if (error) *error = decodeError ?: MASLError(ATProtoMASLErrorInvalidDocument, @"Could not decode MASL DRISL data");
        return nil;
    }
    return [self documentWithObject:object error:error];
}

- (nullable NSData *)DRISLDataWithError:(NSError **)error {
    return [ATProtoDagCBOR encodeObject:self.object
                                profile:ATProtoDRISLProfileDRISL
                                  error:error];
}

- (BOOL)validateForCARWithError:(NSError **)error {
    id version = self.object[@"version"];
    id roots = self.object[@"roots"];
    if (!version && !roots) return YES;
    if (!MASLIsIntegerOne(version)) {
        MASLSetError(error, ATProtoMASLErrorNotCARCompatible,
                     @"CAR-compatible MASL metadata requires integer version 1");
        return NO;
    }
    if (![roots isKindOfClass:[NSArray class]]) {
        MASLSetError(error, ATProtoMASLErrorNotCARCompatible,
                     @"CAR-compatible MASL metadata requires a roots array");
        return NO;
    }
    for (id root in (NSArray *)roots) {
        if (!MASLIsCID(root)) {
            MASLSetError(error, ATProtoMASLErrorNotCARCompatible,
                         @"CAR-compatible MASL roots must contain only DASL CID links");
            return NO;
        }
    }
    return YES;
}

- (nullable NSDictionary<NSString *, NSString *> *)httpHeadersForPath:(nullable NSString *)path
                                                                  error:(NSError **)error {
    NSDictionary *source = self.bundle ? self.resources[path ?: @""] : self.object;
    if (self.bundle && !source) {
        MASLSetError(error, ATProtoMASLErrorInvalidResourcePath,
                     [NSString stringWithFormat:@"MASL bundle has no resource at path %@", path ?: @"(null)"]);
        return nil;
    }
    if (![source isKindOfClass:[NSDictionary class]]) {
        MASLSetError(error, ATProtoMASLErrorInvalidResource, @"MASL header source is not a map");
        return nil;
    }

    NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
    NSSet *allowList = MASLHTTPHeaderAllowList();
    for (NSString *key in source) {
        // The allow-list is deliberately case-sensitive. MASL says incorrectly
        // cased headers must be ignored, not normalized into authority.
        if (![allowList containsObject:key]) continue;
        id value = source[key];
        if (![value isKindOfClass:[NSString class]]) continue;
        if ([key isEqualToString:@"sourcemap"] || [key isEqualToString:@"speculation-rules"]) {
            if (!self.bundle || !MASLPathExists(self.resources, value)) continue;
        }
        headers[key] = value;
    }
    return [headers copy];
}

@end
