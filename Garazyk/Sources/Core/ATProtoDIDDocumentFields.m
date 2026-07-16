// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/DID.h"

@implementation ATProtoDIDDocumentFields

+ (nullable NSString *)normalizedHandleFromDocument:(DIDDocument *)document {
    for (id entry in document.alsoKnownAs ?: @[]) {
        if (![entry isKindOfClass:[NSString class]]) continue;
        NSString *candidate = (NSString *)entry;
        if ([candidate hasPrefix:@"at://"]) {
            candidate = [candidate substringFromIndex:5];
        }
        if ([candidate hasSuffix:@"/"]) {
            candidate = [candidate substringToIndex:candidate.length - 1];
        }
        if (candidate.length > 0) {
            return [candidate lowercaseString];
        }
    }
    return nil;
}

+ (nullable NSString *)pdsEndpointFromDocument:(DIDDocument *)document {
    for (id entry in document.service ?: @[]) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *service = (NSDictionary *)entry;
        if (![service[@"type"] isEqualToString:@"AtprotoPersonalDataServer"]) continue;
        NSString *endpoint = [service[@"serviceEndpoint"] isKindOfClass:[NSString class]]
            ? service[@"serviceEndpoint"]
            : nil;
        if (endpoint.length > 0) return endpoint;
    }
    return nil;
}

+ (nullable NSString *)atprotoSigningKeyMultibaseFromDocument:(DIDDocument *)document {
    NSString *modernKey = [self signingKeyFromModernVerificationMethods:document.jsonDictionary[@"verificationMethod"]];
    if (modernKey.length > 0) return modernKey;
    return [self signingKeyFromLegacyVerificationMethods:document.jsonDictionary[@"verificationMethods"]];
}

+ (nullable NSString *)strictAtprotoSigningKeyMultibaseFromDocument:(DIDDocument *)document {
    return [self signingKeyFromDocument:document fragment:@"#atproto"];
}

+ (nullable NSString *)spaceSigningKeyMultibaseFromDocument:(DIDDocument *)document {
    NSString *key = [self dedicatedSpaceSigningKeyMultibaseFromDocument:document];
    return key.length > 0 ? key : [self signingKeyFromDocument:document fragment:@"#atproto"];
}

+ (nullable NSString *)dedicatedSpaceSigningKeyMultibaseFromDocument:(DIDDocument *)document {
    return [self signingKeyFromDocument:document fragment:@"#atproto_space"];
}

+ (nullable NSString *)spaceHostEndpointFromDocument:(DIDDocument *)document {
    NSString *endpoint = [self endpointFromDocument:document fragment:@"#atproto_space_host"];
    return endpoint.length > 0 ? endpoint : [self endpointFromDocument:document fragment:@"#atproto_pds"];
}

+ (nullable NSString *)signingKeyFromDocument:(DIDDocument *)document fragment:(NSString *)fragment {
    NSDictionary *json = document.jsonDictionary;
    id modern = json[@"verificationMethod"];
    if ([modern isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)modern) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *method = (NSDictionary *)entry;
            NSString *identifier = [method[@"id"] isKindOfClass:[NSString class]] ? method[@"id"] : nil;
            NSString *key = [method[@"publicKeyMultibase"] isKindOfClass:[NSString class]]
                ? method[@"publicKeyMultibase"] : nil;
            if ([self identifier:identifier matchesDocument:document fragment:fragment] && key.length > 0) {
                return key;
            }
        }
    }

    id legacy = json[@"verificationMethods"];
    if (![legacy isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *methods = (NSDictionary *)legacy;
    for (NSString *keyName in [self legacyNamesForDocument:document fragment:fragment]) {
        NSString *key = [self signingKeyFromLegacyValue:methods[keyName]];
        if (key.length > 0) return key;
    }
    return nil;
}

+ (nullable NSString *)endpointFromDocument:(DIDDocument *)document fragment:(NSString *)fragment {
    for (id entry in document.service ?: @[]) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *service = (NSDictionary *)entry;
        NSString *identifier = [service[@"id"] isKindOfClass:[NSString class]] ? service[@"id"] : nil;
        NSString *endpoint = [service[@"serviceEndpoint"] isKindOfClass:[NSString class]]
            ? service[@"serviceEndpoint"] : nil;
        if (![self identifier:identifier matchesDocument:document fragment:fragment]) continue;
        if ([self isUsableServiceEndpoint:endpoint]) return endpoint;
    }
    return nil;
}

+ (BOOL)identifier:(NSString *)identifier matchesDocument:(DIDDocument *)document fragment:(NSString *)fragment {
    return [identifier isEqualToString:fragment] ||
           [identifier isEqualToString:[document.id stringByAppendingString:fragment]];
}

+ (NSArray<NSString *> *)legacyNamesForDocument:(DIDDocument *)document fragment:(NSString *)fragment {
    NSString *bare = [fragment substringFromIndex:1];
    return @[bare, fragment, [document.id stringByAppendingString:fragment]];
}

+ (BOOL)isUsableServiceEndpoint:(NSString *)endpoint {
    if (endpoint.length == 0) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithString:endpoint];
    if (!components || !([components.scheme isEqualToString:@"https"] || [components.scheme isEqualToString:@"http"])) {
        return NO;
    }
    return components.host.length > 0 && components.user.length == 0 && components.password.length == 0 &&
           components.query.length == 0 && components.fragment.length == 0;
}

+ (nullable NSString *)signingKeyFromModernVerificationMethods:(id)verificationMethods {
    if (![verificationMethods isKindOfClass:[NSArray class]]) return nil;

    NSString *fallback = nil;
    for (id entry in (NSArray *)verificationMethods) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *method = (NSDictionary *)entry;
        NSString *key = [method[@"publicKeyMultibase"] isKindOfClass:[NSString class]]
            ? method[@"publicKeyMultibase"]
            : nil;
        if (key.length == 0) continue;

        NSString *methodId = [method[@"id"] isKindOfClass:[NSString class]] ? method[@"id"] : nil;
        if ([methodId hasSuffix:@"#atproto"]) return key;
        if (!fallback) fallback = key;
    }
    return fallback;
}

+ (nullable NSString *)signingKeyFromLegacyVerificationMethods:(id)verificationMethods {
    if (![verificationMethods isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *methods = (NSDictionary *)verificationMethods;
    NSString *atproto = [self signingKeyFromLegacyValue:methods[@"atproto"]];
    if (atproto.length > 0) return atproto;

    NSString *fallback = nil;
    for (id key in methods) {
        NSString *candidate = [self signingKeyFromLegacyValue:methods[key]];
        if (candidate.length == 0) continue;
        NSString *methodName = [key isKindOfClass:[NSString class]] ? key : nil;
        if ([methodName hasSuffix:@"#atproto"]) return candidate;
        if (!fallback) fallback = candidate;
    }
    return fallback;
}

+ (nullable NSString *)signingKeyFromLegacyValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        NSString *key = (NSString *)value;
        return key.length > 0 ? key : nil;
    }
    if (![value isKindOfClass:[NSDictionary class]]) return nil;
    NSDictionary *method = (NSDictionary *)value;
    NSString *key = [method[@"publicKeyMultibase"] isKindOfClass:[NSString class]]
        ? method[@"publicKeyMultibase"]
        : nil;
    return key.length > 0 ? key : nil;
}

@end
