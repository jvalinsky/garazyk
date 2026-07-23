// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PDSRepositoryService_Internal.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSRepositoryService (RecordMaterializer)

- (NSArray<PDSDatabaseRecord *> *)loadAllRecordsForStore:(PDSActorStore *)store
                                                      did:(NSString *)did
                                                    error:(NSError **)error;
- (nullable NSData *)recordBlockDataForRecord:(PDSDatabaseRecord *)record;
- (CBORValue *)cidLinkValueForCID:(CID *)cid;

@end

NS_ASSUME_NONNULL_END
