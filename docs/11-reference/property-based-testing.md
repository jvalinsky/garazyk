# Property-Based Testing

September PDS uses property-based testing (PBT) principles to validate correctness properties across a wide range of inputs. While the project doesn't use a formal PBT framework like QuickCheck or Hypothesis, it employs randomized testing, fuzzing, and invariant checking to achieve similar goals.

## Testing Philosophy

Property-based testing focuses on specifying properties that should hold for all valid inputs, rather than testing specific examples. September validates:

1. **Correctness Properties** - Invariants that must always hold
2. **Round-Trip Properties** - Encode/decode cycles preserve data
3. **Security Properties** - Attack vectors are properly defended
4. **Protocol Compliance** - AT Protocol specifications are followed

## Randomized Testing

### Random Data Generation

September uses cryptographically secure random generation for test data:

```objective-c
// Generate random bytes
NSData *randomData = [CryptoUtils randomBytes:32];

// Generate random code verifier (PKCE)
+ (NSString *)generateCodeVerifier {
    NSData *randomData = [CryptoUtils randomBytes:32];
    return [CryptoUtils base64URLEncode:randomData];
}

// Generate random invite code
NSString *alphabet = @"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
NSMutableString *code = [NSMutableString string];
for (int i = 0; i < 4; i++) {
    unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
    [code appendFormat:@"%C", c];
}
```

### Random Test Fixtures

Tests generate random data to explore edge cases:

```objective-c
- (void)testHandleRandomInputs {
    for (int i = 0; i < 100; i++) {
        // Generate random handle
        NSUInteger length = arc4random_uniform(50) + 1;
        NSMutableString *handle = [NSMutableString string];
        for (NSUInteger j = 0; j < length; j++) {
            unichar c = 'a' + arc4random_uniform(26);
            [handle appendFormat:@"%C", c];
        }
        
        // Test validation
        BOOL isValid = [ATProtoHandleValidator validateHandle:handle];
        // Verify invariants hold
    }
}
```

## Fuzz Testing

September includes a comprehensive fuzzing infrastructure in `fuzzing/`:

### Fuzzer Targets

```
fuzzing/
├── fuzz_xrpc          # XRPC request parsing
├── fuzz_cbor          # CBOR decoding
├── fuzz_car           # CAR file parsing
├── fuzz_mst           # MST tree operations
├── fuzz_did           # DID document parsing
├── fuzz_jwt           # JWT token parsing
└── corpus_*/          # Seed inputs for each fuzzer
```

### Building Fuzzers

```bash
mkdir -p build && cd build
cmake .. -DBUILD_FUZZERS=ON
make -j$(sysctl -n hw.ncpu)
```

### Running Fuzzers

```bash
# Run XRPC fuzzer with corpus
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/

# Run CBOR fuzzer
./build/fuzzing/fuzz_cbor fuzzing/corpus_cbor/

# Run with specific input
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/xrpc_valid_create.txt
```

### Fuzzer Implementation Pattern

```objective-c
// fuzz_cbor.m
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        NSData *input = [NSData dataWithBytes:data length:size];
        
        // Try to decode - should not crash
        NSError *error = nil;
        id decoded = [ATProtoDagCBOR decodeData:input error:&error];
        
        if (decoded) {
            // If decode succeeded, verify round-trip property
            NSData *reencoded = [ATProtoDagCBOR encodeObject:decoded error:nil];
            if (reencoded) {
                id redecoded = [ATProtoDagCBOR decodeData:reencoded error:nil];
                // Verify equivalence
                assert([decoded isEqual:redecoded]);
            }
        }
        
        return 0;
    }
}
```

## Correctness Properties

### Round-Trip Properties

Encoding and decoding should be inverse operations:

```objective-c
- (void)testCBORRoundTrip {
    NSDictionary *original = @{
        @"text": @"Hello",
        @"number": @42,
        @"nested": @{@"key": @"value"}
    };
    
    // Encode
    NSError *error = nil;
    NSData *encoded = [ATProtoDagCBOR encodeObject:original error:&error];
    XCTAssertNotNil(encoded);
    
    // Decode
    id decoded = [ATProtoDagCBOR decodeData:encoded error:&error];
    XCTAssertNotNil(decoded);
    
    // Property: decode(encode(x)) == x
    XCTAssertEqualObjects(decoded, original);
}
```

