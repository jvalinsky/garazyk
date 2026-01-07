#import <Foundation/Foundation.h>
#import "CID.h"
#import "TID.h"
#import "DID.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSLog(@"Testing ATProto core data types...");

        // Test CID creation and encoding
        uint8_t sha256[] = {0x12, 0x20, 0x01, 0x02, 0x03, 0x04}; // SHA-256 multihash prefix + dummy digest
        NSData *multihash = [NSData dataWithBytes:sha256 length:sizeof(sha256)];

        CID *cid = [CID cidWithMultihash:multihash codec:0x71]; // dag-cbor codec
        if (cid) {
            NSString *cidString = cid.stringValue;
            NSLog(@"Created CID: %@", cidString);

            // Test round-trip
            CID *decodedCID = [CID cidFromString:cidString];
            if ([cid isEqualToCID:decodedCID]) {
                NSLog(@"CID round-trip successful");
            } else {
                NSLog(@"CID round-trip failed");
            }
        }

        // Test TID creation
        TID *tid1 = [TID tid];
        TID *tid2 = [TID tid];

        NSLog(@"Created TID 1: %@", tid1.stringValue);
        NSLog(@"Created TID 2: %@", tid2.stringValue);

        // Test TID ordering
        NSComparisonResult comparison = [tid1 compare:tid2];
        if (comparison == NSOrderedAscending) {
            NSLog(@"TID 1 is before TID 2 (as expected)");
        } else if (comparison == NSOrderedDescending) {
            NSLog(@"TID 2 is before TID 1");
        } else {
            NSLog(@"TIDs are equal (unexpected)");
        }

        // Test TID parsing
        TID *parsedTID = [TID tidFromString:tid1.stringValue];
        if ([tid1 isEqual:parsedTID]) {
            NSLog(@"TID parsing successful");
        } else {
            NSLog(@"TID parsing failed");
        }

        // Test DID resolver (basic validation)
        DIDResolver *resolver = [[DIDResolver alloc] init];
        NSError *didError;

        // Test did:web (may fail if no server)
        DIDDocument *doc = [resolver resolveDIDSync:@"did:web:example.com" error:&didError];
        if (doc) {
            NSLog(@"DID web resolution successful: %@", doc.id);
        } else {
            NSLog(@"DID web resolution failed: %@", didError.localizedDescription);
        }

        // Test did:plc with a real DID
        didError = nil;
        DIDDocument *plcDoc = [resolver resolveDIDSync:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz" error:&didError];
        if (plcDoc) {
            NSLog(@"DID plc resolution successful: %@", plcDoc.id);
        } else {
            NSLog(@"DID plc resolution failed: %@", didError.localizedDescription);
        }

        // Test caching - resolve again
        didError = nil;
        DIDDocument *cachedDoc = [resolver resolveDIDSync:@"did:plc:ewvi7nxzyoun6zhxrhs64oiz" error:&didError];
        if (cachedDoc) {
            NSLog(@"DID plc cached resolution successful: %@", cachedDoc.id);
        } else {
            NSLog(@"DID plc cached resolution failed: %@", didError.localizedDescription);
        }

        NSLog(@"Core data type tests completed");
    }
    return 0;
}