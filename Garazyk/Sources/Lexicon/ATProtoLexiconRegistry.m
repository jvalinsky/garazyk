// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "ATProtoLexiconRegistry.h"
#import "ATProtoLexiconSchema.h"
#import "ATProtoLexiconError.h"
#import "Compat/PDSTypes.h"
#import "Debug/GZLogger.h"

@interface ATProtoLexiconRegistry ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoLexiconSchema *> *schemas;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t registryQueue;

@end

@implementation ATProtoLexiconRegistry

+ (instancetype)sharedRegistry {
    static ATProtoLexiconRegistry *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _schemas = [NSMutableDictionary dictionary];
        _registryQueue = dispatch_queue_create("com.atproto.pds.lexicon.registry",
                                               DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (BOOL)loadLexiconsFromDirectory:(NSString *)path error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileNoSuchFileError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Directory does not exist"}];
        }
        return NO;
    }

    GZ_LOG_DEBUG(@"[LexiconRegistry] Loading lexicons from: %@", path);

    NSError *enumError = nil;
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:path error:&enumError];

    if (enumError) {
        if (error) *error = enumError;
        return NO;
    }

    NSUInteger loadedCount = 0;
    NSUInteger errorCount = 0;

    for (NSString *item in contents) {
        NSString *fullPath = [path stringByAppendingPathComponent:item];

        BOOL itemIsDirectory = NO;
        [fileManager fileExistsAtPath:fullPath isDirectory:&itemIsDirectory];

        if (itemIsDirectory) {
            // Recursively load subdirectories
            [self loadLexiconsFromDirectory:fullPath error:nil];
        } else if ([item.pathExtension isEqualToString:@"json"]) {
            // Load JSON file
            NSError *loadError = nil;
            if ([self loadLexiconFromFile:fullPath error:&loadError]) {
                loadedCount++;
            } else {
                errorCount++;
                GZ_LOG_WARN(@"[LexiconRegistry] Failed to load %@: %@",
                              item, loadError.localizedDescription);
            }
        }
    }

    GZ_LOG_DEBUG(@"[LexiconRegistry] Loaded %lu lexicons (%lu errors) from %@",
                (unsigned long)loadedCount, (unsigned long)errorCount, path);

    return errorCount == 0;
}

- (BOOL)loadLexiconFromFile:(NSString *)filePath error:(NSError **)error {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];

    if (readError || !data) {
        if (error) *error = readError;
        return NO;
    }

    NSError *parseError = nil;
    ATProtoLexiconSchema *schema = [ATProtoLexiconSchema schemaFromJSONData:data error:&parseError];

    if (parseError || !schema) {
        if (error) {
            *error = parseError ?: [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                               message:@"Failed to parse lexicon"
                                                               context:filePath];
        }
        return NO;
    }

    [self registerSchema:schema];
    return YES;
}

- (void)registerSchema:(ATProtoLexiconSchema *)schema {
    if (!schema || !schema.nsid) {
        GZ_LOG_WARN(@"[LexiconRegistry] Attempted to register nil schema or schema with nil NSID");
        return;
    }
    
    dispatch_barrier_async(self.registryQueue, ^{
        self.schemas[schema.nsid] = schema;
    });
    
    GZ_LOG_DEBUG(@"[LexiconRegistry] Registered schema: %@", schema.nsid);
}

- (nullable ATProtoLexiconSchema *)schemaForNSID:(NSString *)nsid {
    if (!nsid) return nil;
    
    __block ATProtoLexiconSchema *schema = nil;
    dispatch_sync(self.registryQueue, ^{
        schema = self.schemas[nsid];
    });
    
    if (!schema) {
        GZ_LOG_DEBUG(@"[LexiconRegistry] Schema NOT FOUND for NSID: %@", nsid);
    } else {
        GZ_LOG_DEBUG(@"[LexiconRegistry] Schema found for NSID: %@", nsid);
    }
    
    return schema;
}

- (BOOL)hasSchemaForNSID:(NSString *)nsid {
    return [self schemaForNSID:nsid] != nil;
}

- (void)clearCache {
    dispatch_barrier_async(self.registryQueue, ^{
        [self.schemas removeAllObjects];
    });
    GZ_LOG_DEBUG(@"[LexiconRegistry] Cache cleared");
}

- (NSArray<NSString *> *)loadedNSIDs {
    __block NSArray *nsids = nil;
    dispatch_sync(self.registryQueue, ^{
        nsids = [self.schemas allKeys];
    });
    return nsids ?: @[];
}

- (NSArray<NSString *> *)searchPathsForDirectory:(NSString *)dataDirectory {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableOrderedSet<NSString *> *paths = [NSMutableOrderedSet orderedSet];
    NSString *overridePath = [NSProcessInfo processInfo].environment[@"PDS_LEXICON_PATH"];
    if (overridePath.length > 0) {
        [paths addObject:overridePath];
    }

    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"lexicons" ofType:nil];
    if (bundlePath.length > 0) {
        [paths addObject:bundlePath];
    }

    BOOL isDir = NO;
    if ([fm fileExistsAtPath:@"/usr/share/garazyk/lexicons" isDirectory:&isDir] && isDir) {
        [paths addObject:@"/usr/share/garazyk/lexicons"];
    }

    NSString *cwd = fm.currentDirectoryPath ?: @"";
    NSArray<NSString *> *candidates = @[
        @"Garazyk/Resources/lexicons",
        @"Resources/lexicons",
        @"lexicons",
        @"../Garazyk/Resources/lexicons",
        @"../../Garazyk/Resources/lexicons",
        @"../../../Garazyk/Resources/lexicons"
    ];
    for (NSString *candidate in candidates) {
        NSString *path = [cwd stringByAppendingPathComponent:candidate];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
            [paths addObject:path];
        }
    }

    if (dataDirectory.length > 0) {
        NSString *customPath = [dataDirectory stringByAppendingPathComponent:@"lexicons"];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:customPath isDirectory:&isDir] && isDir) {
            [paths addObject:customPath];
        }
    }

    return paths.array;
}

@end
