// FuzzATProtoLexiconValidator.m - Lexicon record validation fuzzer harness
// Target: Lexicon schema validation

#import <Foundation/Foundation.h>
#import "Lexicon/ATProtoLexiconValidator.h"
#import "Lexicon/ATProtoLexiconRegistry.h"

static ATProtoLexiconValidator *gValidator = nil;

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];

            // Try to load lexicons from current working directory (repo root when run from there)
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            NSString *lexiconPath = [cwd stringByAppendingPathComponent:@"Lexicons"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:lexiconPath]) {
                [registry loadLexiconsFromDirectory:lexiconPath error:nil];
            }

            gValidator = [[ATProtoLexiconValidator alloc] initWithRegistry:registry];
        });

        if (!gValidator) {
            return 0;
        }

        NSError *error = nil;
        NSDictionary *record = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:data length:size]
                                                               options:0
                                                                 error:&error];
        if ([record isKindOfClass:[NSDictionary class]]) {
            // Try Required mode first to exercise strict validation
            [gValidator validateRecord:record
                            collection:@"app.bsky.actor.profile"
                                  mode:ATProtoValidationModeRequired
                                 error:&error];

            // Also try other common collections
            [gValidator validateRecord:record
                            collection:@"app.bsky.feed.post"
                                  mode:ATProtoValidationModeOptimistic
                                 error:&error];
        }
    }
    return 0;
}
