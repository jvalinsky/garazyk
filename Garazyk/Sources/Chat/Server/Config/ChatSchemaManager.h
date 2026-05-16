// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * @abstract Installs and migrates the chat service database schema.
 */
@interface ChatSchemaManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)conversationsTableSchema;
- (NSString *)conversationMembersTableSchema;
- (NSString *)messagesTableSchema;
- (NSString *)messageReactionsTableSchema;
/**
 * @abstract Event log table schema.
 * @return The requested string, or nil when unavailable.
 */
- (NSString *)eventLogTableSchema;
- (NSString *)actorMetadataTableSchema;

- (NSString *)chatSchemaSQL;

@end

NS_ASSUME_NONNULL_END
