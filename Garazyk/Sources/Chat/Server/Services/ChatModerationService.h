#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class ChatModerationService
 @abstract Service for chat moderation tasks (metadata, context, access).
 */
@interface ChatModerationService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/*!
 @method getActorMetadata:error:
 @abstract Retrieves metadata for an actor (muted, blocked status, labels).
 */
- (nullable NSDictionary *)getActorMetadata:(NSString *)actor
                                      error:(NSError **)error;

/*!
 @method getMessageContext:error:
 @abstract Retrieves the context for a specific message (convo info, surrounding messages).
 */
- (nullable NSDictionary *)getMessageContext:(NSString *)messageId
                                       error:(NSError **)error;

/*!
 @method updateActorAccess:access:error:
 @abstract Updates access controls for an actor (mute/block).
 */
- (BOOL)updateActorAccess:(NSString *)actor
                   access:(NSDictionary *)access
                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
