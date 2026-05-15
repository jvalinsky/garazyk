---
title: Property-Based Testing
---

# Property-Based Testing

Garazyk PDS uses property-based testing (PBT) to validate correctness across broad input ranges. While the project does not use a formal PBT framework, it employs randomized testing, fuzzing, and invariant checking.

## Testing Categories

1. **Correctness**: Invariants that must hold for all valid inputs.
2. **Round-Trip**: Encode and decode cycles that preserve data integrity.
3. **Security**: Resistance to malformed input and protocol-level attacks.
4. **Protocol Compliance**: Adherence to AT Protocol specifications.

## Randomized Testing

The system uses cryptographically secure random generation for test data like invite codes and PKCE verifiers. Tests also generate random fixtures to explore edge cases in validators.

```objective-c
- (void)testHandleRandomInputs {
    for (int i = 0; i < 100; i++) {
        NSUInteger length = arc4random_uniform(50) + 1;
        NSMutableString *handle = [NSMutableString string];
        for (NSUInteger j = 0; j < length; j++) {
            unichar c = 'a' + arc4random_uniform(26);
            [handle appendFormat:@"%C", c];
        }
        XCTAssertTrue([ATProtoHandleValidator validateHandle:handle]);
    }
}
```

## Fuzz Testing

Infrastructure in `fuzzing/` targets critical parsers:

- `fuzz_xrpc`: XRPC request parsing.
- `fuzz_cbor`: CBOR decoding.
- `fuzz_car`: CAR file parsing.
- `fuzz_mst`: MST tree operations.
- `fuzz_did`: DID document parsing.
- `fuzz_jwt`: JWT token parsing.

### Execution

```bash
mkdir -p build && cd build
cmake .. -DBUILD_FUZZERS=ON
make -j$(sysctl -n hw.ncpu)
./build/fuzzing/fuzz_xrpc fuzzing/corpus_xrpc/
```

## Invariants

### Round-Trip Equality

Encoding followed by decoding must return the original object.

```objective-c
- (void)testCBORRoundTrip {
    NSDictionary *original = @{@"text": @"Hello", @"number": @42};
    NSData *encoded = [ATProtoDagCBOR encodeObject:original error:nil];
    id decoded = [ATProtoDagCBOR decodeData:encoded error:nil];
    XCTAssertEqualObjects(decoded, original);
}
```

### Canonical Encoding

CBOR encoding must remain deterministic and lexicographically sorted.

```objective-c
- (void)testCBORCanonicalEncoding {
    NSDictionary *data = @{@"z": @"last", @"a": @"first"};
    NSData *encoded1 = [ATProtoDagCBOR encodeObject:data error:nil];
    NSData *encoded2 = [ATProtoDagCBOR encodeObject:data error:nil];
    XCTAssertEqualObjects(encoded1, encoded2);
}
```

### MST Properties

Merkle Search Trees must maintain these structural invariants:

- **Retrievability**: All inserted keys remain retrievable.
- **Balance**: Tree height stays within O(log n).
- **Sorting**: Keys remain in lexicographical order.
- **Determinism**: The root CID is deterministic for a given set of keys.

## Security Properties

### Input Validation

Validators reject:
- Empty strings or strings below minimum length.
- Uppercase characters or underscores where prohibited.
- Double dots, leading dots, or trailing dots in handles.
- Strings exceeding maximum length limits.

### SSRF Protection

Validators reject private IP ranges including loopback (`127.0.0.1`), private networks (`10.0.0.0/8`), and link-local addresses (`169.254.0.0/16`).

## Interoperability

Tests verify adherence to external specifications using reference vectors from the AT Protocol spec.

## Limitations

Garazyk's approach lacks automatic shrinking of failing test cases and formal property discovery. These are mitigated by fuzzing infrastructure, interoperability test suites, and characterization tests.

## Related Resources

- [Test Organization](./test-organization)
- [E2E Testing](./e2e-testing)
- [Test Coverage Goals](./test-coverage-goals)
- [Security Audit Guide](./security-audit-guide)
- [Documentation Map](documentation-map.md)