### Canonical Encoding Properties

CBOR encoding must be canonical (deterministic):

```objective-c
- (void)testCBORCanonicalEncoding {
    NSDictionary *data = @{
        @"z": @"last",
        @"a": @"first",
        @"m": @"middle"
    };
    
    // Encode multiple times
    NSData *encoded1 = [ATProtoDagCBOR encodeObject:data error:nil];
    NSData *encoded2 = [ATProtoDagCBOR encodeObject:data error:nil];
    
    // Property: encode(x) always produces same bytes
    XCTAssertEqualObjects(encoded1, encoded2);
    
    // Property: keys must be sorted
    // Verify byte-level ordering
}
```

### MST Tree Properties

MST (Merkle Search Tree) must maintain invariants:

```objective-c
- (void)testMSTInvariants {
    MST *tree = [[MST alloc] init];
    
    // Insert random keys
    NSMutableArray *keys = [NSMutableArray array];
    for (int i = 0; i < 100; i++) {
        NSString *key = [self generateRandomKey];
        [keys addObject:key];
        [tree insertKey:key value:@{@"data": @"value"}];
    }
    
    // Property 1: All inserted keys are retrievable
    for (NSString *key in keys) {
        XCTAssertNotNil([tree getValueForKey:key]);
    }
    
    // Property 2: Tree is balanced (height is O(log n))
    NSUInteger height = [tree height];
    NSUInteger maxHeight = (NSUInteger)(log2(keys.count) * 2);
    XCTAssertLessThanOrEqual(height, maxHeight);
    
    // Property 3: Keys are in sorted order
    NSArray *allKeys = [tree allKeys];
    NSArray *sortedKeys = [allKeys sortedArrayUsingSelector:@selector(compare:)];
    XCTAssertEqualObjects(allKeys, sortedKeys);
    
    // Property 4: CID is deterministic
    NSString *cid1 = [tree rootCID];
    NSString *cid2 = [tree rootCID];
    XCTAssertEqualObjects(cid1, cid2);
}
```

## Security Properties

### Input Validation Properties

All inputs must be validated before processing:

```objective-c
- (void)testHandleValidationProperties {
    // Property: Invalid handles are rejected
    NSArray *invalidHandles = @[
        @"",                    // Empty
        @"a",                   // Too short
        @"UPPERCASE.test",      // Uppercase not allowed
        @"under_score.test",    // Underscore not allowed
        @"test..double.test",   // Double dot
        @".leading.test",       // Leading dot
        @"trailing.test.",      // Trailing dot
        @"test.123456789012345678901234567890123456789012345678901234567890", // Too long
    ];
    
    for (NSString *handle in invalidHandles) {
        BOOL isValid = [ATProtoHandleValidator validateHandle:handle];
        XCTAssertFalse(isValid, @"Should reject: %@", handle);
    }
    
    // Property: Valid handles are accepted
    NSArray *validHandles = @[
        @"alice.test",
        @"bob-smith.example.com",
        @"user123.bsky.social",
    ];
    
    for (NSString *handle in validHandles) {
        BOOL isValid = [ATProtoHandleValidator validateHandle:handle];
        XCTAssertTrue(isValid, @"Should accept: %@", handle);
    }
}
```

### SSRF Protection Properties

Private IP addresses must be rejected:

```objective-c
- (void)testSSRFProtectionProperties {
    NSArray *privateIPs = @[
        @"127.0.0.1",           // Loopback
        @"10.0.0.1",            // Private class A
        @"172.16.0.1",          // Private class B
        @"192.168.1.1",         // Private class C
        @"169.254.1.1",         // Link-local
        @"::1",                 // IPv6 loopback
        @"fc00::1",             // IPv6 private
    ];
    
    for (NSString *ip in privateIPs) {
        BOOL isAllowed = [SSRFValidator isIPAddressAllowed:ip];
        XCTAssertFalse(isAllowed, @"Should reject private IP: %@", ip);
    }
}
```

## Characterization Tests

Characterization tests document existing behavior and detect regressions:

