// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayEventValidator.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/ATProtoDIDDocumentFields.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Repository/CAR.h"
#import "Repository/RepoCommit.h"
#import "Debug/GZLogger.h"

static NSString *const RelaySignatureFailureResolverUnavailable = @"resolver-unavailable";
static NSString *const RelaySignatureFailureDIDResolution = @"did-resolution";
static NSString *const RelaySignatureFailureDIDDocument = @"did-document";
static NSString *const RelaySignatureFailureSigningKey = @"signing-key";
static NSString *const RelaySignatureFailureCommitBlock = @"commit-block";
static NSString *const RelaySignatureFailureCommitIdentity = @"commit-identity";
static NSString *const RelaySignatureFailureSignatureMismatch = @"signature-mismatch";

static NSTimeInterval const RelaySignatureDiagnosticInterval = 60.0;

static NSString *RelayCanonicalSignatureFailureCategory(NSString *category) {
    static NSSet<NSString *> *allowedCategories;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        allowedCategories = [NSSet setWithArray:@[
            RelaySignatureFailureResolverUnavailable, RelaySignatureFailureDIDResolution,
            RelaySignatureFailureDIDDocument, RelaySignatureFailureSigningKey,
            RelaySignatureFailureCommitBlock, RelaySignatureFailureCommitIdentity,
            RelaySignatureFailureSignatureMismatch, @"unknown"
        ]];
    });
    return [allowedCategories containsObject:category] ? [category copy] : @"unknown";
}

static void RelayLogSignatureDiagnostic(NSString *category) {
    static dispatch_queue_t diagnosticQueue;
    static NSMutableDictionary<NSString *, NSDate *> *lastDiagnosticAt;
    static NSMutableDictionary<NSString *, NSNumber *> *suppressedDiagnosticCount;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        diagnosticQueue = dispatch_queue_create("com.atproto.relay.signature-diagnostics", DISPATCH_QUEUE_SERIAL);
        lastDiagnosticAt = [NSMutableDictionary dictionary];
        suppressedDiagnosticCount = [NSMutableDictionary dictionary];
    });

    dispatch_async(diagnosticQueue, ^{
        NSDate *now = [NSDate date];
        NSDate *lastLogged = lastDiagnosticAt[category];
        if (lastLogged && [now timeIntervalSinceDate:lastLogged] < RelaySignatureDiagnosticInterval) {
            int64_t suppressed = [suppressedDiagnosticCount[category] longLongValue];
            suppressedDiagnosticCount[category] = @(suppressed + 1);
            return;
        }

        int64_t suppressed = [suppressedDiagnosticCount[category] longLongValue];
        suppressedDiagnosticCount[category] = @0;
        lastDiagnosticAt[category] = now;
        if (suppressed > 0) {
            GZ_LOG_SYNC_WARN(@"Relay commit signature validation failed category=%@ suppressed=%lld",
                             category, (long long)suppressed);
        } else {
            GZ_LOG_SYNC_WARN(@"Relay commit signature validation failed category=%@", category);
        }
    });
}

@interface ATProtoRelayValidationOutcome ()

+ (instancetype)invalidSignatureOutcome:(NSString *)reason category:(NSString *)category;

@end

@implementation ATProtoRelayValidationOutcome

