// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
// Registers PLCServer's (PLC) WebSocket transport factory with the concrete
// Sync class it needs (PDSWebSocketNetworkAdapter), at process load time.
// This file lives in ATProtoRuntime specifically because Runtime is the one
// module in the DAG that already legitimately depends on both PLC and Sync
// (workstream 08 M4, PLC -> Sync inversion) — putting this registration in
// PLC itself would just invert the leak instead of removing it, and
// campagnola (the only binary that runs a PLCServer) already links
// ATProtoRuntime. Mirrors the RateLimiter storage-factory self-registration
// pattern from the Transport -> Storage fix.
#import "PLC/PLCServer.h"
#import "Sync/WebSocket/PDSWebSocketNetworkAdapter.h"

@interface PLCWebSocketTransportRegistration : NSObject
@end

@implementation PLCWebSocketTransportRegistration

+ (void)load {
    PLCServerSetWebSocketTransportFactory(^id<PDSWebSocketTransport> _Nullable(id<ATProtoNetworkConnection> connection) {
        return [[PDSWebSocketNetworkAdapter alloc] initWithConnection:connection];
    });
}

@end
