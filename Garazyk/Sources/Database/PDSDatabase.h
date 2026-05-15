// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import "PDSBlock.h"
#import "PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/*!
 @protocol PDSDatabaseModel
 @abstract Protocol for database model objects that can initialize themselves from a dictionary row.
 */
@protocol PDSDatabaseModel <NSObject>

/*!
 @method initWithDatabaseRow:
 @abstract Initializes a new model object from a dictionary representing a database row.
 @param row A dictionary where keys are column names and values are column data.
 @return An initialized model object, or nil if initialization failed.
 */
- (nullable instancetype)initWithDatabaseRow:(NSDictionary<NSString *, id> *)row;

@end

/*!
 @header PDSDatabase.h
 @abstract Database layer for ATProto PDS persistence.
 @discussion This header defines the core database interface for persisting
 ATProto data including accounts, repositories, records, blocks, and blobs.
 Uses SQLite for local storage with transactions and migrations.
 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

extern NSString * const PDSDatabaseErrorDomain;

/*! Error codes for PDSDatabase. */
typedef NS_ENUM(NSInteger, PDSDatabaseError) {
    PDSDatabaseErrorNotOpen = 1000,
    PDSDatabaseErrorQueryFailed = 1001,
    PDSDatabaseErrorMigrationFailed = 1002,
    PDSDatabaseErrorConstraintViolation = 1003,
    PDSDatabaseErrorNotFound = 1004,
};

/*!
 @class PDSDatabase
 @abstract Manages the PDS SQLite database.
 */
@interface PDSDatabase : NSObject <PDSQueryDatabase>

/*! The URL path to the SQLite database file. */
@property (nonatomic, readonly) NSURL *databaseURL;

/*! YES if the database connection is currently open. */
@property (nonatomic, readonly) BOOL isOpen;

/*!
 @method internalSQLiteHandle
 @abstract Returns the raw sqlite3* handle.
 @discussion INTERNAL USE ONLY. Requires casting to sqlite3*.
 */
- (void *)internalSQLiteHandle;

/*!
 @method init
 @abstract Designated initializer.
 */
- (instancetype)init NS_DESIGNATED_INITIALIZER;

/*!
 @method databaseAtURL:
 
 @abstract Creates a database instance at the specified file path.
 
 @param url The file URL where the SQLite database should be located or created.
 @return An initialized PDSDatabase instance.
 */
+ (instancetype)databaseAtURL:(NSURL *)url;

/*!
 @method openWithError:
 
 @abstract Opens the database connection and runs any pending migrations.
 
 @param error On return, contains an error if the operation failed.
 @return YES if the database opened successfully, NO otherwise.
 */
- (BOOL)openWithError:(NSError **)error;

/*!
 @method close
 
 @abstract Closes the database connection.
 */
- (void)close;

/*!
 @method preparedStatementForQuery:

 @abstract Returns a cached prepared statement for the given SQL query.
 @discussion Uses an LRU cache internally. The caller must finalize the returned
 statement when done.
 */
- (nullable sqlite3_stmt *)preparedStatementForQuery:(NSString *)query;

/*!
 @method executeUnsafeRawSQL:error:
 
 @abstract Executes a raw SQL statement.
 
 @discussion DANGEROUS: Does not support parameter binding. Use only for
 internal schema setup or when the SQL string is a compile-time constant.
 
 @param sql The SQL statement to execute.
 @param error On return, contains an error if the operation failed.
 @return YES if the statement executed successfully, NO otherwise.
 */
- (BOOL)executeUnsafeRawSQL:(NSString *)sql error:(NSError **)error;

/*!
 @method executeUnsafeRawQuery:error:
 
 @abstract Executes a SQL query and returns results.
 
 @discussion DANGEROUS: Does not support parameter binding. Prefer
 executeParameterizedQuery:params:error: instead.
 
 @param sql The SQL query to execute.
 @param error On return, contains an error if the query failed.
 @return An array of dictionaries representing query results, or nil on failure.
 */
- (NSArray<NSDictionary *> *)executeUnsafeRawQuery:(NSString *)sql error:(NSError **)error;

