//
//  fuzz_lexicon.mm
//  Lexicon validation fuzzing harness for ATProto PDS
//
//  Tests:
//  1. Lexicon schema loading (once during init)
//  2. Record validation against loaded schemas
//  3. Edge cases in validation logic (types, constraints, enums)
//

#import <Foundation/Foundation.h>
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconSchema.h"

static ATProtoLexiconRegistry *registry = nil;
static ATProtoLexiconValidator *validator = nil;
static NSArray<NSString *> *loadedNSIDs = nil;

extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv) {
    @autoreleasepool {
        registry = [ATProtoLexiconRegistry sharedRegistry];
        
        // Try to load lexicons from likely locations
        NSArray *paths = [registry searchPathsForDirectory:nil];
        BOOL loaded = NO;
        
        for (NSString *path in paths) {
            NSError *error = nil;
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                if ([registry loadLexiconsFromDirectory:path error:&error]) {
                    printf("Loaded lexicons from: %s\n", [path UTF8String]);
                    loaded = YES;
                    break;
                }
            }
        }
        
        if (!loaded) {
            printf("WARNING: Failed to load lexicons. Validation may be limited.\n");
        }
        
        validator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
        loadedNSIDs = [[registry loadedNSIDs] sortedArrayUsingSelector:@selector(compare:)];
        
        printf("Initialized validator with %lu schemas.\n", (unsigned long)loadedNSIDs.count);
    }
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size < 10 || loadedNSIDs.count == 0) {
        return 0;
    }

    @autoreleasepool {
        // Use first byte to select collection
        uint8_t collectionIdx = data[0] % loadedNSIDs.count;
        NSString *collection = loadedNSIDs[collectionIdx];
        
        // Use remaining data as JSON input
        NSData *jsonData = [NSData dataWithBytes:data + 1 length:size - 1];
        
        // Try to parse as JSON first (validator expects Dictionary)
        NSError *jsonError = nil;
        id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];
        
        if (jsonObject && [jsonObject isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *record = [jsonObject mutableCopy];
            
            // Ensure $type matches collection if not present
            if (!record[@"$type"]) {
                record[@"$type"] = collection;
            }
            
            // Validate
            NSError *error = nil;
            [validator validateRecord:record
                           collection:collection
                                 mode:ATProtoValidationModeOptimistic
                                error:&error];
        }
    }
    return 0;
}
