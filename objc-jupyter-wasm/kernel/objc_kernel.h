//
//  objc_kernel.h
//  Objective-C Jupyter Kernel Protocol Implementation
//
//  Copyright (c) 2026 Jack Valinsky
//

#import <Foundation/Foundation.h>

@interface ObjcKernel : NSObject

@property (nonatomic, assign) NSInteger executionCount;

// MARK: - Jupyter Kernel Protocol Methods

/// kernel_info_request handler
/// Returns: { "protocol_version": [5,3], "language_info": {...} }
- (NSDictionary *)kernel_info_request;

/// execute_request handler
/// Returns: { "status": "ok"|"error", "execution_count": N, "data": {...} }
/// Publishes IOPub: stream (stdout/stderr), execute_result, error
- (NSDictionary *)execute_request:(NSString *)code
                       cellId:(NSString *)cellId;

/// complete_request handler
/// Returns: { "matches": [...], "cursor_start": N, "cursor_end": N }
- (NSDictionary *)complete_request:(NSString *)code
                         cursorPos:(NSInteger)cursorPos;

/// inspect_request handler
/// Returns: { "status": "ok", "found": true, "data": {...} }
- (NSDictionary *)inspect_request:(NSString *)code
                        cursorPos:(NSInteger)cursorPos
                       detailLevel:(NSInteger)detailLevel;

/// history_request handler
/// Returns: { "history": [...], "status": "ok" }
- (NSDictionary *)history_request:(NSString *)historyAccessType
                         start:(NSInteger)start
                           stop:(NSInteger)stop
                           n:(NSInteger)n
                        pattern:(NSString *)pattern
                             raw:(BOOL)raw
                        session:(NSString *)session;

@end
