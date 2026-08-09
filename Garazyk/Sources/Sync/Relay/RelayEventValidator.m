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

@implementation RelayValidationOutcome

+ (instancetype)validOutcome {
    RelayValidationOutcome *outcome = [[RelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultValid;
    return outcome;
}

+ (instancetype)invalidOutcome:(NSString *)reason {
    RelayValidationOutcome *outcome = [[RelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultInvalidMST;
    outcome.errorMessage = reason;
    return outcome;
}

+ (instancetype)errorOutcome:(NSString *)error {
    RelayValidationOutcome *outcome = [[RelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultError;
    outcome.errorMessage = error;
    return outcome;
}

+ (instancetype)invalidSignatureOutcome:(NSString *)reason {
    [[RelayMetrics sharedMetrics] recordSignatureValidationFailure];
    RelayValidationOutcome *outcome = [[RelayValidationOutcome alloc] init];
    outcome.result = RelayValidationResultInvalidSignature;
    outcome.errorMessage = reason;
    return outcome;
}

@end

@interface RelayEventValidator ()

@property (nonatomic, assign, readwrite) RelayValidationMode validationMode;

@end

@implementation RelayEventValidator {
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

- (RelayValidationOutcome *)validateCommitEvent:(id)event {
    if (![event isKindOfClass:[FirehoseCommitEvent class]]) {
        return [RelayValidationOutcome errorOutcome:@"event is not a FirehoseCommitEvent"];
    }

    FirehoseCommitEvent *commitEvent = (FirehoseCommitEvent *)event;

    if (commitEvent.repo.length == 0) {
        return [RelayValidationOutcome invalidOutcome:@"commit event has no repo DID"];
    }
    if (!commitEvent.commit) {
        return [RelayValidationOutcome invalidOutcome:@"commit event has no commit CID"];
    }

    if (!self.plcResolver) {
        return [RelayValidationOutcome invalidSignatureOutcome:@"repository signing-key resolver is unavailable"];
    }

    NSError *resolveError = nil;
    NSDictionary *didJSON = [self.plcResolver resolveDID:commitEvent.repo error:&resolveError];
    if (!didJSON) {
        GZ_LOG_SYNC_WARN(@"Relay commit signature validation: DID resolution failed for %@: %@",
                         commitEvent.repo, resolveError.localizedDescription ?: @"unknown");
        return [RelayValidationOutcome invalidSignatureOutcome:@"repository DID could not be resolved"];
    }

    NSError *documentError = nil;
    ATProtoDIDDocument *document = [ATProtoDIDDocument documentWithJSON:didJSON error:&documentError];
    if (!document || ![document.id isEqualToString:commitEvent.repo]) {
        return [RelayValidationOutcome invalidSignatureOutcome:@"resolved DID document does not match the repository"];
    }

    NSError *keyError = nil;
    NSData *publicKey = [ATProtoDIDDocumentFields strictAtprotoSigningKeyBytesFromDocument:document
                                                                                       error:&keyError];
    if (!publicKey) {
        GZ_LOG_SYNC_WARN(@"Relay commit signature validation: no usable signing key for %@: %@",
                         commitEvent.repo, keyError.localizedDescription ?: @"unknown");
        return [RelayValidationOutcome invalidSignatureOutcome:@"repository DID has no usable secp256k1 signing key"];
    }

    NSError *carError = nil;
    ATProtoCARReader *reader = [ATProtoCARReader readFromData:commitEvent.blocks error:&carError];
    ATProtoCARBlock *commitBlock = [reader blockWithCID:commitEvent.commit];
    ATProtoCID *computedCID = commitBlock
        ? [ATProtoCID cidWithDigest:[ATProtoCID sha256Digest:commitBlock.data] codec:commitEvent.commit.codec]
        : nil;
    if (!reader || !commitBlock || ![computedCID isEqualToCID:commitEvent.commit]) {
        GZ_LOG_SYNC_WARN(@"Relay commit signature validation: missing or invalid commit block for %@: %@",
                         commitEvent.repo, carError.localizedDescription ?: @"unknown");
        return [RelayValidationOutcome invalidSignatureOutcome:@"commit block is missing or does not match its advertised CID"];
    }

    NSError *commitError = nil;
    ATProtoRepoCommit *commit = [ATProtoRepoCommit fromSignedBlockData:commitBlock.data error:&commitError];
    if (!commit || ![commit.did isEqualToString:commitEvent.repo]) {
        return [RelayValidationOutcome invalidSignatureOutcome:@"signed commit does not match the repository"];
    }

    NSError *signatureError = nil;
    if (![commit verifySignatureWithPublicKey:publicKey error:&signatureError]) {
        GZ_LOG_SYNC_WARN(@"Relay commit signature validation: signature verification failed for %@: %@",
                         commitEvent.repo, signatureError.localizedDescription ?: @"unknown");
        return [RelayValidationOutcome invalidSignatureOutcome:@"commit signature does not verify against the repository DID key"];
    }

    [[RelayMetrics sharedMetrics] recordSignatureValidationSuccess];
    return [RelayValidationOutcome validOutcome];
}

- (RelayValidationOutcome *)validateIdentityEvent:(id)event {
    [[RelayMetrics sharedMetrics] recordSignatureValidationSuccess];
    return [RelayValidationOutcome validOutcome];
}

- (RelayValidationOutcome *)validateAccountEvent:(id)event {
    return [RelayValidationOutcome validOutcome];
}

#pragma mark - Mode-based Forwarding

- (BOOL)shouldForwardEvent:(RelayValidationOutcome *)outcome {
    switch (self.validationMode) {
        case RelayValidationModeLenient:
            return YES;

        case RelayValidationModeStrict:
            if (outcome.result == RelayValidationResultValid) {
                [[RelayMetrics sharedMetrics] recordEventForwarded];
                return YES;
            } else {
                [[RelayMetrics sharedMetrics] recordEventDropped];
                return NO;
            }

        case RelayValidationModeLogOnly:
        default:
            if (outcome.result == RelayValidationResultValid) {
                [[RelayMetrics sharedMetrics] recordEventValidated];
                [[RelayMetrics sharedMetrics] recordEventForwarded];
            } else {
                [[RelayMetrics sharedMetrics] recordEventInvalidated:outcome.errorMessage ?: @"unknown"];
                [[RelayMetrics sharedMetrics] recordEventForwarded];
            }
            return YES;
    }
}

@end
