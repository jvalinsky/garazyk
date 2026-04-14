/*!
 @file PDSLegacySessionRepository.h
 @abstract Adapter for legacy session data.
 @copyright Copyright (c) 2025 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSSessionRepository.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSServiceDatabases;

@interface PDSLegacySessionRepository : NSObject <PDSSessionRepository>

- (instancetype)initWithServiceDatabases:(PDSServiceDatabases *)serviceDatabases;

@end

NS_ASSUME_NONNULL_END
