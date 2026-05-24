// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>
#import <sqlite3.h>

@protocol ATProtoConnectionManager;

NS_ASSUME_NONNULL_BEGIN

typedef NSError * _Nonnull (^ATProtoDatabaseQueryRunnerErrorFactory)(sqlite3 * _Nullable db,
                                                                     NSInteger code,
                                                                     NSString *fallback);

@interface ATProtoDatabaseQueryRunner : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                              errorDomain:(NSString *)errorDomain;
- (instancetype)initWithConnectionManager:(id<ATProtoConnectionManager>)connectionManager
                             errorFactory:(ATProtoDatabaseQueryRunnerErrorFactory)errorFactory NS_DESIGNATED_INITIALIZER;

- (nullable NSArray<NSDictionary<NSString *, id> *> *)executeQuery:(NSString *)sql
                                                            params:(nullable NSArray *)params
                                                             error:(NSError **)error;

- (BOOL)executeUpdate:(NSString *)sql
               params:(nullable NSArray *)params
           connection:(sqlite3 *)db
                error:(NSError **)error;

- (BOOL)performWriteTransaction:(BOOL (^)(sqlite3 *db, NSError **error))block
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
