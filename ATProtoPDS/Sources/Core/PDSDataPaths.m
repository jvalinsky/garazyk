#import "PDSDataPaths.h"

@implementation PDSDataPaths

+ (instancetype)pathsForBaseDirectory:(NSString *)baseDirectory {
    return [[self alloc] initWithBaseDirectory:baseDirectory];
}

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory {
    self = [super init];
    if (self) {
        _baseDirectory = [baseDirectory copy];
        _serviceDirectory = [baseDirectory stringByAppendingPathComponent:@"service"];
        _didCacheDirectory = [baseDirectory stringByAppendingPathComponent:@"did_cache"];
        _sequencerDirectory = [baseDirectory stringByAppendingPathComponent:@"sequencer"];
        _blobsDirectory = [baseDirectory stringByAppendingPathComponent:@"blobs"];
        _lexiconsDirectory = [baseDirectory stringByAppendingPathComponent:@"lexicons"];
        _keysDirectory = [baseDirectory stringByAppendingPathComponent:@"keys"];
        _exploreCacheDirectory = [[baseDirectory stringByAppendingPathComponent:@"cache"]
                                  stringByAppendingPathComponent:@"explore"];
    }
    return self;
}

- (BOOL)createDirectoriesWithError:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *dirs = @[
        self.baseDirectory,
        self.serviceDirectory,
        self.didCacheDirectory,
        self.sequencerDirectory,
        self.blobsDirectory,
        self.lexiconsDirectory,
        self.keysDirectory,
        self.exploreCacheDirectory,
    ];
    for (NSString *dir in dirs) {
        if (![fm fileExistsAtPath:dir]) {
            if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

- (NSString *)actorStorePathForDid:(NSString *)did {
    // Parse did:<method>:<method-specific-id>
    // Shard into {base}/{method}/{2-char-prefix}/{did}
    NSRange firstColon = [did rangeOfString:@":"];
    if (firstColon.location != NSNotFound) {
        NSRange rest = NSMakeRange(firstColon.location + 1, did.length - firstColon.location - 1);
        NSRange secondColon = [did rangeOfString:@":" options:0 range:rest];
        if (secondColon.location != NSNotFound) {
            NSString *method = [did substringWithRange:NSMakeRange(firstColon.location + 1,
                                                                   secondColon.location - firstColon.location - 1)];
            NSString *identifier = [did substringFromIndex:secondColon.location + 1];
            NSString *prefix = [identifier substringToIndex:MIN(2, identifier.length)];

            NSString *methodDir = [self.baseDirectory stringByAppendingPathComponent:method];
            NSString *prefixDir = [methodDir stringByAppendingPathComponent:prefix];
            return [prefixDir stringByAppendingPathComponent:did];
        }
    }

    // Fallback for non-standard DIDs
    NSString *prefix = [did substringToIndex:MIN(2, did.length)];
    return [[self.baseDirectory stringByAppendingPathComponent:prefix]
            stringByAppendingPathComponent:did];
}

- (NSString *)keyPathForDid:(NSString *)did {
    return [self.keysDirectory stringByAppendingPathComponent:did];
}

@end
