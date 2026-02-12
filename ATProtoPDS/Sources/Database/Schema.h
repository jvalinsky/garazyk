#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @file Schema.h

 @abstract Database schema constants for ATProto PDS.

 @discussion This header defines the database schema version, table names,
 and CREATE TABLE statements for all PDS database tables:
 - accounts: User accounts with credentials
 - repos: Repository root CID storage
 - records: Repository records
 - blocks: CAR blocks
 - blobs: Blob metadata
 - invite_codes: Invitation codes
 - passkeys: WebAuthn credentials
 - oauth_clients: OAuth client registrations
 - jwt_signing_keys: JWT signing keys

 @see PDSDatabase
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSInteger const kPDSDatabaseSchemaVersion;

extern NSString * const kPDSAccountTableName;
extern NSString * const kPDSRepoTableName;
extern NSString * const kPDSRecordTableName;
extern NSString * const kPDSBlockTableName;
extern NSString * const kPDSBlobTableName;
extern NSString * const kPDSInviteCodeTableName;
extern NSString * const kPDSPasskeysTableName;
extern NSString * const kPDSOAuthClientsTableName;
extern NSString * const kPDSAdminTakedownTableName;
extern NSString * const kPDSLabelTableName;
extern NSString * const kPDSReservedHandleTableName;

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
extern NSString * const kPDSLabelTableCreateSQL;
extern NSString * const kPDSReservedHandleTableCreateSQL;

extern NSString * const kPDSIndexBlocksRepoDidSQL;
extern NSString * const kPDSIndexBlobsDidSQL;
extern NSString * const kPDSIndexAccountsHandleSQL;
extern NSString * const kPDSIndexInviteCodesAccountDidSQL;
extern NSString * const kPDSIndexTakedownsSubjectIdSQL;
extern NSString * const kPDSIndexPasskeysAccountDidSQL;
extern NSString * const kPDSIndexPasskeysCredentialIdSQL;
extern NSString * const kPDSIndexLabelsUriSQL;
extern NSString * const kPDSIndexLabelsSourceSQL;
extern NSString * const kPDSIndexReservedHandlesHandleSQL;

NS_ASSUME_NONNULL_END
