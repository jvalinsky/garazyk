#import "ATProtoValidator.h"

@implementation ATProtoValidator

+ (BOOL)validateDID:(NSString *)did error:(NSError **)error {
    if (!did) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"DID cannot be nil"}];
        return NO;
    }

    // Supported methods: did:plc and did:web
    if ([did hasPrefix:@"did:plc:"]) {
        // did:plc:<24 chars base32>
        // Regex: ^did:plc:[a-z2-7]{24}$
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^did:plc:[a-z2-7]{24}$" options:0 error:nil];
        if ([regex numberOfMatchesInString:did options:0 range:NSMakeRange(0, did.length)] == 0) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:plc format. Must be lowercase base32 (24 chars)."}];
            return NO;
        }
        return YES;
    } else if ([did hasPrefix:@"did:web:"]) {
        // did:web:<hostname>
        // Hostname validation is complex, simplified check for now
        NSString *identifier = [did substringFromIndex:8];
        if (identifier.length == 0 || [identifier containsString:@"/"] || [identifier containsString:@":"]) {
             if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:web format."}];
            return NO;
        }
        return YES;
    }

    if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:4 userInfo:@{NSLocalizedDescriptionKey: @"Unsupported DID method"}];
    return NO;
}

+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error {
    if (!handle) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Handle cannot be nil"}];
        return NO;
    }

    // Regex: ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$
    // Simplified: lowercase, valid chars, TLD check
    
    if (handle.length > 253) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Handle too long"}];
        return NO;
    }

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$" options:0 error:nil];
    
    if ([regex numberOfMatchesInString:handle options:0 range:NSMakeRange(0, handle.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:6 userInfo:@{NSLocalizedDescriptionKey: @"Invalid handle syntax"}];
        return NO;
    }

    // Check reserved TLDs
    NSArray *reservedTLDs = @[@"alt", @"arpa", @"example", @"internal", @"invalid", @"local", @"localhost", @"onion"];
    NSString *tld = [[handle componentsSeparatedByString:@"."] lastObject];
    if ([reservedTLDs containsObject:[tld lowercaseString]]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:7 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Reserved TLD: .%@", tld]}];
        return NO;
    }

    return YES;
}

+ (BOOL)validateCID:(NSString *)cid error:(NSError **)error {
    if (!cid) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"CID cannot be nil"}];
        return NO;
    }

    // Must be CIDv1 base32 lowercase
    // Starts with 'b'
    if (![cid hasPrefix:@"b"]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:8 userInfo:@{NSLocalizedDescriptionKey: @"CID must be base32 lowercase (start with 'b')"}];
        return NO;
    }

    // Check for uppercase characters (strict lowercase base32)
    NSRegularExpression *uppercaseRegex = [NSRegularExpression regularExpressionWithPattern:@"[A-Z]" options:0 error:nil];
    if ([uppercaseRegex numberOfMatchesInString:cid options:0 range:NSMakeRange(0, cid.length)] > 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:9 userInfo:@{NSLocalizedDescriptionKey: @"CID must be lowercase"}];
        return NO;
    }

    // Check valid base32 chars
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[a-z2-7]+$" options:0 error:nil];
    // Skip the 'b' prefix
    NSString *content = [cid substringFromIndex:1];
    if ([regex numberOfMatchesInString:content options:0 range:NSMakeRange(0, content.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:10 userInfo:@{NSLocalizedDescriptionKey: @"Invalid base32 characters in CID"}];
        return NO;
    }

    return YES;
}

+ (BOOL)validateTID:(NSString *)tid error:(NSError **)error {
    if (!tid) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"TID cannot be nil"}];
        return NO;
    }

    if (tid.length != 13) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:11 userInfo:@{NSLocalizedDescriptionKey: @"TID must be 13 characters"}];
        return NO;
    }

    // Base32 sortable: 234567abcdefghijklmnopqrstuvwxyz (clockid is part of it)
    // Actually standard TID uses base32-sortable: 234567abcdefghijklmnopqrstuvwxyz
    // Spec says: "13-char base32-sortable"
    // Regex: ^[2-7a-z]{13}$
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[2-7a-z]{13}$" options:0 error:nil];
    if ([regex numberOfMatchesInString:tid options:0 range:NSMakeRange(0, tid.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Invalid TID format"}];
        return NO;
    }

    return YES;
}

+ (BOOL)validateNSID:(NSString *)nsid error:(NSError **)error {
    if (!nsid) return NO;
    // Simple check: reverse domain name style
    if (![nsid containsString:@"."]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:13 userInfo:@{NSLocalizedDescriptionKey: @"Invalid NSID"}];
        return NO;
    }
    return YES;
}

@end
