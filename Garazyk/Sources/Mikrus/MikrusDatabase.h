// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file MikrusDatabase.h

 @abstract SQLite-backed link index for Microcosm Mikrus-style queries.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MikrusSourceSpec;

extern NSString * const MikrusDatabaseErrorDomain;

@interface MikrusDatabase : NSObject

- (nullable instancetype)initWithPath:(NSString *)path error:(NSError **)error;
- (BOOL)runMigrations:(NSError **)error;
- (void)close;

- (BOOL)indexRecord:(NSDictionary *)record
                did:(NSString *)did
         collection:(NSString *)collection
               rkey:(NSString *)rkey
                cid:(nullable NSString *)cid
                seq:(int64_t)seq
              error:(NSError **)error;

- (BOOL)deleteRecordForDID:(NSString *)did
                collection:(NSString *)collection
                      rkey:(NSString *)rkey
                     error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)backlinkRecordsForSubject:(NSString *)subject
                                                         source:(MikrusSourceSpec *)source
                                                     didFilters:(NSArray<NSString *> *)didFilters
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                     nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                          total:(NSInteger * _Nullable)total
                                                          error:(NSError **)error;

- (nullable NSArray<NSString *> *)backlinkDIDsForSubject:(NSString *)subject
                                                  source:(MikrusSourceSpec *)source
                                                   limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                              nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                   total:(NSInteger * _Nullable)total
                                                   error:(NSError **)error;

- (NSInteger)backlinksCountForSubject:(NSString *)subject
                                source:(MikrusSourceSpec *)source
                                 error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)manyToManyItemsForSubject:(NSString *)subject
                                                         source:(MikrusSourceSpec *)source
                                                    pathToOther:(NSString *)pathToOther
                                                     linkDIDs:(NSArray<NSString *> *)linkDIDs
                                                  otherSubjects:(NSArray<NSString *> *)otherSubjects
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                     nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                          error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)manyToManyCountsForSubject:(NSString *)subject
                                                          source:(MikrusSourceSpec *)source
                                                     pathToOther:(NSString *)pathToOther
                                                            dids:(NSArray<NSString *> *)dids
                                                   otherSubjects:(NSArray<NSString *> *)otherSubjects
                                                           limit:(NSInteger)limit
                                                          cursor:(nullable NSString *)cursor
                                                      nextCursor:(NSString * _Nullable * _Nullable)nextCursor
                                                           error:(NSError **)error;

- (nullable NSDictionary *)recordByURI:(NSString *)uri
                                   cid:(nullable NSString *)cid
                                 error:(NSError **)error;

- (BOOL)saveHandle:(NSString *)handle did:(NSString *)did error:(NSError **)error;
- (nullable NSString *)resolveHandleToDID:(NSString *)handle error:(NSError **)error;
- (nullable NSString *)resolveDIDToHandle:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
