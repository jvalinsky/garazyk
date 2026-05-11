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

typedef NS_ENUM(NSInteger, RelayValidationResult) {
    RelayValidationResultValid,
    RelayValidationResultInvalidMST,
    RelayValidationResultInvalidSignature,
    RelayValidationResultInvalidSchema,
    RelayValidationResultError
};

@interface RelayValidationOutcome : NSObject

@property (nonatomic, assign) RelayValidationResult result;
@property (nonatomic, copy, nullable) NSString *errorMessage;
@property (nonatomic, copy, nullable) NSString *repoDID;
@property (nonatomic, assign) int64_t sequence;

+ (instancetype)validOutcome;
+ (instancetype)invalidOutcome:(NSString *)reason;
+ (instancetype)errorOutcome:(NSString *)error;

@end

@protocol RelayEventValidatorDelegate <NSObject>
@optional
- (void)eventValidator:(id)validator didValidateEvent:(RelayValidationOutcome *)outcome;
@end

@interface RelayEventValidator : NSObject

@property (nonatomic, weak, nullable) id<RelayEventValidatorDelegate> delegate;
@property (nonatomic, assign, readonly) RelayValidationMode validationMode;

- (instancetype)initWithValidationMode:(RelayValidationMode)mode NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (RelayValidationOutcome *)validateCommitEvent:(id)event;
- (RelayValidationOutcome *)validateIdentityEvent:(id)event;
- (RelayValidationOutcome *)validateAccountEvent:(id)event;

- (BOOL)shouldForwardEvent:(RelayValidationOutcome *)outcome;

- (void)setValidationMode:(RelayValidationMode)mode;

@end

NS_ASSUME_NONNULL_END