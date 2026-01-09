#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSInteger const kPDSDatabaseSchemaVersion;

extern NSString * const kPDSAccountTableName;
extern NSString * const kPDSRepoTableName;
extern NSString * const kPDSRecordTableName;
extern NSString * const kPDSBlockTableName;
extern NSString * const kPDSBlobTableName;
extern NSString * const kPDSInviteCodeTableName;
extern NSString * const kPDSPasskeysTableName;
extern NSString * const kPDSOAuthClientsTableName;

extern NSString * const kPDSAccountTableCreateSQL;
extern NSString * const kPDSRepoTableCreateSQL;
extern NSString * const kPDSRecordTableCreateSQL;
extern NSString * const kPDSBlockTableCreateSQL;
extern NSString * const kPDSBlobTableCreateSQL;
extern NSString * const kPDSInviteCodeTableCreateSQL;
extern NSString * const kPDSAdminTakedownTableCreateSQL;
extern NSString * const kPDSPasskeysTableCreateSQL;
extern NSString * const kPDSOAuthClientsTableCreateSQL;
extern NSString * const kPDSJWTSigningKeysTableCreateSQL;

extern NSString * const kPDSIndexBlocksRepoDidSQL;
extern NSString * const kPDSIndexBlobsDidSQL;
extern NSString * const kPDSIndexAccountsHandleSQL;
extern NSString * const kPDSIndexInviteCodesAccountDidSQL;
extern NSString * const kPDSIndexTakedownsSubjectIdSQL;
extern NSString * const kPDSIndexPasskeysAccountDidSQL;
extern NSString * const kPDSIndexPasskeysCredentialIdSQL;

NS_ASSUME_NONNULL_END
