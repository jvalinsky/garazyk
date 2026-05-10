#import "Security/PDSInputValidator.h"

NSErrorDomain const PDSValidationErrorDomain = @"com.atproto.pds.validation";

static const char kTIDBase32Alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";

@interface PDSInputValidator ()
@property (nonatomic, strong) NSRegularExpression *nsidRegex;
@property (nonatomic, strong) NSRegularExpression *didRegex;
@property (nonatomic, strong) NSRegularExpression *handleRegex;
@property (nonatomic, strong) NSRegularExpression *atUriRegex;
@property (nonatomic, strong) NSCharacterSet *allowedNSIDChars;
@end

@implementation PDSInputValidator

+ (instancetype)sharedValidator {
    static PDSInputValidator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[PDSInputValidator alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSError *error = nil;
        _nsidRegex = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+\\.[a-zA-Z0-9_-]+$" options:0 error:&error];
        _didRegex = [NSRegularExpression regularExpressionWithPattern:@"^did:(plc|web|key):[a-zA-Z0-9_-]+$" options:0 error:&error];
        _handleRegex = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$" options:0 error:&error];
        _atUriRegex = [NSRegularExpression regularExpressionWithPattern:@"^at://[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+(/[a-zA-Z0-9_-]+)?)?$" options:0 error:&error];

        NSMutableCharacterSet *allowed = [NSMutableCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"];
        [allowed formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        _allowedNSIDChars = [allowed invertedSet];
    }
    return self;
}

- (BOOL)isValidNSID:(NSString *)nsid {
    if (!nsid || nsid.length == 0) return NO;
    if (nsid.length > 512) return NO;
    if ([self containsNullByte:nsid]) return NO;

    NSRange range = NSMakeRange(0, nsid.length);
    return [self.nsidRegex numberOfMatchesInString:nsid options:0 range:range] > 0;
}

- (BOOL)isValidDID:(NSString *)did {
    if (!did || did.length == 0) return NO;
    if (did.length > 1024) return NO;
    if ([self containsNullByte:did]) return NO;

    NSRange range = NSMakeRange(0, did.length);
    return [self.didRegex numberOfMatchesInString:did options:0 range:range] > 0;
}

- (BOOL)isValidHandle:(NSString *)handle {
    if (!handle || handle.length == 0) return NO;
    if (handle.length > 253) return NO;
    if ([self containsNullByte:handle]) return NO;
    if ([handle hasPrefix:@"-"] || [handle hasSuffix:@"-"]) return NO;
    if ([handle containsString:@".."]) return NO;

    NSRange range = NSMakeRange(0, handle.length);
    return [self.handleRegex numberOfMatchesInString:handle options:0 range:range] > 0;
}

- (BOOL)isValidTID:(NSString *)tid {
    if (!tid || tid.length == 0) return NO;
    if (tid.length != 13) return NO;
    if ([self containsNullByte:tid]) return NO;

    for (NSUInteger i = 0; i < tid.length; i++) {
        char c = [tid characterAtIndex:i];
        BOOL valid = NO;
        for (int j = 0; j < 32; j++) {
            if (c == kTIDBase32Alphabet[j]) {
                valid = YES;
                break;
            }
        }
        if (!valid) return NO;
    }

    return YES;
}

- (BOOL)isValidCID:(NSString *)cid {
    if (!cid || cid.length == 0) return NO;
    if ([self containsNullByte:cid]) return NO;

    if (![cid hasPrefix:@"b"]) return NO;

    NSString *encoded = [cid substringFromIndex:1];
    if (encoded.length < 10) return NO;

    for (NSUInteger i = 0; i < encoded.length; i++) {
        char c = [encoded characterAtIndex:i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '2' && c <= '7'))) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)isValidRecordKey:(NSString *)rkey {
    if (!rkey || rkey.length == 0) return NO;
    if (rkey.length > 512) return NO;
    if ([self containsNullByte:rkey]) return NO;

    if ([rkey containsString:@".."]) return NO;
    if ([self isValidTID:rkey]) return YES;

    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./"];
    NSCharacterSet *inputChars = [NSCharacterSet characterSetWithCharactersInString:rkey];
    return [validChars isSupersetOfSet:inputChars];
}

- (BOOL)isValidCollectionName:(NSString *)collection {
    return [self isValidNSID:collection];
}

- (BOOL)isValidRepoURI:(NSString *)uri {
    return [self isValidATURI:uri];
}

- (BOOL)isValidATURI:(NSString *)uri {
    if (!uri || uri.length == 0) return NO;
    if (uri.length > 2048) return NO;
    if ([self containsNullByte:uri]) return NO;

    NSRange range = NSMakeRange(0, uri.length);
    return [self.atUriRegex numberOfMatchesInString:uri options:0 range:range] > 0;
}

- (BOOL)containsNullByte:(NSString *)input {
    if (!input) return NO;
    return [input containsString:@"\0"];
}

- (NSInteger)validateLimitParameter:(NSInteger)limit maxLimit:(NSInteger)maxLimit {
    if (limit <= 0) {
        return 20;
    }
    if (limit > maxLimit) {
        return maxLimit;
    }
    return limit;
}

- (nullable NSString *)validateCursorParameter:(NSString *)cursor maxLength:(NSInteger)maxLength {
    if (!cursor || cursor.length == 0) {
        return nil;
    }

    if (cursor.length > maxLength) {
        return nil;
    }

    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/="];
    NSCharacterSet *cursorChars = [NSCharacterSet characterSetWithCharactersInString:cursor];
    if (![validChars isSupersetOfSet:cursorChars]) {
        return nil;
    }

    return cursor;
}

@end
