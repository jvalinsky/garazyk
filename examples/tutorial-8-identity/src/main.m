#import <Foundation/Foundation.h>
#import "TutorialIdentityService.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 8: Identity & DID Resolution");
        NSLog(@"======================================\n");

        NSError *error = nil;

        // Setup cache directory
        NSString *cacheDir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tutorial-8-identity"];
        [[NSFileManager defaultManager] removeItemAtPath:cacheDir error:nil];

        TutorialIdentityService *identity = [[TutorialIdentityService alloc] initWithCacheDirectory:cacheDir];
        identity.cacheTTL = 300; // 5 minutes

        // ============================================================
        // 1. DID Resolution (did:web)
        // ============================================================
        NSLog(@"1. DID Resolution (did:web)");
        NSLog(@"---------------------------");

        NSString *did = @"did:web:localhost:2583";
        TutorialDIDDocument *doc = [identity resolveDID:did error:&error];
        if (doc) {
            NSLog(@"Resolved DID: %@", doc.did);
            NSLog(@"  Handle: %@", doc.handle);
            NSLog(@"  Verification methods: %lu", (unsigned long)doc.verificationMethods.count);
            NSLog(@"  Services: %lu", (unsigned long)doc.services.count);
            if (doc.services.count > 0) {
                NSLog(@"  PDS endpoint: %@", doc.services[0][@"serviceEndpoint"]);
            }
            NSLog(@"");
        } else {
            NSLog(@"DID resolution failed: %@\n", error.localizedDescription);
        }

        // ============================================================
        // 2. DID Resolution (did:plc)
        // ============================================================
        NSLog(@"2. DID Resolution (did:plc)");
        NSLog(@"---------------------------");

        // Try a real did:plc (will attempt network fetch)
        NSString *plcDid = @"did:plc:ewvi7nxzy7lk2pg3hkbh5u6q"; // bsky.app's DID
        TutorialDIDDocument *plcDoc = [identity resolveDID:plcDid error:&error];
        if (plcDoc) {
            NSLog(@"Resolved DID: %@", plcDoc.did);
            NSLog(@"  Handle: %@", plcDoc.handle);
            NSLog(@"");
        } else {
            NSLog(@"did:plc resolution failed (network may be unavailable): %@\n", error.localizedDescription);
        }

        // ============================================================
        // 3. Handle Resolution
        // ============================================================
        NSLog(@"3. Handle Resolution");
        NSLog(@"--------------------");

        // Try resolving a real handle
        NSString *handle = @"bsky.app";
        NSString *resolvedDID = [identity resolveHandle:handle error:&error];
        if (resolvedDID) {
            NSLog(@"Handle '%@' resolves to: %@", handle, resolvedDID);
            NSLog(@"");
        } else {
            NSLog(@"Handle resolution for '%@' failed (network may be unavailable): %@\n", handle, error.localizedDescription);
        }

        // ============================================================
        // 4. Handle Verification (bidirectional)
        // ============================================================
        NSLog(@"4. Handle Verification");
        NSLog(@"----------------------");

        // For local testing, verify a mock identity
        NSString *localDid = @"did:web:localhost:2583";
        NSString *localHandle = @"handle.localhost";

        // Pre-seed the handle cache for the tutorial
        // (In production, this would come from DNS/HTTPS resolution)
        TutorialDIDDocument *localDoc = [identity resolveDID:localDid error:nil];
        if (localDoc) {
            NSLog(@"Local DID document retrieved");
            NSLog(@"  DID: %@", localDoc.did);
            NSLog(@"  Handle: %@", localDoc.handle);
            NSLog(@"");
        }

        // ============================================================
        // 5. Cache Behavior
        // ============================================================
        NSLog(@"5. Cache Behavior");
        NSLog(@"------------------");

        // Second resolution should hit cache
        NSDate *start = [NSDate date];
        TutorialDIDDocument *cachedDoc = [identity resolveDID:localDid error:nil];
        NSTimeInterval elapsed = -[start timeIntervalSinceNow] * 1000;
        if (cachedDoc) {
            NSLog(@"Second resolution (cached): %.1fms", elapsed);
        }

        // Clear cache and resolve again
        [identity clearCache];
        start = [NSDate date];
        TutorialDIDDocument *freshDoc = [identity resolveDID:localDid error:nil];
        elapsed = -[start timeIntervalSinceNow] * 1000;
        if (freshDoc) {
            NSLog(@"After cache clear: %.1fms\n", elapsed);
        }

        // ============================================================
        // 6. DID Document Structure
        // ============================================================
        NSLog(@"6. DID Document Structure");
        NSLog(@"-------------------------");

        NSLog(@"A DID document contains:");
        NSLog(@"  - id: The DID itself");
        NSLog(@"  - alsoKnownAs: Array of handles");
        NSLog(@"  - verificationMethod: Public keys for signing");
        NSLog(@"  - service: Service endpoints (PDS, etc.)");
        NSLog(@"");
        NSLog(@"Example did:web document:");
        NSLog(@"  {");
        NSLog(@"    \"@context\": [\"https://www.w3.org/ns/did/v1\"],");
        NSLog(@"    \"id\": \"did:web:localhost:2583\",");
        NSLog(@"    \"alsoKnownAs\": [\"handle.localhost\"],");
        NSLog(@"    \"verificationMethod\": [{");
        NSLog(@"      \"id\": \"did:web:localhost:2583#atproto\",");
        NSLog(@"      \"type\": \"Multikey\",");
        NSLog(@"      \"publicKeyMultibase\": \"zQ3sh...\"");
        NSLog(@"    }],");
        NSLog(@"    \"service\": [{");
        NSLog(@"      \"id\": \"did:web:localhost:2583#atproto_pds\",");
        NSLog(@"      \"type\": \"AtprotoPersonalDataServer\",");
        NSLog(@"      \"serviceEndpoint\": \"https://localhost:2583\"");
        NSLog(@"    }]");
        NSLog(@"  }");

        NSLog(@"\n======================================");
        NSLog(@"Tutorial completed!");
        NSLog(@"Key concepts:");
        NSLog(@"  - DID methods: did:web (DNS-based) and did:plc (PLC directory)");
        NSLog(@"  - Handle resolution: HTTPS well-known and DNS TXT");
        NSLog(@"  - Bidirectional verification: handle -> DID and DID -> handle");
        NSLog(@"  - Identity caching with TTL for performance");
    }

    return 0;
}
