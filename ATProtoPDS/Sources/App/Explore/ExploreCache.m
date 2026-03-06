#import "ExploreCache.h"
#import "Core/PDSDataPaths.h"
#import "App/PDSConfiguration.h"
#import "Debug/PDSLogger.h"

@interface ExploreCache ()
@property (nonatomic, strong) NSCache *memoryCache;
@property (nonatomic, readonly) NSString *cacheDirectory;
@property (nonatomic, readonly) NSString *didCacheDir;
@property (nonatomic, readonly) NSString *plcCacheDir;
@property (nonatomic, readonly) NSString *accountCachePath;
@end

@implementation ExploreCache

static NSTimeInterval const kDidTTL = 3600;
static NSTimeInterval const kPlcTTL = 86400;
static NSTimeInterval const kAccountListTTL = 300;
static NSInteger const kMaxMemoryItems = 200;
static NSString *const kAccountListCacheKey = @"accounts:list";
static NSString *const kAccountListValueKey = @"value";
static NSString *const kAccountListTimestampKey = @"timestamp";

+ (instancetype)sharedCache {
    static ExploreCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ExploreCache alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = kMaxMemoryItems;
    }
    return self;
}

- (NSString *)defaultCacheDirectory {
    NSString *override = [NSProcessInfo processInfo].environment[@"PDS_EXPLORE_CACHE_DIR"];
    if (override.length > 0) {
        return override;
    }

    PDSConfiguration *config = [PDSConfiguration sharedConfiguration];
    if (config) {
        return config.dataPaths.exploreCacheDirectory;
    }

    return [[PDSDataPaths pathsForBaseDirectory:[PDSConfiguration defaultDataDirectory]] exploreCacheDirectory];
}

- (NSString *)cacheDirectory {
    return [self defaultCacheDirectory];
}

- (NSString *)didCacheDir {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:@"did-docs"];
    [self createDirectoryIfNeeded:path];
    return path;
}

- (NSString *)plcCacheDir {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:@"plc-logs"];
    [self createDirectoryIfNeeded:path];
    return path;
}

- (NSString *)accountCachePath {
    [self createDirectoryIfNeeded:self.cacheDirectory];
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:@"accounts.json"];
    return path;
}

- (void)createDirectoryIfNeeded:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        NSError *error = nil;
        if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
            PDS_LOG_ERROR_C(PDSLogComponentExplore, @"ExploreCache: Failed to create directory %@: %@", path, error);
        }
    }
}

#pragma mark - DID Document

- (nullable NSString *)getDidDocument:(NSString *)did {
    if (!did || did.length == 0) return nil;
    
    NSString *key = [self cacheKeyForDid:did];
    NSString *cached = [self.memoryCache objectForKey:key];
    if (cached) return cached;
    
    NSString *path = [self pathForDidDocument:did];
    NSString *diskCached = [NSString stringWithContentsOfFile:path 
                                                     encoding:NSUTF8StringEncoding 
                                                        error:nil];
    if (diskCached) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *modDate = attrs[NSFileModificationDate];
        if (modDate && [modDate timeIntervalSinceNow] > -kDidTTL) {
            [self.memoryCache setObject:diskCached forKey:key];
            return diskCached;
        }
    }
    return nil;
}

