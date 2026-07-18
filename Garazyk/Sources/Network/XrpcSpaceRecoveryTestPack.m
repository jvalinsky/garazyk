// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcSpaceRecoveryTestPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Services/PDS/PDSSpaceReconciler.h"
#import "Services/PDS/PDSSpaceStore.h"

#import <stdint.h>

static NSString *const XrpcSpaceRecoveryTestNSID = @"tools.garazyk.test.spaceRecovery";

static BOOL XrpcSpaceRecoveryTestEnabledValue(NSString *value) {
  return [value isKindOfClass:[NSString class]] &&
      ([value caseInsensitiveCompare:@"true"] == NSOrderedSame || [value isEqualToString:@"1"]);
}

static NSString *const XrpcSpaceRecoveryTestControlTokenEnvironment =
    @"PDS_SPACE_RECOVERY_TEST_CONTROL_TOKEN";

static BOOL XrpcSpaceRecoveryTestIsProductionEnvironment(NSDictionary<NSString *, NSString *> *environment) {
  return [[environment[@"PDS_ENV"] lowercaseString] isEqualToString:@"production"] ||
      XrpcSpaceRecoveryTestEnabledValue(environment[@"PDS_REQUIRE_ISSUER"]);
}

static BOOL XrpcSpaceRecoveryTestTokensMatch(NSString *candidate, NSString *expected) {
  NSData *candidateData = [candidate dataUsingEncoding:NSUTF8StringEncoding];
  NSData *expectedData = [expected dataUsingEncoding:NSUTF8StringEncoding];
  if (candidateData.length != expectedData.length || expectedData.length == 0) return NO;
  const uint8_t *candidateBytes = candidateData.bytes;
  const uint8_t *expectedBytes = expectedData.bytes;
  uint8_t difference = 0;
  for (NSUInteger index = 0; index < expectedData.length; index++) {
    difference |= candidateBytes[index] ^ expectedBytes[index];
  }
  return difference == 0;
}

static BOOL XrpcSpaceRecoveryTestIsLoopbackAddress(NSString *address) {
  NSString *normalized = [address lowercaseString];
  return [normalized hasPrefix:@"127."] || [normalized isEqualToString:@"::1"] ||
      [normalized isEqualToString:@"localhost"];
}

static void XrpcSpaceRecoveryTestError(HttpResponse *response, NSInteger status, NSString *message) {
  response.statusCode = status;
  [response setJsonBody:@{ @"error" : @"RecoveryTestControlError", @"message" : message ?: @"Invalid request" }];
}

@implementation XrpcSpaceRecoveryTestPack

+ (BOOL)isEnabledForEnvironment:(NSDictionary<NSString *, NSString *> *)environment {
  if (![environment isKindOfClass:[NSDictionary class]]) return NO;
  NSString *token = environment[XrpcSpaceRecoveryTestControlTokenEnvironment];
  return !XrpcSpaceRecoveryTestIsProductionEnvironment(environment) &&
      XrpcSpaceRecoveryTestEnabledValue(environment[@"PDS_RUNNING_TESTS"]) &&
      XrpcSpaceRecoveryTestEnabledValue(environment[@"PDS_SPACE_RECOVERY_TEST_CONTROL"]) &&
      [token isKindOfClass:[NSString class]] && token.length >= 32;
}

+ (BOOL)isAuthorizedRequest:(HttpRequest *)request
                environment:(NSDictionary<NSString *, NSString *> *)environment {
  NSString *token = environment[XrpcSpaceRecoveryTestControlTokenEnvironment];
  NSString *authorization = [request headerForKey:@"Authorization"];
  if (![token isKindOfClass:[NSString class]] || token.length < 32 ||
      ![authorization hasPrefix:@"Bearer "] ||
      !XrpcSpaceRecoveryTestIsLoopbackAddress(request.remoteAddress)) {
    return NO;
  }
  return XrpcSpaceRecoveryTestTokensMatch([authorization substringFromIndex:7], token);
}

