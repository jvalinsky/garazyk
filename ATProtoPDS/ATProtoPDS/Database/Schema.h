#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSInteger const kPDSDatabaseSchemaVersion;

extern NSString * const kPDSAccountTableName;
extern NSString * const kPDSRepoTableName;
extern NSString * const kPDSBlockTableName;
extern NSString * const kPDSBlobTableName;

extern NSString * const kPDSAccountTableCreateSQL;
extern NSString * const kPDSRepoTableCreateSQL;
extern NSString * const kPDSRecordTableCreateSQL;
extern NSString * const kPDSBlockTableCreateSQL;
extern NSString * const kPDSBlobTableCreateSQL;

extern NSString * const kPDSIndexBlocksRepoDidSQL;
extern NSString * const kPDSIndexBlobsDidSQL;
extern NSString * const kPDSIndexAccountsHandleSQL;

NS_ASSUME_NONNULL_END
