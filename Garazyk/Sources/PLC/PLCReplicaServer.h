// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PLCReplicaServer.h

 @abstract Read-only PLC server for replica mode.

 @discussion
    PLCReplicaServer is a variant of PLCServer that operates in read-only mode.
    It serves DID resolution and audit log queries from a local replica store,
    but does not accept operation submissions (POST /:did).
    
    This is suitable for deploying a PLC directory read replica that syncs
    from the primary plc.directory instance.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCServer.h"

NS_ASSUME_NONNULL_BEGIN

@interface PLCReplicaServer : PLCServer

@property (nonatomic, assign, readonly, getter=isReadOnlyMode) BOOL readOnlyMode;

- (instancetype)initWithStore:(id<PLCStore>)store
                      auditor:(PLCAuditor *)auditor
                         port:(NSUInteger)port
                 readOnlyMode:(BOOL)readOnly NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithStore:(id<PLCStore>)store
                      auditor:(PLCAuditor *)auditor
                         port:(NSUInteger)port NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END