+ (BOOL)isFixtureSpaceURI:(NSString *)space {
  if (![space isKindOfClass:[NSString class]]) return NO;
  NSRange marker = [space rangeOfString:@"/space/com.garazyk.permissioned/recovery-"];
  return [space hasPrefix:@"at://did:"] && marker.location != NSNotFound &&
      marker.location + marker.length < space.length;
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  PDSSpaceStore *spaceStore = services.spaceStore;
  PDSSpaceReconciler *reconciler = services.spaceReconciler;
  if (!spaceStore || !reconciler) return;
  NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;

  [dispatcher registerMethod:XrpcSpaceRecoveryTestNSID handler:^(HttpRequest *request, HttpResponse *response) {
    if (![self isAuthorizedRequest:request environment:environment]) {
      XrpcSpaceRecoveryTestError(response, 401, @"Recovery test control requires local bearer authorization");
      return;
    }
    if (request.method != HttpMethodPOST || ![request.jsonBody isKindOfClass:[NSDictionary class]]) {
      XrpcSpaceRecoveryTestError(response, 400, @"Expected a JSON POST body");
      return;
    }
    NSDictionary *body = request.jsonBody;
    NSString *operation = body[@"operation"];
    NSString *space = body[@"space"];
    NSString *author = body[@"repo"];
    if (![operation isKindOfClass:[NSString class]] || ![space isKindOfClass:[NSString class]] ||
        ![author isKindOfClass:[NSString class]] || operation.length == 0 ||
        space.length == 0 || author.length == 0) {
      XrpcSpaceRecoveryTestError(response, 400, @"operation, space, and repo are required");
      return;
    }
    if (![self isFixtureSpaceURI:space]) {
      XrpcSpaceRecoveryTestError(response, 403, @"Recovery test control is limited to recovery fixture spaces");
      return;
    }

    if ([operation isEqualToString:@"seed"]) {
      NSString *rkey = [body[@"rkey"] isKindOfClass:[NSString class]] ? body[@"rkey"] : @"recovery-seed";
      if (![rkey hasPrefix:@"recovery-"]) {
        XrpcSpaceRecoveryTestError(response, 403, @"Recovery test control seed must use a fixture record key");
        return;
      }
      NSDictionary *value = @{ @"$type" : @"app.bsky.feed.post", @"text" : @"recovery control seed" };
      NSData *valueData = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
      PDSSpaceWrite *write = [PDSSpaceWrite writeWithAction:PDSSpaceWriteActionCreate
                                                  collection:@"app.bsky.feed.post"
                                                        rkey:rkey
                                                         cid:@"bafyrecoverytestcontrolseed"
                                                       value:valueData];
      NSError *error = nil;
      NSDictionary *commit = [spaceStore applyWrites:@[write]
                                             toSpace:space
                                              author:author
                                                 rev:@"recovery-test-seed"
                                               error:&error];
      if (!commit) {
        XrpcSpaceRecoveryTestError(response, 409, error.localizedDescription ?: @"Unable to seed replica state");
        return;
      }
      [response setJsonBody:@{ @"revision" : commit[@"rev"] ?: @"", @"seeded" : @YES }];
      return;
    }

    if ([operation isEqualToString:@"prune"]) {
      NSNumber *keepValue = [body[@"keepingRevisions"] isKindOfClass:[NSNumber class]] ? body[@"keepingRevisions"] : @0;
      NSError *error = nil;
      if (![spaceStore pruneOplogForSpace:space author:author keepingRevisions:keepValue.unsignedIntegerValue error:&error]) {
        XrpcSpaceRecoveryTestError(response, 409, error.localizedDescription ?: @"Unable to prune oplog");
        return;
      }
      [response setJsonBody:@{ @"keepingRevisions" : keepValue, @"pruned" : @YES }];
      return;
    }

    if (![operation isEqualToString:@"reconcile"]) {
      XrpcSpaceRecoveryTestError(response, 400, @"operation must be seed, prune, or reconcile");
      return;
    }

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block NSDictionary<NSString *, id> *result = nil;
    [reconciler reconcileOnceForSpace:space author:author completion:^(NSDictionary<NSString *, id> *recoveryResult) {
      result = recoveryResult;
      dispatch_semaphore_signal(done);
    }];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC)) != 0) {
      XrpcSpaceRecoveryTestError(response, 504, @"Reconciliation did not finish within 30 seconds");
      return;
    }
    NSString *selector = result[@"selector"];
    if (![@[ @"incremental", @"lightweight", @"fullCAR" ] containsObject:selector]) {
      XrpcSpaceRecoveryTestError(response, 409, @"No recovery path was selected");
      return;
    }
    [response setJsonBody:result];
  }];
}

@end
