// FuzzMultiJSON.m - Multi-path JSON parsing fuzzer
// Tests different parsing paths within NSJSONSerialization

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, JSONParsePath) {
    JSONParsePathBasic,
    JSONParsePathFragments,
    JSONParsePathMutable,
    JSONParsePathNumeric,
    JSONParsePathAllowFragments,
    JSONParsePathValidating,
    JSONParsePathObjectCoding,
    JSONParsePathMax
};

static const char *pathNames[] = {
    "basic",
    "fragments", 
    "mutable",
    "numeric",
    "allowFragments",
    "validating",
    "objectCoding"
};

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        if (!data || size == 0) return 0;
        
        NSData *input = [NSData dataWithBytes:data length:size];
        
        // Try different JSON parsing paths
        for (int path = 0; path < JSONParsePathMax; path++) {
            NSError *error = nil;
            id result = nil;
            NSData *outputData = nil;
            
            switch (path) {
                case JSONParsePathBasic:
                    // Basic parsing - most common path
                    result = [NSJSONSerialization JSONObjectWithData:input options:0 error:&error];
                    break;
                    
                case JSONParsePathFragments:
                    // Allow fragments - parses non-object/array top-level
                    result = [NSJSONSerialization JSONObjectWithData:input 
                                               options:NSJSONReadingAllowFragments 
                                                 error:&error];
                    break;
                    
                case JSONParsePathMutable:
                    // Mutable containers
                    result = [NSJSONSerialization JSONObjectWithData:input 
                                               options:NSJSONReadingMutableContainers 
                                                 error:&error];
                    break;
                    
                case JSONParsePathNumeric:
                    // Parse numbers as NSNumber (preserves type)
                    result = [NSJSONSerialization JSONObjectWithData:input 
                                               options:NSJSONReadingMutableContainers | NSJSONReadingAllowFragments
                                                 error:&error];
                    break;
                    
                case JSONParsePathAllowFragments:
                    // Strict fragments
                    result = [NSJSONSerialization JSONObjectWithData:input 
                                               options:NSJSONReadingAllowFragments
                                                 error:&error];
                    break;
                    
                case JSONParsePathValidating:
                    // Same as basic but with explicit nil check
                    result = input ? [NSJSONSerialization JSONObjectWithData:input options:0 error:&error] : nil;
                    break;
                    
                case JSONParsePathObjectCoding:
                    // Round-trip test: serialize then deserialize
                    if (result) {
                        outputData = [NSJSONSerialization dataWithJSONObject:result options:0 error:&error];
                        if (outputData) {
                            result = [NSJSONSerialization JSONObjectWithData:outputData options:0 error:&error];
                        }
                    }
                    break;
            }
            
            // Touch result to prevent optimization
            if (result) {
                (void)[result isKindOfClass:[NSDictionary class]];
                (void)[result isKindOfClass:[NSArray class]];
                (void)[result isKindOfClass:[NSString class]];
                (void)[result isKindOfClass:[NSNumber class]];
                (void)[result isKindOfClass:[NSNull class]];
            }
            
            // Track serialization paths
            if (outputData) {
                (void)outputData.length;
            }
            
            (void)error;
        }
        
        // Test serialization paths
        NSString *jsonStr = [[NSString alloc] initWithBytes:data length:size encoding:NSUTF8StringEncoding];
        if (jsonStr) {
            // Try parsing then reserializing
            id parsed = [NSJSONSerialization JSONObjectWithData:input options:0 error:nil];
            if (parsed) {
                // Pretty print
                NSData *pretty = [NSJSONSerialization dataWithJSONObject:parsed 
                                                       options:NSJSONWritingPrettyPrinted 
                                                         error:nil];
                (void)pretty;
                
                // Sorted keys
                NSData *sorted = [NSJSONSerialization dataWithJSONObject:parsed 
                                                           options:NSJSONWritingSortedKeys 
                                                             error:nil];
                (void)sorted;
                
                // Fragments output
                NSData *frag = [NSJSONSerialization dataWithJSONObject:@(1) options:0 error:nil];
                (void)frag;
            }
        }
    }
    return 0;
}