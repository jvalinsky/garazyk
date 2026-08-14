// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayEventValidator.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Firehose/Firehose.h"
#import "Repository/RepoCommit.h"
#import "Core/CID.h"
#import "Auth/Crypto/Secp256k1.h"

@interface RelayEventValidatorTestResolver : NSObject <DIDResolving>
@property (nonatomic, strong, nullable) NSDictionary *document;
@end

@implementation RelayEventValidatorTestResolver

- (nullable NSDictionary *)resolveDID:(NSString *)did error:(NSError **)error {
    if (self.document) return self.document;
    if (error) {
        *error = [NSError errorWithDomain:@"RelayEventValidatorTests"
                                     code:1
                                 userInfo:@{NSLocalizedDescriptionKey: @"DID unavailable"}];
    }
    return nil;
}

@end

@interface RelayEventValidatorTests : XCTestCase

@end

@implementation RelayEventValidatorTests

- (void)testLenientModeForwardsAll {
    ATProtoRelayEventValidator *validator = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeLenient];
    
    ATProtoRelayValidationOutcome *validOutcome = [ATProtoRelayValidationOutcome validOutcome];
    XCTAssertTrue([validator shouldForwardEvent:validOutcome]);
    
    ATProtoRelayValidationOutcome *invalidOutcome = [ATProtoRelayValidationOutcome invalidOutcome:@"MST proof failed"];
    XCTAssertTrue([validator shouldForwardEvent:invalidOutcome]);
}

- (void)testStrictModeDropsInvalid {
    ATProtoRelayEventValidator *validator = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeStrict];
    
    ATProtoRelayValidationOutcome *validOutcome = [ATProtoRelayValidationOutcome validOutcome];
    XCTAssertTrue([validator shouldForwardEvent:validOutcome]);
    
    ATProtoRelayValidationOutcome *invalidOutcome = [ATProtoRelayValidationOutcome invalidOutcome:@"Signature invalid"];
    XCTAssertFalse([validator shouldForwardEvent:invalidOutcome]);
}

- (void)testLogOnlyModeForwardsAllButLogs {
    ATProtoRelayEventValidator *validator = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeLogOnly];
    
    ATProtoRelayValidationOutcome *validOutcome = [ATProtoRelayValidationOutcome validOutcome];
    XCTAssertTrue([validator shouldForwardEvent:validOutcome]);
    
    ATProtoRelayValidationOutcome *invalidOutcome = [ATProtoRelayValidationOutcome invalidOutcome:@"Invalid"];
    XCTAssertTrue([validator shouldForwardEvent:invalidOutcome]); // Still forwards
}

- (void)testValidationModesWork {
    // Test lenient
    ATProtoRelayEventValidator *lenient = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeLenient];
    XCTAssertEqual(lenient.validationMode, RelayValidationModeLenient);
    
    // Test strict
    ATProtoRelayEventValidator *strict = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeStrict];
    XCTAssertEqual(strict.validationMode, RelayValidationModeStrict);
    
    // Test logOnly
    ATProtoRelayEventValidator *logOnly = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeLogOnly];
    XCTAssertEqual(logOnly.validationMode, RelayValidationModeLogOnly);
}

- (void)testValidOutcomeCreation {
    ATProtoRelayValidationOutcome *outcome = [ATProtoRelayValidationOutcome validOutcome];
    XCTAssertEqual(outcome.result, RelayValidationResultValid);
    XCTAssertNil(outcome.errorMessage);
}

- (void)testInvalidOutcomeCreation {
    ATProtoRelayValidationOutcome *outcome = [ATProtoRelayValidationOutcome invalidOutcome:@"Test error"];
    XCTAssertEqual(outcome.result, RelayValidationResultInvalidMST);
    XCTAssertNotNil(outcome.errorMessage);
}

- (void)testErrorOutcomeCreation {
    ATProtoRelayValidationOutcome *outcome = [ATProtoRelayValidationOutcome errorOutcome:@"System error"];
    XCTAssertEqual(outcome.result, RelayValidationResultError);
    XCTAssertNotNil(outcome.errorMessage);
}

- (void)testChangeValidationMode {
    ATProtoRelayEventValidator *validator = [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeLenient];
    XCTAssertEqual(validator.validationMode, RelayValidationModeLenient);
    
    validator.validationMode = RelayValidationModeStrict;
    XCTAssertEqual(validator.validationMode, RelayValidationModeStrict);
    
    validator.validationMode = RelayValidationModeLogOnly;
    XCTAssertEqual(validator.validationMode, RelayValidationModeLogOnly);
}