+ (instancetype)validOutcome {
    ATProtoRelayValidationOutcome *outcome = [[ATProtoRelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultValid;
    return outcome;
}

+ (instancetype)invalidOutcome:(NSString *)reason {
    ATProtoRelayValidationOutcome *outcome = [[ATProtoRelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultInvalidMST;
    outcome.errorMessage = reason;
    return outcome;
}

+ (instancetype)errorOutcome:(NSString *)error {
    ATProtoRelayValidationOutcome *outcome = [[ATProtoRelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultError;
    outcome.errorMessage = error;
    return outcome;
}

+ (instancetype)invalidSignatureOutcome:(NSString *)reason {
    return [self invalidSignatureOutcome:reason category:@"unknown"];
}

+ (instancetype)invalidSignatureOutcome:(NSString *)reason category:(NSString *)category {
    NSString *canonicalCategory = RelayCanonicalSignatureFailureCategory(category);
    [[ATProtoRelayMetrics sharedMetrics] recordSignatureValidationFailureWithCategory:canonicalCategory];
    RelayLogSignatureDiagnostic(canonicalCategory);
    ATProtoRelayValidationOutcome *outcome = [[ATProtoRelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultInvalidSignature;
    outcome.errorMessage = reason;
    return outcome;
}

@end

@interface ATProtoRelayEventValidator ()

@property (nonatomic, assign, readwrite) RelayValidationMode validationMode;

@end

@implementation ATProtoRelayEventValidator {
    dispatch_queue_t _validationQueue;
}

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithValidationMode:(RelayValidationMode)mode {
    self = [super init];
    if (self) {
        _validationMode = mode;
        _validationQueue = dispatch_queue_create("com.atproto.relay.validator", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)setValidationMode:(RelayValidationMode)mode {
    dispatch_barrier_sync(_validationQueue, ^{
        _validationMode = mode;
    });
}

#pragma mark - Validation Methods

- (ATProtoRelayValidationOutcome *)validateCommitEvent:(id)event {
    if (![event isKindOfClass:[ATProtoFirehoseCommitEvent class]]) {
        return [ATProtoRelayValidationOutcome errorOutcome:@"event is not a FirehoseCommitEvent"];
    }

    ATProtoFirehoseCommitEvent *commitEvent = (ATProtoFirehoseCommitEvent *)event;

    if (commitEvent.repo.length == 0) {
        return [ATProtoRelayValidationOutcome invalidOutcome:@"commit event has no repo DID"];
    }
    if (!commitEvent.commit) {
        return [ATProtoRelayValidationOutcome invalidOutcome:@"commit event has no commit CID"];
    }

    if (!self.plcResolver) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"repository signing-key resolver is unavailable"
                                                              category:RelaySignatureFailureResolverUnavailable];
    }

    NSDictionary *didJSON = [self.plcResolver resolveDID:commitEvent.repo error:nil];
    if (!didJSON) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"repository DID could not be resolved"
                                                              category:RelaySignatureFailureDIDResolution];
    }

    ATProtoDIDDocument *document = [ATProtoDIDDocument documentWithJSON:didJSON error:nil];
    if (!document || ![document.id isEqualToString:commitEvent.repo]) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"resolved DID document does not match the repository"
                                                              category:RelaySignatureFailureDIDDocument];
    }

    NSData *publicKey = [ATProtoDIDDocumentFields strictAtprotoSigningKeyBytesFromDocument:document
                                                                                       error:nil];
    if (!publicKey) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"repository DID has no usable secp256k1 signing key"
                                                              category:RelaySignatureFailureSigningKey];
    }

    ATProtoCARReader *reader = [ATProtoCARReader readFromData:commitEvent.blocks error:nil];
    ATProtoCARBlock *commitBlock = [reader blockWithCID:commitEvent.commit];
    ATProtoCID *computedCID = commitBlock
        ? [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:commitBlock.data] codec:commitEvent.commit.codec]
        : nil;
    if (!reader || !commitBlock || ![computedCID isEqualToCID:commitEvent.commit]) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"commit block is missing or does not match its advertised CID"
                                                              category:RelaySignatureFailureCommitBlock];
    }

    ATProtoRepoCommit *commit = [ATProtoRepoCommit fromSignedBlockData:commitBlock.data error:nil];
    if (!commit || ![commit.did isEqualToString:commitEvent.repo]) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"signed commit does not match the repository"
                                                              category:RelaySignatureFailureCommitIdentity];
    }

    if (![commit verifySignatureWithPublicKey:publicKey error:nil]) {
        return [ATProtoRelayValidationOutcome invalidSignatureOutcome:@"commit signature does not verify against the repository DID key"
                                                              category:RelaySignatureFailureSignatureMismatch];
    }

    [[ATProtoRelayMetrics sharedMetrics] recordSignatureValidationSuccess];
    return [ATProtoRelayValidationOutcome validOutcome];
}

- (ATProtoRelayValidationOutcome *)validateIdentityEvent:(id)event {
    [[ATProtoRelayMetrics sharedMetrics] recordSignatureValidationSuccess];
    return [ATProtoRelayValidationOutcome validOutcome];
}

- (ATProtoRelayValidationOutcome *)validateAccountEvent:(id)event {
    return [ATProtoRelayValidationOutcome validOutcome];
}

#pragma mark - Mode-based Forwarding

- (BOOL)shouldForwardEvent:(ATProtoRelayValidationOutcome *)outcome {
    ATProtoRelayMetrics *metrics = [ATProtoRelayMetrics sharedMetrics];
    if (outcome.result == RelayValidationResultValid) {
        [metrics recordEventValidated];
    } else {
        [metrics recordEventInvalidated:outcome.errorMessage ?: @"unknown"];
    }

    switch (self.validationMode) {
        case RelayValidationModeLenient:
            return YES;

        case RelayValidationModeStrict:
            if (outcome.result == RelayValidationResultValid) {
                return YES;
            } else {
                [metrics recordEventDropped];
                return NO;
            }

        case RelayValidationModeLogOnly:
        default:
            return YES;
    }
}

@end
