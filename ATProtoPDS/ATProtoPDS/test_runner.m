#import <Foundation/Foundation.h>
#import "CID.h"
#import "TID.h"
#import "DID.h"

/// Simple test runner for core ATProto types
int runTests(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"🧪 Running ATProto Core Tests");
        NSUInteger totalTests = 0;
        NSUInteger passedTests = 0;
        
        // CID Tests
        NSLog(@"📋 Testing CID implementation...");
        
        // Test 1: CID Creation
        totalTests++;
        uint8_t sha256Bytes[] = {0x12, 0x20, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                                0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                                0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
                                0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20};
        NSData *multihash = [NSData dataWithBytes:sha256Bytes length:sizeof(sha256Bytes)];
        CID *cid = [CID cidWithMultihash:multihash codec:0x71];
        if (cid && cid.version == 1 && cid.codec == 0x71 && [cid.multihash isEqualToData:multihash]) {
            passedTests++;
            NSLog(@"✅ CID Creation: PASSED");
        } else {
            NSLog(@"❌ CID Creation: FAILED");
        }
        
        // Test 2: CID String Encoding Round-trip
        totalTests++;
        NSString *cidString = cid.stringValue;
        NSLog(@"CID string: %@", cidString);
        CID *decodedCID = [CID cidFromString:cidString];
        if (decodedCID) {
            NSLog(@"Decoded CID codec: %lu, version: %lu", (unsigned long)decodedCID.codec, (unsigned long)decodedCID.version);
            if ([cid isEqualToCID:decodedCID]) {
                passedTests++;
                NSLog(@"✅ CID String Encoding: PASSED");
            } else {
                NSLog(@"❌ CID String Encoding: FAILED");
            }
        } else {
            NSLog(@"❌ CID String Encoding: FAILED (decode returned nil)");
        }
        
        // Test 3: Basic CID functionality
        totalTests++;
        if (cid && cid.stringValue && decodedCID) {
            passedTests++;
            NSLog(@"✅ CID Basic Functionality: PASSED");
        } else {
            NSLog(@"❌ CID Basic Functionality: FAILED");
        }
        
        // TID Tests
        NSLog(@"📋 Testing TID implementation...");
        
        // Test 4: TID Creation
        totalTests++;
        TID *tid = [TID tid];
        if (tid && tid.stringValue.length == 13) {
            passedTests++;
            NSLog(@"✅ TID Creation: PASSED");
        } else {
            NSLog(@"❌ TID Creation: FAILED");
        }
        
        // Test 5: TID String Validation
        totalTests++;
        NSString *tidString = tid.stringValue;
        BOOL validChars = YES;
        NSCharacterSet *validTIDChars = [NSCharacterSet characterSetWithCharactersInString:@"234567abcdefghijklmnopqrstuvwxyz"];
        for (NSUInteger i = 0; i < tidString.length; i++) {
            unichar c = [tidString characterAtIndex:i];
            if (![validTIDChars characterIsMember:c]) {
                validChars = NO;
                break;
            }
        }
        unichar firstChar = [tidString characterAtIndex:0];
        NSString *validFirstChars = @"234567abcdefghij";
        BOOL validFirst = [validFirstChars containsString:[NSString stringWithCharacters:&firstChar length:1]];
        
        if (validChars && validFirst) {
            passedTests++;
            NSLog(@"✅ TID String Validation: PASSED");
        } else {
            NSLog(@"❌ TID String Validation: FAILED");
        }
        
        // Test 6: TID Round-trip
        totalTests++;
        TID *decodedTID = [TID tidFromString:tidString];
        if ([tid isEqual:decodedTID]) {
            passedTests++;
            NSLog(@"✅ TID Round-trip: PASSED");
        } else {
            NSLog(@"❌ TID Round-trip: FAILED");
        }
        
        // Test 7: TID Ordering
        totalTests++;
        TID *tid1 = [TID tidWithTimestamp:1000000];
        TID *tid2 = [TID tidWithTimestamp:2000000];
        if ([tid1 isBefore:tid2] && [tid2 isAfter:tid1]) {
            passedTests++;
            NSLog(@"✅ TID Ordering: PASSED");
        } else {
            NSLog(@"❌ TID Ordering: FAILED");
        }
        
        // DID Tests
        NSLog(@"📋 Testing DID implementation...");
        
        // Test 8: DID Document Creation
        totalTests++;
        NSDictionary *json = @{
            @"id": @"did:web:example.com",
            @"alsoKnownAs": @[@"at://alice.example.com"],
            @"service": @{
                @"id": @"#atproto_pds",
                @"type": @"AtprotoPersonalDataServer",
                @"serviceEndpoint": @"https://pds.example.com"
            }
        };
        NSError *error;
        DIDDocument *doc = [DIDDocument documentWithJSON:json error:&error];
        if (doc && [doc.id isEqualToString:@"did:web:example.com"]) {
            passedTests++;
            NSLog(@"✅ DID Document Creation: PASSED");
        } else {
            NSLog(@"❌ DID Document Creation: FAILED");
        }
        
        // Test 9: DID Validation
        totalTests++;
        DIDResolver *resolver = [[DIDResolver alloc] init];
        DIDDocument *invalidDoc = [resolver resolveDIDSync:@"" error:&error];
        if (!invalidDoc && error) {
            passedTests++;
            NSLog(@"✅ DID Validation: PASSED");
        } else {
            NSLog(@"❌ DID Validation: FAILED");
        }
        
        // Summary
        NSLog(@"🎯 Test Results: %lu/%lu tests passed", (unsigned long)passedTests, (unsigned long)totalTests);
        
        if (passedTests == totalTests) {
            NSLog(@"🎉 All tests PASSED! Core ATProto types are working correctly.");
            return 0;
        } else {
            NSLog(@"⚠️  Some tests FAILED. Please review the implementation.");
            return 1;
        }
    }
}

int main(int argc, const char * argv[]) {
    return runTests(argc, argv);
}