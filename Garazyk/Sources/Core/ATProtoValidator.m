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
        // did:web:<hostname> or did:web:<hostname>:<path>
        NSString *identifier = [did substringFromIndex:8];
        if (identifier.length == 0 || [identifier containsString:@"/"]) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:web format."}];
            return NO;
        }

        NSArray<NSString *> *components = [identifier componentsSeparatedByString:@":"];
        for (NSString *component in components) {
            if (component.length == 0) {
                if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Invalid did:web format."}];
                return NO;
            }
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
    
    // Check minimum length (CIDv1 with SHA-256 is typically 59 chars)
    // We'll enforce a safe minimum like 10 to avoid "b", "ba", etc.
    if (cid.length < 10) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:14 userInfo:@{NSLocalizedDescriptionKey: @"CID too short"}];
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

    // TIDs are base32-sortable using alphabet: 234567abcdefghijklmnopqrstuvwxyz
    // Plus: the "high bit can't be high" (timestamp must fit in 53 bits), which restricts the first char to index < 8.
    static NSString * const alphabet = @"234567abcdefghijklmnopqrstuvwxyz";
    static NSString * const allowedFirstChars = @"234567ab";
    unichar first = [tid characterAtIndex:0];
    if ([allowedFirstChars rangeOfString:[NSString stringWithCharacters:&first length:1]].location == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Invalid TID format (high bit cannot be set)"}];
        return NO;
    }
    for (NSUInteger i = 0; i < tid.length; i++) {
        unichar c = [tid characterAtIndex:i];
        if ([alphabet rangeOfString:[NSString stringWithCharacters:&c length:1]].location == NSNotFound) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:12 userInfo:@{NSLocalizedDescriptionKey: @"Invalid TID format (must be base32-sortable)"}];
            return NO;
        }
    }

    return YES;
}

+ (BOOL)validateNSID:(NSString *)nsid error:(NSError **)error {
    if (!nsid) return NO;
    
    // NSID (Namespaced Identifier) - reversed domain name
    // Max length 253
    if (nsid.length > 253) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:15 userInfo:@{NSLocalizedDescriptionKey: @"NSID too long"}];
        return NO;
    }
    
    // Check for empty segs, uppercase, special chars
    // Regex: ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$
    // But allowing >1 segments
    
    // Must contain at least one dot
    if (![nsid containsString:@"."]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:13 userInfo:@{NSLocalizedDescriptionKey: @"NSID must contain segments"}];
        return NO;
    }
    
    // NSID can contain uppercase (e.g. XRPC methods like getRecord)
    
    NSArray *components = [nsid componentsSeparatedByString:@"."];
    for (NSString *comp in components) {
        if (comp.length == 0) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:17 userInfo:@{NSLocalizedDescriptionKey: @"NSID cannot have empty segments"}];
            return NO;
        }
        if (comp.length > 63) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:18 userInfo:@{NSLocalizedDescriptionKey: @"NSID segment too long"}];
            return NO;
        }
        
        // Check valid chars: a-z, A-Z, 0-9, -
        // Cannot start or end with -
        if ([comp hasPrefix:@"-"] || [comp hasSuffix:@"-"]) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:19 userInfo:@{NSLocalizedDescriptionKey: @"NSID segment cannot start or end with hyphen"}];
            return NO;
        }
        
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9-]+$" options:0 error:nil];
        if ([regex numberOfMatchesInString:comp options:0 range:NSMakeRange(0, comp.length)] == 0) {
            if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:20 userInfo:@{NSLocalizedDescriptionKey: @"NSID contains invalid characters"}];
            return NO;
        }
    }
    
    // Check for starts/ends with dot (components check handles empty start/end but let's be safe)
    if ([nsid hasPrefix:@"."] || [nsid hasSuffix:@"."]) {
         if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:21 userInfo:@{NSLocalizedDescriptionKey: @"NSID cannot start or end with dot"}];
         return NO;
    }

    return YES;
}

+ (BOOL)validateDatetime:(NSString *)datetime error:(NSError **)error {
    if (!datetime) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Datetime cannot be nil"}];
        return NO;
    }

    // Regex for basic ISO 8601 structure compliant with ATProto lexicon
    // YYYY-MM-DDTHH:mm:ss[.sss](Z|±HH:MM)
    NSString *pattern = @"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(\\.[0-9]{1,20})?(Z|([+-][0-9]{2}:[0-9]{2}))$";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if ([regex numberOfMatchesInString:datetime options:0 range:NSMakeRange(0, datetime.length)] == 0) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:22 userInfo:@{NSLocalizedDescriptionKey: @"Invalid datetime format"}];
        return NO;
    }

    // Range checks
    int y, m, d, hr, min, sec;
    sscanf([datetime UTF8String], "%d-%d-%dT%d:%d:%d", &y, &m, &d, &hr, &min, &sec);

    if (y < 0 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31 || hr < 0 || hr > 23 || min < 0 || min > 59 || sec < 0 || sec > 60) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:23 userInfo:@{NSLocalizedDescriptionKey: @"Datetime components out of range"}];
        return NO;
    }

    // Special check for -00:00 (prohibited by lexicon)
    if ([datetime containsString:@"-00:00"]) {
        if (error) *error = [NSError errorWithDomain:@"ATProtoValidator" code:24 userInfo:@{NSLocalizedDescriptionKey: @"Negative zero timezone offset is prohibited"}];
        return NO;
    }

    return YES;
}

@end
