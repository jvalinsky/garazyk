// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file HttpProtocolSession.m

 @abstract Implements HTTP protocol session state management and progression.

 @discussion Maintains protocol-session context as requests are parsed and processed, coordinating transitions between parser outputs and dispatch inputs. Does not implement route business semantics.
 */

#import "Network/HttpProtocolSession.h"
#import "Debug/PDSLogger.h"

@interface HttpProtocolSession ()
@property(nonatomic, strong, readwrite) Http1Parser *parser;
@property(nonatomic, strong, readwrite) Http1PipelinePolicy *pipelinePolicy;
@property(nonatomic, strong) NSMutableArray<HttpRequest *> *pendingRequests;
@property(nonatomic, strong, nullable) HttpRequest *upgradeRequest;
@end

@implementation HttpProtocolSession

- (instancetype)init {
  self = [super init];
  if (self) {
    _parser = [[Http1Parser alloc] init];
    _pipelinePolicy = [[Http1PipelinePolicy alloc] init];
    _pendingRequests = [NSMutableArray array];
    _upgradedToWebSocket = NO;
  }
  return self;
}

- (NSArray<NSNumber *> *)feedData:(NSData *)data {
  if (self.upgradedToWebSocket) {
    return @[];
  }

  NSMutableArray<NSNumber *> *events = [NSMutableArray array];
  BOOL completeOrError = [self.parser feedData:data];

  if (!completeOrError) {
    PDS_LOG_DEBUG_C(PDSLogComponentHTTP, @"HttpProtocolSession: Parser needs more data (%lu bytes fed)", (unsigned long)data.length);
    return events;
  }

  Http1ParserError *parseError = [self.parser parseError];
  if (parseError) {
    [events addObject:@(HttpSessionEventError)];
    return events;
  }

  HttpRequest *request = [self.parser completedRequest];
  if (!request) {
    return events;
  }

  // Check for upgrade header
  if ([request headerForKey:@"upgrade"] != nil) {
    self.upgradeRequest = request;
    [events addObject:@(HttpSessionEventUpgrade)];
    // Driver will handle the actual upgrade logic
  }

  Http1PipelineAction action = [self.pipelinePolicy requestParsed];
  if (action == Http1PipelineActionDispatch || action == Http1PipelineActionQueue) {
    [self.pendingRequests addObject:request];
    [events addObject:@(HttpSessionEventRequestReady)];

    NSData *unconsumed = [self.parser unconsumedData];
    [self resetForNextRequest];

    // Recurse internally for pipelined data
    if (unconsumed.length > 0) {
      [events addObjectsFromArray:[self feedData:unconsumed]];
    }
  }

  return events;
}

- (nullable HttpRequest *)nextRequestToDispatch {
  if (self.pendingRequests.count > 0 && [self shouldReadMoreData]) {
    HttpRequest *request = self.pendingRequests[0];
    [self.pendingRequests removeObjectAtIndex:0];
    [self.pipelinePolicy requestDispatched];
    return request;
  }
  return nil;
}

- (void)queueResponse:(HttpResponse *)response {
  (void)response;
  [self responseDidFinishSending];
}

- (void)responseDidFinishSending {
  // This just signals that a response was finished for the policy.
  // The driver still manages the actual network output queue (for now).
  [self.pipelinePolicy responseCompleted];
}

- (void)resetForNextRequest {
  [self.parser reset];
}

- (nullable HttpRequest *)currentUpgradeRequest {
  return self.upgradeRequest;
}

- (nullable Http1ParserError *)currentParseError {
  return self.parser.parseError;
}

- (void)setRemoteAddressIfNeeded:(nullable NSString *)remoteAddress {
  if (self.parser.remoteAddress.length == 0 && remoteAddress.length > 0) {
    self.parser.remoteAddress = remoteAddress;
  }
}

- (BOOL)shouldReadMoreData {
  return [self.pipelinePolicy shouldReadMoreData];
}

- (NSUInteger)pendingDispatchCount {
  return self.pipelinePolicy.pendingDispatchCount;
}

@end
