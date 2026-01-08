#import "Security/PDSInputValidator.h"

NSErrorDomain const PDSValidationErrorDomain = @"com.atproto.pds.validation";

static NSString *const kSQLInjectionPatterns[] = {
    @"' OR '1'='1",
    @"UNION SELECT",
    @"DROP TABLE",
    @"--",
    @"; DROP",
    @"EXEC(",
    @"EXEC (",
    @"xp_cmdshell",
    @"load_extension",
    @"ATTACH DATABASE",
    @"PRAGMA",
    @"VACUUM",
    NULL
};

static NSString *const kPathTraversalPatterns[] = {
    @"../",
    @"..\\",
    @"%2e%2e",
    @"%c0%ae%c0%ae",
    @"....//",
    @"..%2F",
    @"\\..\\",
    NULL
};

static NSString *const kXSSPatterns[] = {
    @"<script>",
    @"javascript:",
    @"<iframe",
    @"<object",
    @"<embed",
    @"onload=",
    @"onerror=",
    @"onclick=",
    @"onmouseover=",
    @"alert(",
    @"eval(",
    NULL
};

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

- (BOOL)isValidRecordKey:(NSString *)rkey {
    if (!rkey || rkey.length == 0) return NO;
    if (rkey.length > 512) return NO;
    if ([self containsNullByte:rkey]) return NO;
    if ([self containsPathTraversalPattern:rkey]) return NO;

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
    if ([self containsPathTraversalPattern:uri]) return NO;

    NSRange range = NSMakeRange(0, uri.length);
    return [self.atUriRegex numberOfMatchesInString:uri options:0 range:range] > 0;
}

- (nullable NSString *)sanitizeSQLInput:(NSString *)input error:(NSError **)error {
    if (!input) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorEmptyString userInfo:@{NSLocalizedDescriptionKey: @"Input cannot be nil"}];
        }
        return nil;
    }

    if ([self containsSQLInjectionPattern:input]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorSQLInjectionPattern userInfo:@{NSLocalizedDescriptionKey: @"Input contains SQL injection patterns"}];
        }
        return nil;
    }

    NSMutableString *sanitized = [NSMutableString stringWithString:input];
    [sanitized replaceOccurrencesOfString:@"'" withString:@"''" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@"\0" withString:@"" options:0 range:NSMakeRange(0, sanitized.length)];

    return [sanitized copy];
}

- (nullable NSString *)sanitizePathInput:(NSString *)input error:(NSError **)error {
    if (!input) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorEmptyString userInfo:@{NSLocalizedDescriptionKey: @"Input cannot be nil"}];
        }
        return nil;
    }

    if ([self containsNullByte:input]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorNullByteInjection userInfo:@{NSLocalizedDescriptionKey: @"Input contains null byte"}];
        }
        return nil;
    }

    if ([self containsPathTraversalPattern:input]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorPathTraversal userInfo:@{NSLocalizedDescriptionKey: @"Input contains path traversal pattern"}];
        }
        return nil;
    }

    NSMutableString *sanitized = [NSMutableString stringWithString:input];
    [sanitized replaceOccurrencesOfString:@"../" withString:@"" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@"..\\" withString:@"" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@"\0" withString:@"" options:0 range:NSMakeRange(0, sanitized.length)];

    return [sanitized copy];
}

- (nullable NSString *)sanitizeJSONField:(NSString *)input error:(NSError **)error {
    if (!input) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorEmptyString userInfo:@{NSLocalizedDescriptionKey: @"Input cannot be nil"}];
        }
        return nil;
    }

    if ([self containsXSSPattern:input]) {
        if (error) {
            *error = [NSError errorWithDomain:PDSValidationErrorDomain code:PDSValidationErrorXSSPattern userInfo:@{NSLocalizedDescriptionKey: @"Input contains XSS patterns"}];
        }
        return nil;
    }

    NSMutableString *sanitized = [NSMutableString stringWithString:input];
    [sanitized replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@"'" withString:@"&#x27;" options:0 range:NSMakeRange(0, sanitized.length)];
    [sanitized replaceOccurrencesOfString:@"\0" withString:@"" options:0 range:NSMakeRange(0, sanitized.length)];

    return [sanitized copy];
}

- (BOOL)containsSQLInjectionPattern:(NSString *)input {
    if (!input) return NO;

    NSString *upperInput = [input uppercaseString];
    for (int i = 0; kSQLInjectionPatterns[i] != NULL; i++) {
        NSString *pattern = [kSQLInjectionPatterns[i] uppercaseString];
        if ([upperInput containsString:pattern]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)containsPathTraversalPattern:(NSString *)input {
    if (!input) return NO;

    NSString *normalizedInput = [input lowercaseString];
    for (int i = 0; kPathTraversalPatterns[i] != NULL; i++) {
        if ([normalizedInput containsString:[kPathTraversalPatterns[i] lowercaseString]]) {
            return YES;
        }
    }

    if ([input containsString:@"/../"] || [input hasSuffix:@"/.."] ||
        [input containsString:@"\\..\\"] || [input hasSuffix:@"\\.."]) {
        return YES;
    }

    return NO;
}

- (BOOL)containsNullByte:(NSString *)input {
    if (!input) return NO;
    return [input containsString:@"\0"];
}

- (BOOL)containsXSSPattern:(NSString *)input {
    if (!input) return NO;

    NSString *upperInput = [input uppercaseString];
    for (int i = 0; kXSSPatterns[i] != NULL; i++) {
        NSString *pattern = [kXSSPatterns[i] uppercaseString];
        if ([upperInput containsString:pattern]) {
            return YES;
        }
    }
    return NO;
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
