// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/WebAuthnDomain.h"
#import "Auth/Base32Utils.h"

@implementation ATProtoWebAuthnRelyingParty
@end

@implementation ATProtoWebAuthnUser
@end

@implementation ATProtoWebAuthnPubKeyCredParam
@end

@implementation ATProtoWebAuthnRegistrationOptions
@end

@implementation ATProtoWebAuthnCredentialDescriptor
@end

@implementation ATProtoWebAuthnAssertionOptions
@end

@implementation ATProtoWebAuthnDomain

+ (NSDictionary *)dictionaryFromRegistrationOptions:(ATProtoWebAuthnRegistrationOptions *)options {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"challenge"] = [ATProtoBase32Utils base32StringFromData:options.challenge];
    dict[@"rp"] = @{@"name": options.rp.name, @"id": options.rp.identifier};
    dict[@"user"] = @{
        @"id": [ATProtoBase32Utils base32StringFromData:options.user.identifier],
        @"name": options.user.name,
        @"displayName": options.user.displayName
    };
    
    NSMutableArray *pubKeyCredParams = [NSMutableArray array];
    for (ATProtoWebAuthnPubKeyCredParam *param in options.pubKeyCredParams) {
        [pubKeyCredParams addObject:@{@"type": param.type, @"alg": @(param.alg)}];
    }
    dict[@"pubKeyCredParams"] = pubKeyCredParams;
    
    dict[@"timeout"] = @(options.timeout * 1000); // ms
    dict[@"attestation"] = options.attestation ?: @"none";
    
    return [dict copy];
}

+ (NSDictionary *)dictionaryFromAssertionOptions:(ATProtoWebAuthnAssertionOptions *)options {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"challenge"] = [ATProtoBase32Utils base32StringFromData:options.challenge];
    dict[@"timeout"] = @(options.timeout * 1000);
    dict[@"rpId"] = options.rpId;
    dict[@"userVerification"] = options.userVerification ?: @"preferred";
    
    if (options.allowCredentials.count > 0) {
        NSMutableArray *creds = [NSMutableArray array];
        for (ATProtoWebAuthnCredentialDescriptor *desc in options.allowCredentials) {
            NSMutableDictionary *c = [NSMutableDictionary dictionary];
            c[@"type"] = desc.type;
            c[@"id"] = [ATProtoBase32Utils base32StringFromData:desc.credentialId];
            if (desc.transports) {
                c[@"transports"] = desc.transports;
            }
            [creds addObject:c];
        }
        dict[@"allowCredentials"] = creds;
    }
    
    return [dict copy];
}

@end
