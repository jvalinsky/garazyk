#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);

@interface XrpcDispatcher : NSObject

@property (nonatomic, copy) void (^defaultHandler)(HttpRequest *, HttpResponse *);

+ (instancetype)sharedDispatcher;

- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler;
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler;
- (void)registerComAtprotoServerCreateAccount:(XrpcMethodHandler)handler;
- (void)registerComAtprotoServerRefreshSession:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoCreateRecord:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoGetRecord:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoListRecords:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoDeleteRecord:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoApplyWrites:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoDescribeRepo:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoPutRecord:(XrpcMethodHandler)handler;
- (void)registerComAtprotoRepoUploadBlob:(XrpcMethodHandler)handler;
- (void)registerComAtprotoSyncGetRepo:(XrpcMethodHandler)handler;
- (void)registerComAtprotoSyncGetHead:(XrpcMethodHandler)handler;
- (void)registerComAtprotoSyncGetBlob:(XrpcMethodHandler)handler;
- (void)registerComAtprotoSyncListBlobs:(XrpcMethodHandler)handler;
- (void)registerComAtprotoIdentityResolveDid:(XrpcMethodHandler)handler;
- (void)registerComAtprotoIdentityResolveIdentity:(XrpcMethodHandler)handler;
- (void)registerComAtprotoIdentityResolveHandle:(XrpcMethodHandler)handler;

- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler;
- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler;
- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler;
- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler;

@end

NS_ASSUME_NONNULL_END
