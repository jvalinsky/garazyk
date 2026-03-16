// fuzz_lexicon.mm — libFuzzer entry point for ATProto Lexicon validation
//
// Exercises ATProtoLexiconDef JSON parsing and constraint validation
// with arbitrary input.

#import <Foundation/Foundation.h>
#include "Lexicon/ATProtoLexiconDef.h"
#include "Lexicon/ATProtoLexiconConstraints.h"
#include <stdint.h>
#include <stdlib.h>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
    @autoreleasepool {
        if (Size == 0) return 0;

        NSData *inputData = [NSData dataWithBytes:Data length:Size];

        // Attempt to parse as a Lexicon definition JSON
        NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:inputData options:0 error:&error];
        if (parsed && [parsed isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)parsed;

            // Attempt to build a lexicon def from the parsed JSON
            NSError *defError = nil;
            ATProtoLexiconDef *def = [ATProtoLexiconDef definitionFromDictionary:dict
                                                                           error:&defError];
            if (def) {
                // Validate constraints on a sample value
                NSError *constraintError = nil;
                [ATProtoLexiconConstraints validateValue:@"test"
                                           againstSchema:def
                                                   error:&constraintError];
            }
        }
    }
    return 0;
}
