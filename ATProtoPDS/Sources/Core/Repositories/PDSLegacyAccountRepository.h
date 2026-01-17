/*!
 @file PDSLegacyAccountRepository.h
 @abstract Adapter class for legacy account storage.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSAccountRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;

@interface PDSLegacyAccountRepository : NSObject <PDSAccountRepository>

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END