- (ATProtoFirehoseCommitEvent *)signedCommitEventForDID:(NSString *)did
                                         keyPair:(ATProtoSecp256k1KeyPair *)keyPair
                                          commit:(ATProtoRepoCommit **)commitOut {
    ATProtoRepoCommit *commit = [ATProtoRepoCommit createCommitWithDid:did
                                                     data:[ATProtoCID sha256:[@"relay-signature-root" dataUsingEncoding:NSUTF8StringEncoding]]
                                                      rev:@"3lr5msvv5dk2d"
                                                     prev:nil];
    NSError *error = nil;
    XCTAssertTrue([commit signWithPrivateKey:keyPair.privateKey error:&error], @"%@", error);

    ATProtoFirehoseCommitEvent *event = [ATProtoFirehoseCommitEvent eventWithRepo:did
                                                              commit:commit.computeCID
                                                                 ops:@[]];
    event.blocks = commit.exportCAR;
    XCTAssertNotNil(event.blocks);
    if (commitOut) *commitOut = commit;
    return event;
}

- (NSDictionary *)didDocumentForDID:(NSString *)did
                            keyPair:(ATProtoSecp256k1KeyPair *)keyPair
                             legacy:(BOOL)legacy {
    if (legacy) {
        return @{
            @"id": did,
            @"verificationMethods": @{ @"atproto": keyPair.didKeyString },
        };
    }
    return @{
        @"id": did,
        @"verificationMethod": @[
            @{ @"id": [did stringByAppendingString:@"#atproto"],
               @"publicKeyMultibase": [keyPair.didKeyString substringFromIndex:8] },
        ],
    };
}

- (ATProtoRelayEventValidator *)validatorWithDocument:(NSDictionary *)document mode:(RelayValidationMode)mode {
    RelayEventValidatorTestResolver *resolver = [[RelayEventValidatorTestResolver alloc] init];
    resolver.document = document;
    ATProtoRelayEventValidator *validator = [[ATProtoRelayEventValidator alloc] initWithValidationMode:mode];
    validator.plcResolver = resolver;
    return validator;
}

- (void)testCommitSignatureVerificationAcceptsLegacyDidKey {
    NSString *did = @"did:plc:relaylegacy";
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:keyPair commit:nil];
    ATProtoRelayEventValidator *validator = [self validatorWithDocument:[self didDocumentForDID:did keyPair:keyPair legacy:YES]
                                                             mode:RelayValidationModeStrict];

    ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
    XCTAssertEqual(outcome.result, RelayValidationResultValid, @"%@", outcome.errorMessage);
}

- (void)testCommitSignatureVerificationAcceptsVerificationMethodMultibase {
    NSString *did = @"did:plc:relaymodern";
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:keyPair commit:nil];
    ATProtoRelayEventValidator *validator = [self validatorWithDocument:[self didDocumentForDID:did keyPair:keyPair legacy:NO]
                                                             mode:RelayValidationModeStrict];

    ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
    XCTAssertEqual(outcome.result, RelayValidationResultValid, @"%@", outcome.errorMessage);
}

- (void)testCommitSignatureVerificationRejectsTamperedCommitWithMatchingCID {
    NSString *did = @"did:plc:relaytampered";
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoRepoCommit *commit = nil;
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:keyPair commit:&commit];
    NSMutableData *signature = [commit.signature mutableCopy];
    ((uint8_t *)signature.mutableBytes)[0] ^= 0x01;
    commit.signature = signature;
    event.commit = commit.computeCID;
    event.blocks = commit.exportCAR;

    ATProtoRelayEventValidator *validator = [self validatorWithDocument:[self didDocumentForDID:did keyPair:keyPair legacy:YES]
                                                             mode:RelayValidationModeStrict];
    ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
    XCTAssertEqual(outcome.result, RelayValidationResultInvalidSignature);
    XCTAssertFalse([validator shouldForwardEvent:outcome]);
}

- (void)testCommitSignatureVerificationRejectsWrongKey {
    NSString *did = @"did:plc:relaywrongkey";
    ATProtoSecp256k1KeyPair *signingKey = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoSecp256k1KeyPair *wrongKey = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:signingKey commit:nil];
    ATProtoRelayEventValidator *validator = [self validatorWithDocument:[self didDocumentForDID:did keyPair:wrongKey legacy:NO]
                                                             mode:RelayValidationModeStrict];

    ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
    XCTAssertEqual(outcome.result, RelayValidationResultInvalidSignature);
    XCTAssertFalse([validator shouldForwardEvent:outcome]);
}

