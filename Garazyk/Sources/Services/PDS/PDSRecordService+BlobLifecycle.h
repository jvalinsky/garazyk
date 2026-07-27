// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRecordService.h"

NS_ASSUME_NONNULL_BEGIN

@protocol PDSActorStoreTransactor;

@interface PDSRecordService (BlobLifecycle)

- (BOOL)syncBlobReferencesForRecordURI:(NSString *)recordURI
                           recordValue:(NSDictionary *)recordValue
                                forDid:(NSString *)did
                            transactor:(id<PDSActorStoreTransactor>)transactor
                                 error:(NSError **)error;

- (BOOL)syncBlobReferencesForRecordURI:(NSString *)recordURI
                              recordValue:(NSDictionary *)recordValue
                                   forDid:(NSString *)did
                                    error:(NSError **)error;

- (BOOL)removeBlobReferencesForRecordURI:(NSString *)recordURI
                                  forDid:(NSString *)did
                              transactor:(id<PDSActorStoreTransactor>)transactor
                                   error:(NSError **)error;

- (BOOL)removeBlobReferencesForRecordURI:(NSString *)recordURI
                                  forDid:(NSString *)did
                                   error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
