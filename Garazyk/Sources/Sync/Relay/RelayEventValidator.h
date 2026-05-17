// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file RelayEventValidator.h

 @abstract Validates firehose events (MST proofs, signatures) for ATProto Relay

 @discussion
    RelayEventValidator performs:
    - MST (Merkle Search Tree) proof validation for commits
    - Signature verification for repo operations
    - Event schema validation
    
    Validation modes (Sync v1.1):
    - Lenient: validate but forward all events regardless of result
    - Strict: drop events that fail validation  
    - LogOnly: validate strictly, log failures, forward anyway (default)

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "Sync/Relay/RelayConfiguration.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Validation result for a relay event.
 */
typedef NS_ENUM(NSInteger, RelayValidationResult) {
    /** The event passed all enabled validation checks. */
    RelayValidationResultValid,
    /** The event failed Merkle Search Tree validation. */
    RelayValidationResultInvalidMST,
    /** The event failed repository signature validation. */
    RelayValidationResultInvalidSignature,
    /** The event payload did not match the expected schema. */
    RelayValidationResultInvalidSchema,
    /** Validation could not complete because of an internal error. */
    RelayValidationResultError
};

/**
 * @abstract Captures the result and context for validating one relay event.
 */
@interface RelayValidationOutcome : NSObject

/** Validation result classification. */
@property (nonatomic, assign) RelayValidationResult result;
/** Human-readable validation failure, when validation did not pass. */
@property (nonatomic, copy, nullable) NSString *errorMessage;
/** Repository DID associated with the event, when known. */
@property (nonatomic, copy, nullable) NSString *repoDID;
/** Firehose sequence associated with the event, when known. */
@property (nonatomic, assign) int64_t sequence;

/**
 * @abstract Creates an outcome for a valid event.
 */
+ (instancetype)validOutcome;

/**
 * @abstract Creates an outcome for a rejected event.
 * @param reason Human-readable validation failure.
 */
+ (instancetype)invalidOutcome:(NSString *)reason;

/**
 * @abstract Creates an outcome for a validation error.
 * @param error Human-readable error description.
 */
+ (instancetype)errorOutcome:(NSString *)error;

@end

/**
 * @abstract Receives validation callbacks for relay events.
 */
@protocol RelayEventValidatorDelegate <NSObject>
@optional

/**
 * @abstract Called after an event is validated.
 * @param validator The validator that produced the outcome.
 * @param outcome The validation outcome.
 */
- (void)eventValidator:(id)validator didValidateEvent:(RelayValidationOutcome *)outcome;
@end

/**
 * @abstract Validates relay events before downstream forwarding.
 */
@interface RelayEventValidator : NSObject

/** Delegate notified when validation completes. */
@property (nonatomic, weak, nullable) id<RelayEventValidatorDelegate> delegate;
/** Current validation mode used to decide forwarding policy. */
@property (nonatomic, assign, readonly) RelayValidationMode validationMode;

/**
 * @abstract Creates a validator with the supplied forwarding policy.
 * @param mode Validation mode controlling strictness and forwarding behavior.
 */
- (instancetype)initWithValidationMode:(RelayValidationMode)mode NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
 * @abstract Validates a repository commit event.
 * @param event Event payload to validate.
 * @return Validation outcome for the event.
 */
- (RelayValidationOutcome *)validateCommitEvent:(id)event;

/**
 * @abstract Validates an identity event.
 * @param event Event payload to validate.
 * @return Validation outcome for the event.
 */
- (RelayValidationOutcome *)validateIdentityEvent:(id)event;

/**
 * @abstract Validates an account status event.
 * @param event Event payload to validate.
 * @return Validation outcome for the event.
 */
- (RelayValidationOutcome *)validateAccountEvent:(id)event;

/**
 * @abstract Returns whether the relay should forward an event with the supplied outcome.
 * @param outcome Validation outcome to evaluate.
 */
- (BOOL)shouldForwardEvent:(RelayValidationOutcome *)outcome;

/**
 * @abstract Changes the validator's forwarding policy.
 * @param mode Validation mode controlling strictness and forwarding behavior.
 */
- (void)setValidationMode:(RelayValidationMode)mode;

@end

NS_ASSUME_NONNULL_END
