#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSSchemaManager : NSObject

+ (instancetype)sharedManager;

#pragma mark - Service Database Schemas

- (NSString *)serviceAccountsTableSchema;
- (NSString *)serviceInviteCodesTableSchema;
- (NSString *)serviceRefreshTokensTableSchema;
- (NSString *)serviceJWTSigningKeysTableSchema;
- (NSString *)serviceDIDCacheTableSchema;
- (NSString *)serviceRepoSequenceTableSchema;
- (NSString *)serviceSchemaSQL;

#pragma mark - Actor Store Schemas

- (NSString *)actorStoreRepoRootTableSchema;
- (NSString *)actorStoreRecordsTableSchema;
- (NSString *)actorStoreBlocksTableSchema;
- (NSString *)actorStoreBlobsTableSchema;
- (NSString *)actorStoreRotationKeysTableSchema;
- (NSString *)actorStoreSchemaSQL;

#pragma mark - Common

- (NSString *)accountsTableSchema;
- (NSString *)inviteCodesTableSchema;

@end

NS_ASSUME_NONNULL_END
