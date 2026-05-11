// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpConnectionDriver.m

 @abstract Implements connection-level orchestration for HTTP request processing.

 @discussion Drives read/parse/dispatch/write sequencing for a single connection, including lifecycle transitions and failure handling paths. Delegates parsing and routing details to specialized components.
 */

#import "Network/HttpConnectionDriver.h"

#import "Network/HttpProtocolSession.h"

@implementation HttpConnectionDriver

- (BOOL)shouldBeginReadForSession:(HttpProtocolSession *)session
                  outputQueueSize:(NSUInteger)outputQueueSize
                     headerOpened:(NSTimeInterval)headerOpened
                              now:(NSTimeInterval)now
                    headerTimeout:(NSTimeInterval)headerTimeout {
  if (session.upgradedToWebSocket) {
    return NO;
  }
  if (session.pendingDispatchCount > 0 || outputQueueSize > 0) {
    return NO;
  }
  if (now - headerOpened > headerTimeout) {
    return NO;
  }
  return YES;
}

- (BOOL)shouldResumeReadForSession:(HttpProtocolSession *)session
                   outputQueueSize:(NSUInteger)outputQueueSize {
  return outputQueueSize == 0 && [session shouldReadMoreData];
}

@end
