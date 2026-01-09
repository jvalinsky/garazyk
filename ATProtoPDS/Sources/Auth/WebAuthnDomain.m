#import "Auth/WebAuthnDomain.h"
#import "Auth/Base32Utils.h"

@implementation WebAuthnRelyingParty
@end

@implementation WebAuthnUser
@end

@implementation WebAuthnPubKeyCredParam
@end

@implementation WebAuthnRegistrationOptions
@end

@implementation WebAuthnCredentialDescriptor
@end

@implementation WebAuthnAssertionOptions
@end

@implementation WebAuthnDomain

+ (NSDictionary *)dictionaryFromRegistrationOptions:(WebAuthnRegistrationOptions *)options {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"challenge"] = [Base32Utils base32StringFromData:options.challenge];
    dict[@"rp"] = @{@"name": options.rp.name, @"id": options.rp.identifier};
    dict[@"user"] = @{
        @"id": [Base32Utils base32StringFromData:options.user.identifier],
        @"name": options.user.name,
        @"displayName": options.user.displayName
    };
    
    NSMutableArray *pubKeyCredParams = [NSMutableArray array];
    for (WebAuthnPubKeyCredParam *param in options.pubKeyCredParams) {
        [pubKeyCredParams addObject:@{@"type": param.type, @"alg": @(param.alg)}];
    }
    dict[@"pubKeyCredParams"] = pubKeyCredParams;
    
    dict[@"timeout"] = @(options.timeout * 1000); // ms
    dict[@"attestation"] = options.attestation ?: @"none";
    
    return [dict copy];
}

+ (NSDictionary *)dictionaryFromAssertionOptions:(WebAuthnAssertionOptions *)options {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"challenge"] = [Base32Utils base32StringFromData:options.challenge];
    dict[@"timeout"] = @(options.timeout * 1000);
    dict[@"rpId"] = options.rpId;
    dict[@"userVerification"] = options.userVerification ?: @"preferred";
    
    if (options.allowCredentials.count > 0) {
        NSMutableArray *creds = [NSMutableArray array];
        for (WebAuthnCredentialDescriptor *desc in options.allowCredentials) {
            NSMutableDictionary *c = [NSMutableDictionary dictionary];
            c[@"type"] = desc.type;
            c[@"id"] = [Base32Utils base32StringFromData:desc.credentialId];
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