```objective-c
@interface ActorStoreCharacterizationTests : XCTestCase
@end

@implementation ActorStoreCharacterizationTests

- (void)testSigningKeyWarningBehavior {
    // Document current behavior: ActorStore logs warning when signing key is missing
    // This test captures the current state and will fail if behavior changes
    
    ActorStore *store = [[ActorStore alloc] initWithPath:@"/tmp/test"];
    
    // Capture log output
    __block BOOL warningLogged = NO;
    // ... log capture setup ...
    
    [store getSigningKey];
    
    // Property: Warning is logged when key is missing
    XCTAssertTrue(warningLogged, @"Expected warning about missing signing key");
}

@end
```

## Interoperability Properties

Tests verify compliance with AT Protocol specifications:

```objective-c
- (void)testMSTInteroperability {
    // Load reference test vectors from AT Protocol spec
    NSString *fixturePath = [[NSBundle bundleForClass:[self class]] 
                             pathForResource:@"mst-test-vectors" ofType:@"json"];
    NSData *fixtureData = [NSData dataWithContentsOfFile:fixturePath];
    NSDictionary *testVectors = [NSJSONSerialization JSONObjectWithData:fixtureData 
                                                                options:0 
                                                                  error:nil];
    
    for (NSDictionary *vector in testVectors[@"tests"]) {
        NSArray *operations = vector[@"operations"];
        NSString *expectedCID = vector[@"expectedCID"];
        
        MST *tree = [[MST alloc] init];
        for (NSDictionary *op in operations) {
            [tree insertKey:op[@"key"] value:op[@"value"]];
        }
        
        // Property: Implementation matches reference implementation
        XCTAssertEqualObjects([tree rootCID], expectedCID);
    }
}
```

## Test Data Generators

### Handle Generator

```objective-c
- (NSString *)generateRandomHandle {
    NSArray *segments = @[
        [self randomAlphanumeric:arc4random_uniform(10) + 3],
        [self randomAlphanumeric:arc4random_uniform(10) + 3],
        @"test"
    ];
    return [segments componentsJoinedByString:@"."];
}

- (NSString *)randomAlphanumeric:(NSUInteger)length {
    NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz0123456789";
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [alphabet characterAtIndex:arc4random_uniform((uint32_t)alphabet.length)];
        [result appendFormat:@"%C", c];
    }
    return result;
}
```

### DID Generator

```objective-c
- (NSString *)generateRandomDID {
    NSData *randomBytes = [CryptoUtils randomBytes:16];
    NSString *encoded = [CryptoUtils base32Encode:randomBytes];
    return [NSString stringWithFormat:@"did:plc:%@", [encoded lowercaseString]];
}
```

### Record Generator

```objective-c
- (NSDictionary *)generateRandomPost {
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | 
                              NSISO8601DateFormatWithFractionalSeconds;
    
    return @{
        @"$type": @"app.bsky.feed.post",
        @"text": [self generateRandomText:arc4random_uniform(280) + 1],
        @"createdAt": [formatter stringFromDate:[NSDate date]]
    };
}
```

## Best Practices

1. **Test Invariants** - Focus on properties that must always hold
2. **Use Random Data** - Generate diverse inputs to explore edge cases
3. **Verify Round-Trips** - Encode/decode cycles should preserve data
4. **Check Boundaries** - Test minimum, maximum, and invalid values
5. **Fuzz Parsers** - Use fuzzing for all input parsing code
6. **Document Behavior** - Use characterization tests for complex behavior
7. **Test Security** - Verify attack vectors are properly defended

## Limitations

September's testing approach has some limitations compared to formal PBT frameworks:

- No automatic shrinking of failing test cases
- Manual test data generation (no built-in generators)
- Limited property specification language
- No automatic property discovery

These limitations are mitigated by:
- Comprehensive fuzzing infrastructure
- Extensive interoperability test suites
- Security-focused testing
- Manual property verification

## See Also

- [Test Organization](test-organization) - Test structure and discovery
- [E2E Testing](e2e-testing) - End-to-end test scenarios
- [Test Coverage Goals](test-coverage-goals) - Coverage targets
- [Security Audit Guide](security-audit-guide) - Security testing