- (void)testCommitSignatureVerificationRejectsUnresolvedKey {
    NSString *did = @"did:plc:relayunresolved";
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:keyPair commit:nil];
    ATProtoRelayEventValidator *validator = [self validatorWithDocument:nil mode:RelayValidationModeStrict];

    ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
    XCTAssertEqual(outcome.result, RelayValidationResultInvalidSignature);
    XCTAssertFalse([validator shouldForwardEvent:outcome]);
}

- (void)testUnsupportedP256RepositoryKeyIsRejectedAndRecordedAsSignatureFailure {
    NSString *did = @"did:plc:relayp256";
    ATProtoSecp256k1KeyPair *keyPair = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:keyPair commit:nil];
    uint8_t p256Multicodec[] = {0x80, 0x24};
    NSMutableData *encodedKey = [NSMutableData dataWithBytes:p256Multicodec length:sizeof(p256Multicodec)];
    [encodedKey appendData:keyPair.compressedPublicKey];
    NSString *p256Key = [@"did:key:z" stringByAppendingString:[ATProtoCID base58btcEncode:encodedKey]];
    ATProtoRelayEventValidator *validator = [self validatorWithDocument:@{
        @"id": did,
        @"verificationMethods": @{ @"atproto": p256Key },
    } mode:RelayValidationModeStrict];

    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    NSDictionary *before = [metrics snapshotDictionary];
    int64_t failuresBefore = [before[@"signatureValidationFailure"] longLongValue];
    int64_t signingKeyBefore = [before[@"signatureValidationFailuresByCategory"][@"signing-key"] longLongValue];
    ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
    NSDictionary *after = [metrics snapshotDictionary];
    int64_t failuresAfter = [after[@"signatureValidationFailure"] longLongValue];
    int64_t signingKeyAfter = [after[@"signatureValidationFailuresByCategory"][@"signing-key"] longLongValue];

    XCTAssertEqual(outcome.result, RelayValidationResultInvalidSignature);
    XCTAssertEqual(failuresAfter, failuresBefore + 1);
    XCTAssertEqual(signingKeyAfter, signingKeyBefore + 1);
}

- (void)testValidationPolicyDoesNotCountForwardingBeforeDelivery {
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    int64_t forwardedBefore = [[metrics snapshotDictionary][@"eventsForwarded"] longLongValue];
    int64_t validatedBefore = [[metrics snapshotDictionary][@"eventsValidated"] longLongValue];

    ATProtoRelayEventValidator *validator =
        [[ATProtoRelayEventValidator alloc] initWithValidationMode:RelayValidationModeLogOnly];
    XCTAssertTrue([validator shouldForwardEvent:[ATProtoRelayValidationOutcome validOutcome]]);

    NSDictionary *after = [metrics snapshotDictionary];
    XCTAssertEqual([after[@"eventsForwarded"] longLongValue], forwardedBefore);
    XCTAssertEqual([after[@"eventsValidated"] longLongValue], validatedBefore + 1);
}

- (void)testSignatureValidationModesRetainAvailabilityPolicy {
    NSString *did = @"did:plc:relaypolicy";
    ATProtoSecp256k1KeyPair *signingKey = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoSecp256k1KeyPair *wrongKey = [[ATProtoSecp256k1 shared] generateKeyPairWithError:nil];
    ATProtoFirehoseCommitEvent *event = [self signedCommitEventForDID:did keyPair:signingKey commit:nil];
    NSDictionary *document = [self didDocumentForDID:did keyPair:wrongKey legacy:YES];

    for (NSNumber *modeValue in @[@(RelayValidationModeLenient), @(RelayValidationModeLogOnly), @(RelayValidationModeStrict)]) {
        RelayValidationMode mode = (RelayValidationMode)modeValue.integerValue;
        ATProtoRelayEventValidator *validator = [self validatorWithDocument:document mode:mode];
        ATProtoRelayValidationOutcome *outcome = [validator validateCommitEvent:event];
        XCTAssertEqual(outcome.result, RelayValidationResultInvalidSignature);
        XCTAssertEqual([validator shouldForwardEvent:outcome], mode != RelayValidationModeStrict);
    }
}

@end
