// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/XrpcSpaceRecoveryTestPack.h"

#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"
#import "Network/XrpcRoutePackServices.h"
#import "Services/PDS/PDSSpaceReconciler.h"
#import "Services/PDS/PDSSpaceStore.h"

static NSString *const XrpcSpaceRecoveryTestNSID = @"tools.garazyk.test.spaceRecovery";

static BOOL XrpcSpaceRecoveryTestEnabledValue(NSString *value) {
  return [value isKindOfClass:[NSString class]] &&
      ([value caseInsensitiveCompare:@"true"] == NSOrderedSame || [value isEqualToString:@"1"]);
}

static void XrpcSpaceRecoveryTestError(HttpResponse *response, NSInteger status, NSString *message) {
  response.statusCode = status;
  [response setJsonBody:@{ @"error" : @"RecoveryTestControlError", @"message" : message ?: @"Invalid request" }];
}

@implementation XrpcSpaceRecoveryTestPack

+ (BOOL)isEnabledForEnvironment:(NSDictionary<NSString *, NSString *> *)environment {
  if (![environment isKindOfClass:[NSDictionary class]]) return NO;
  NSString *environmentName = [environment[@"PDS_ENV"] lowercaseString];
  return ![environmentName isEqualToString:@"production"] &&
      XrpcSpaceRecoveryTestEnabledValue(environment[@"PDS_RUNNING_TESTS"]) &&
      XrpcSpaceRecoveryTestEnabledValue(environment[@"PDS_SPACE_RECOVERY_TEST_CONTROL"]);
}

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                      services:(id<XrpcRoutePackServices>)services {
  PDSSpaceStore *spaceStore = services.spaceStore;
  PDSSpaceReconciler *reconciler = services.spaceReconciler;
  if (!spaceStore || !reconciler) return;

  [dispatcher registerMethod:XrpcSpaceRecoveryTestNSID handler:^(HttpRequest *request, HttpResponse *response) {
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

    if ([operation isEqualToString:@"seed"]) {
      NSString *rkey = [body[@"rkey"] isKindOfClass:[NSString class]] ? body[@"rkey"] : @"recovery-seed";
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
