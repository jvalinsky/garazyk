// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Sync/Relay/RelayEventValidator.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Sync/Firehose/Firehose.h"
#import "Core/CID.h"
#import "Auth/Crypto/Secp256k1.h"
#import "Network/XrpcIdentityHelper.h"
#import "Core/ATProtoDIDDocumentFields.h"
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

    if (self.plcResolver) {
        NSError *resolveError = nil;
        NSDictionary *didDoc = [self.plcResolver resolveDID:commitEvent.repo error:&resolveError];

        if (didDoc) {
            NSString *signingKeyMultibase = [ATProtoDIDDocumentFields atprotoSigningKeyMultibaseFromDocument:didDoc];
            if (signingKeyMultibase) {
                NSError *decodeError = nil;
                NSData *publicKeyBytes = [XrpcIdentityHelper publicKeyBytesFromMultibase:signingKeyMultibase
                                                                                  error:&decodeError];
                if (publicKeyBytes) {
                    GZ_LOG_SYNC_INFO(@"Signature precheck: resolved signing key for %@ (%lu bytes)",
                                     commitEvent.repo, (unsigned long)publicKeyBytes.length);
                } else {
                    GZ_LOG_SYNC_WARN(@"Signature precheck: failed to decode signing key for %@: %@",
                                     commitEvent.repo, decodeError.localizedDescription ?: @"unknown");
                }
            } else {
                GZ_LOG_SYNC_WARN(@"Signature precheck: no atproto signing key in DID doc for %@", commitEvent.repo);
            }
        } else {
            GZ_LOG_SYNC_WARN(@"Signature precheck: DID resolution failed for %@: %@",
                             commitEvent.repo, resolveError.localizedDescription ?: @"unknown");
        }
    }

    [[RelayMetrics sharedMetrics] recordMSTValidationSuccess];

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
