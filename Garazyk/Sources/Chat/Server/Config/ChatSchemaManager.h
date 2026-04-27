#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ChatSchemaManager : NSObject

+ (instancetype)sharedManager;

- (NSString *)conversationsTableSchema;
- (NSString *)conversationMembersTableSchema;
- (NSString *)messagesTableSchema;
- (NSString *)messageReactionsTableSchema;
- (NSString *)eventLogTableSchema;
- (NSString *)actorMetadataTableSchema;

- (NSString *)chatSchemaSQL;

@end

NS_ASSUME_NONNULL_END