/*!
 @method executeParameterizedQuery:params:error:
 
 @abstract Executes a SQL query with parameterized values.
 
 @discussion This is the RECOMMENDED method for executing queries with user-provided
 values. It uses SQLite parameter binding to prevent SQL injection attacks.
 
 @param sql The SQL query with ? placeholders for parameters.
 @param params An array of parameter values to bind to the query.
 @param error On return, contains an error if the query failed.
 @return An array of dictionaries representing query results, or nil on failure.
 */
- (NSArray<NSDictionary *> *)executeParameterizedQuery:(NSString *)sql
                                                params:(NSArray *)params
                                                 error:(NSError **)error;

/*!
 @method executeParameterizedQuery:params:modelClass:error:
 @abstract Executes a query and maps results to model objects.
 @param sql The SQL query to execute.
 @param params Array of parameters for placeholders.
 @param modelClass The class of the model to instantiate (must implement PDSDatabaseModel).
 @param error On return, contains an error if the query failed.
 @return An array of model objects, or nil on failure.
 */
- (nullable NSArray *)executeParameterizedQuery:(NSString *)sql
                                         params:(NSArray *)params
                                     modelClass:(Class<PDSDatabaseModel>)modelClass
                                          error:(NSError **)error;

/*!
 @method executeParameterizedUpdate:params:error:
 
 @abstract Executes a parameterized SQL statement (INSERT, UPDATE, DELETE).
 
 @param sql The SQL statement with ? placeholders for parameters.
 @param params An array of parameter values to bind to the statement.
 @param error On return, contains an error if the statement failed.
 @return YES if the statement executed successfully, NO otherwise.
 */
- (BOOL)executeParameterizedUpdate:(NSString *)sql
                            params:(NSArray *)params
                             error:(NSError **)error;

/*!
 @method parameterPlaceholdersForCount:
 @abstract Returns a string of ? placeholders for use in an IN clause.
 @param count Number of placeholders needed.
 @return A string like "?, ?, ?" or empty if count is 0.
 */
- (NSString *)parameterPlaceholdersForCount:(NSUInteger)count;

@end

/*!
 @class PDSDatabaseAccount
 
 @abstract Represents a PDS account record in the database.
 
 @discussion This class models account data stored in the database, including
 identity information (DID, handle, email), credentials (password hash, JWT tokens),
 and metadata (creation time, invite status).
 
 @see PDSDatabase (Accounts)
 */
@interface PDSDatabaseAccount : NSObject <PDSDatabaseModel>

/*! The decentralized identifier (DID) for this account. */
@property (nonatomic, copy) NSString *did;

/*! The handle (username) for this account. */
@property (nonatomic, copy) NSString *handle;

/*! Optional email address for password recovery and notifications. */
@property (nonatomic, copy, nullable) NSString *email;

/*! Bcrypt hash of the account password. */
@property (nonatomic, copy, nullable) NSData *passwordHash;

/*! Salt used for password hashing. */
@property (nonatomic, copy, nullable) NSData *passwordSalt;

/*! JWT access token for API authentication. */
@property (nonatomic, copy, nullable) NSData *accessJwt;

/*! JWT refresh token for obtaining new access tokens. */
@property (nonatomic, copy, nullable) NSData *refreshJwt;

/*! Account status (e.g., "active", "deactivated"). */
@property (nonatomic, copy) NSString *status;

/*! Unix timestamp when the account was deactivated. */
@property (nonatomic, assign) NSTimeInterval deactivatedAt;

/*! Unix timestamp when the account was created. */
@property (nonatomic, assign) NSTimeInterval createdAt;

/*! Unix timestamp when the account was last updated. */
@property (nonatomic, assign) NSTimeInterval updatedAt;

/*! Whether invite codes are enabled for this account. */
@property (nonatomic, assign) BOOL inviteEnabled;

/*! Whether 2FA (TOTP/Passkey) is enabled. */
@property (nonatomic, assign) BOOL tfaEnabled;

/*! Whether WebAuthn is enabled for this account. */
@property (nonatomic, assign) BOOL webauthnEnabled;

/*! Encrypted TOTP secret or other 2FA secret data. */
@property (nonatomic, copy, nullable) NSData *tfaSecret;

/*! JSON array of hashed recovery codes. */
@property (nonatomic, copy, nullable) NSData *recoveryCodes;

/*! Age assurance level. */
@property (nonatomic, copy, nullable) NSString *ageAssurance;

/*! Timestamp when age was verified. */
@property (nonatomic, copy, nullable) NSString *ageVerifiedAt;

