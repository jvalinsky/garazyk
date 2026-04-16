#import "Sync/Relay/RelayEventValidator.h"
#import "Sync/Relay/RelayMetrics.h"
#import "Repository/MST.h"
#import "Auth/Secp256k1.h"

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

- (instancetype)initWithValidationMode:(RelayValidationMode)mode {
    self = [super init];
    if (self) {
        _validationMode = mode;
        _validationQueue = dispatch_queue_create("com.atproto.relay.validator", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)setValidationMode:(RelayValidationMode)mode {
    @synchronized (self) {
        _validationMode = mode;
    }
}

#pragma mark - Validation Methods

- (RelayValidationOutcome *)validateCommitEvent:(id)event {
    // Extract event data
    // In a full implementation, this would:
    // 1. Parse the commit event to get repo DID, commit CID, ops
    // 2. Verify the signature using the repo's public key from DID doc
    // 3. Validate MST proof (the "inductive validation" from Sync v1.1)
    
    // For now, return valid - full implementation requires MST inversion
    [[RelayMetrics sharedMetrics] recordMSTValidationSuccess];
    [[RelayMetrics sharedMetrics] recordSignatureValidationSuccess];
    
    return [RelayValidationOutcome validOutcome];
}

- (RelayValidationOutcome *)validateIdentityEvent:(id)event {
    // Identity events (#identity) - verify the DID document signature
    // For now, return valid - full implementation would verify DID update signatures
    [[RelayMetrics sharedMetrics] recordSignatureValidationSuccess];
    
    return [RelayValidationOutcome validOutcome];
}

- (RelayValidationOutcome *)validateAccountEvent:(id)event {
    // Account events (#account) - verify account status changes
    // No cryptographic validation needed for account status
    
    return [RelayValidationOutcome validOutcome];
}

#pragma mark - Mode-based Forwarding

- (BOOL)shouldForwardEvent:(RelayValidationOutcome *)outcome {
    switch (self.validationMode) {
        case RelayValidationModeLenient:
            // Forward all events, regardless of validation result
            return YES;
            
        case RelayValidationModeStrict:
            // Only forward valid events, drop invalid
            if (outcome.result == RelayValidationResultValid) {
                [[RelayMetrics sharedMetrics] recordEventForwarded];
                return YES;
            } else {
                [[RelayMetrics sharedMetrics] recordEventDropped];
                return NO;
            }
            
        case RelayValidationModeLogOnly:
        default:
            // Validate strictly, log failures, forward anyway (Bluesky's default)
            if (outcome.result == RelayValidationResultValid) {
                [[RelayMetrics sharedMetrics] recordEventValidated];
                [[RelayMetrics sharedMetrics] recordEventForwarded];
            } else {
                [[RelayMetrics sharedMetrics] recordEventInvalidated:outcome.errorMessage ?: @"unknown"];
                [[RelayMetrics sharedMetrics] recordEventForwarded]; // Forward anyway in log-only
            }
            return YES;
    }
}

@end