- (void)setDidDocument:(NSString *)did value:(NSString *)document {
    if (!did || !document) return;
    
    NSString *key = [self cacheKeyForDid:did];
    [self.memoryCache setObject:document forKey:key];
    
    NSString *path = [self pathForDidDocument:did];
    [document writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)pathForDidDocument:(NSString *)did {
    NSString *sanitized = [self sanitizeFilename:did];
    return [self.didCacheDir stringByAppendingPathComponent:[sanitized stringByAppendingPathExtension:@"json"]];
}

#pragma mark - PLC Log

- (nullable NSString *)getPlcLog:(NSString *)did {
    if (!did || did.length == 0) return nil;
    
    NSString *key = [NSString stringWithFormat:@"plc:%@", did];
    NSString *cached = [self.memoryCache objectForKey:key];
    if (cached) return cached;
    
    NSString *path = [self pathForPlcLog:did];
    NSString *diskCached = [NSString stringWithContentsOfFile:path 
                                                     encoding:NSUTF8StringEncoding 
                                                        error:nil];
    if (diskCached) {
        NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
        NSDate *modDate = attrs[NSFileModificationDate];
        if (modDate && [modDate timeIntervalSinceNow] > -kPlcTTL) {
            [self.memoryCache setObject:diskCached forKey:key];
            return diskCached;
        }
    }
    return nil;
}

- (void)setPlcLog:(NSString *)did value:(NSString *)log {
    if (!did || !log) return;
    
    NSString *key = [NSString stringWithFormat:@"plc:%@", did];
    [self.memoryCache setObject:log forKey:key];
    
    NSString *path = [self pathForPlcLog:did];
    [log writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)pathForPlcLog:(NSString *)did {
    NSString *sanitized = [self sanitizeFilename:did];
    return [self.plcCacheDir stringByAppendingPathComponent:[sanitized stringByAppendingPathExtension:@"json"]];
}

#pragma mark - Account List

- (nullable NSString *)getAccountList {
    id cachedEntry = [self.memoryCache objectForKey:kAccountListCacheKey];
    if (cachedEntry) {
        // Backward-compatibility: ignore legacy string entries that had no TTL.
        if ([cachedEntry isKindOfClass:[NSString class]]) {
            [self.memoryCache removeObjectForKey:kAccountListCacheKey];
        } else if ([cachedEntry isKindOfClass:[NSDictionary class]]) {
            NSString *value = cachedEntry[kAccountListValueKey];
            NSDate *timestamp = cachedEntry[kAccountListTimestampKey];
            if ([value isKindOfClass:[NSString class]] &&
                [timestamp isKindOfClass:[NSDate class]] &&
                [timestamp timeIntervalSinceNow] > -kAccountListTTL) {
                return value;
            }
            [self.memoryCache removeObjectForKey:kAccountListCacheKey];
        } else {
            [self.memoryCache removeObjectForKey:kAccountListCacheKey];
        }
    }
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.accountCachePath]) {
        NSString *diskCached = [NSString stringWithContentsOfFile:self.accountCachePath 
                                                         encoding:NSUTF8StringEncoding 
                                                            error:nil];
        if (diskCached) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:self.accountCachePath error:nil];
            NSDate *modDate = attrs[NSFileModificationDate];
            if (modDate && [modDate timeIntervalSinceNow] > -kAccountListTTL) {
                [self.memoryCache setObject:@{
                    kAccountListValueKey: diskCached,
                    kAccountListTimestampKey: modDate
                } forKey:kAccountListCacheKey];
                return diskCached;
            }
        }
    }
    return nil;
}

- (void)setAccountList:(NSString *)accountList {
    if (!accountList) return;
    
    [self.memoryCache setObject:@{
        kAccountListValueKey: accountList,
        kAccountListTimestampKey: [NSDate date]
    } forKey:kAccountListCacheKey];
    [accountList writeToFile:self.accountCachePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark - Cleanup

- (void)clearExpiredEntries {
    NSFileManager *fm = [NSFileManager defaultManager];

    
    NSArray *dirs = @[self.didCacheDir, self.plcCacheDir];
    for (NSString *dir in dirs) {
        NSArray *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            NSString *path = [dir stringByAppendingPathComponent:file];
            NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
            NSDate *modDate = attrs[NSFileModificationDate];
            
            BOOL expired = NO;
            if ([dir isEqualToString:self.didCacheDir]) {
                expired = modDate && [modDate timeIntervalSinceNow] < -kDidTTL;
            } else if ([dir isEqualToString:self.plcCacheDir]) {
                expired = modDate && [modDate timeIntervalSinceNow] < -kPlcTTL;
            }
            
            if (expired) {
                [fm removeItemAtPath:path error:nil];
            }
        }
    }
    
    [self.memoryCache removeAllObjects];
}

- (void)clearAll {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:self.cacheDirectory error:nil];
    [self createDirectoryIfNeeded:self.didCacheDir];
    [self createDirectoryIfNeeded:self.plcCacheDir];
    [self.memoryCache removeAllObjects];
}

#pragma mark - Helpers

- (NSString *)cacheKeyForDid:(NSString *)did {
    return [NSString stringWithFormat:@"did:%@", did];
}

- (NSString *)sanitizeFilename:(NSString *)filename {
    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@":/\\?%*|\"<>"];
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < filename.length; i++) {
        unichar c = [filename characterAtIndex:i];
        if ([invalidChars characterIsMember:c]) {
            [result appendFormat:@"_%X", (int)c];
        } else {
            [result appendFormat:@"%C", c];
        }
    }
    return result;
}

@end