@end

/*!
 @class PDSDatabaseRepo
 
 @abstract Represents a repository in the database.
 
 @discussion A repository contains a user's collection of records and blocks.
 Each repository is identified by its owner's DID and has a current root CID
 representing the state of the Merkle Search Tree.
 
 @see PDSDatabase (Repos)
 */
@interface PDSDatabaseRepo : NSObject <PDSDatabaseModel>

/*! The DID of the repository owner. */
@property (nonatomic, copy) NSString *ownerDid;

/*! The current root CID of the repository's Merkle Search Tree. */
@property (nonatomic, copy) NSData *rootCid;

/*! Optional serialized collection index data. */
@property (nonatomic, copy, nullable) NSData *collectionData;

/*! Date when the repository was created. */
@property (nonatomic, strong) NSDate *createdAt;

/*! Date when the repository was last updated. */
@property (nonatomic, strong) NSDate *updatedAt;

@end

/*!
 @class PDSDatabaseRecord
 
 @abstract Represents a single record in a repository.
 
 @discussion Records are the fundamental data units in ATProto repositories.
 Each record is identified by a URI (repo DID + collection + rkey) and has
 an associated CID for content-addressable retrieval.
 
 @see PDSDatabase (Records)
 */
@interface PDSDatabaseRecord : NSObject <PDSDatabaseModel>

/*! The AT-URI identifying this record (e.g., at://did:plc:z.../app.bsky.actor.profile/self). */
@property (nonatomic, copy) NSString *uri;

/*! The DID of the repository that contains this record. */
@property (nonatomic, copy) NSString *did;

/*! The collection namespace for this record (e.g., app.bsky.actor.profile). */
@property (nonatomic, copy) NSString *collection;

/*! The record key within the collection. */
@property (nonatomic, copy) NSString *rkey;

/*! The CID of the record content. */
@property (nonatomic, copy) NSString *cid;

/*! Date when the record was created. */
@property (nonatomic, strong) NSDate *createdAt;

/*! The raw value of the record (JSON string). */
@property (nonatomic, copy, nullable) NSString *value;

/*! Revision TID when this record was last written. */
@property (nonatomic, copy, nullable) NSString *rev;

/*! The subject DID for relationship records (e.g. follow target). */
@property (nonatomic, copy, nullable) NSString *subjectDid;

/*! Date when the record was indexed by the PDS. */
@property (nonatomic, strong, nullable) NSDate *indexedAt;

@end

/*!
 @class PDSDatabaseBlob
 
 @abstract Represents a blob reference stored in the database.
 
 @discussion Blobs are large binary data attachments stored separately from
 repository blocks. This class tracks blob metadata for retrieval and quota
 management.
 
 @see PDSDatabase (Blobs)
 */
@interface PDSDatabaseBlob : NSObject <PDSDatabaseModel>

/*! The CID of the blob. */
@property (nonatomic, copy) NSData *cid;

/*! The DID of the account that uploaded this blob. */
@property (nonatomic, copy) NSString *did;

/*! The MIME type of the blob content. */
@property (nonatomic, copy, nullable) NSString *mimeType;

/*! The size of the blob in bytes. */
@property (nonatomic, assign) NSInteger size;

/*! Date when the blob was uploaded. */
@property (nonatomic, strong) NSDate *createdAt;

@end


NS_ASSUME_NONNULL_END

// ── Category imports ─────────────────────────────────────────────────
// Importing here (after @interface) preserves backward compatibility:
// consumers who #import "PDSDatabase.h" still get all category methods.
// The category headers #import this file, but #import's include guards
// prevent recursion.
#import "PDSDatabase+Accounts.h"
#import "PDSDatabase+Transactions.h"
#import "PDSDatabase+Repos.h"
#import "PDSDatabase+Blobs.h"
#import "PDSDatabase+Records.h"
#import "PDSDatabase+Moderation.h"
#import "PDSDatabase+AdminAudit.h"
#import "PDSDatabase+Reports.h"
#import "PDSDatabase+AdminConfig.h"
#import "PDSDatabase+Sessions.h"
#import "PDSDatabase+VideoJobs.h"
#import "PDSDatabase+WebAuthn.h"
#import "PDSDatabase+Blocks.h"
#import "PDSDatabase+OAuthClients.h"

