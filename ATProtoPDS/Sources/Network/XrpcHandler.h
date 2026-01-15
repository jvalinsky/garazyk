#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

/// A block type for handling XRPC method invocations.
///
/// @param request The incoming HTTP request containing the XRPC method call.
/// @param response The response object used to send the XRPC response back.
typedef void (^XrpcMethodHandler)(HttpRequest *request, HttpResponse *response);

/// XrpcDispatcher handles XRPC method invocation, routing incoming XRPC requests
/// to registered method handlers and formatting responses according to the XRPC protocol.
///
/// The XRPC protocol (extended RPC) is used by AT Protocol for remote procedure calls.
/// This dispatcher manages method registration, lookup, and invocation lifecycle.
///
/// @note This class serves as both the XRPC handler and registry for the PDS.
@interface XrpcDispatcher : NSObject

/// A fallback handler invoked when no registered method matches the incoming request.
/// This can be used to provide default behavior or custom error responses.
@property (nonatomic, copy) void (^defaultHandler)(HttpRequest *, HttpResponse *);

/// Returns the shared singleton XrpcDispatcher instance.
+ (instancetype)sharedDispatcher;

/// Registers an XRPC method handler with the dispatcher.
///
/// @param methodId The fully-qualified method identifier (e.g., @"com.atproto.server.createSession").
/// @param handler The block to invoke when the method is called.
- (void)registerMethod:(NSString *)methodId handler:(XrpcMethodHandler)handler;

/// Processes an incoming HTTP request as an XRPC method call.
///
/// @param request The HTTP request containing the XRPC method invocation.
/// @param response The response object to populate with the method result or error.
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

// MARK: - ComAtproto Server Methods

/// Registers a handler for com.atproto.server.createSession.
/// Creates a new session for an authenticated user.
- (void)registerComAtprotoServerCreateSession:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.server.createAccount.
/// Creates a new account on the PDS.
- (void)registerComAtprotoServerCreateAccount:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.server.refreshSession.
/// Refreshes an existing session using a refresh token.
- (void)registerComAtprotoServerRefreshSession:(XrpcMethodHandler)handler;

// MARK: - ComAtproto Repo Methods

/// Registers a handler for com.atproto.repo.createRecord.
/// Creates a new record in the user's repository.
- (void)registerComAtprotoRepoCreateRecord:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.getRecord.
/// Retrieves a specific record from the repository.
- (void)registerComAtprotoRepoGetRecord:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.listRecords.
/// Lists records in the repository with optional filtering.
- (void)registerComAtprotoRepoListRecords:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.deleteRecord.
/// Deletes a record from the repository.
- (void)registerComAtprotoRepoDeleteRecord:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.applyWrites.
/// Applies multiple write operations in a single transaction.
- (void)registerComAtprotoRepoApplyWrites:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.describeRepo.
/// Returns metadata about the user's repository.
- (void)registerComAtprotoRepoDescribeRepo:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.putRecord.
/// Creates or updates a record in the repository.
- (void)registerComAtprotoRepoPutRecord:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.repo.uploadBlob.
/// Uploads binary blob data to the repository.
- (void)registerComAtprotoRepoUploadBlob:(XrpcMethodHandler)handler;

// MARK: - ComAtproto Sync Methods

/// Registers a handler for com.atproto.sync.getRepo.
/// Retrieves the complete repository data for an identity.
- (void)registerComAtprotoSyncGetRepo:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.sync.getHead.
/// Returns the current commit HEAD for an identity.
- (void)registerComAtprotoSyncGetHead:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.sync.getBlob.
/// Retrieves a specific blob from the repository.
- (void)registerComAtprotoSyncGetBlob:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.sync.listBlobs.
/// Lists blob CID references in the repository.
- (void)registerComAtprotoSyncListBlobs:(XrpcMethodHandler)handler;

// MARK: - ComAtproto Identity Methods

/// Registers a handler for com.atproto.identity.resolveDID.
/// Resolves a DID identifier to its document.
- (void)registerComAtprotoIdentityResolveDid:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.identity.resolveIdentity.
/// Resolves an identity (DID or handle) to its details.
- (void)registerComAtprotoIdentityResolveIdentity:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.identity.resolveHandle.
/// Resolves a handle to its associated DID.
- (void)registerComAtprotoIdentityResolveHandle:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.identity.getRecommendedDidCredentials.
/// Returns recommended DID document fields for the authenticated identity.
- (void)registerComAtprotoIdentityGetRecommendedDidCredentials:(XrpcMethodHandler)handler;

// MARK: - ComAtproto Moderation Methods

/// Registers a handler for com.atproto.moderation.createReport.
/// Creates a moderation report for content.
- (void)registerComAtprotoModerationCreateReport:(XrpcMethodHandler)handler;

// MARK: - ComAtproto Admin Methods

/// Registers a handler for com.atproto.admin.updateSubjectStatus.
/// Updates the moderation status of a subject.
- (void)registerComAtprotoAdminUpdateSubjectStatus:(XrpcMethodHandler)handler;

/// Registers a handler for com.atproto.admin.getSubjectStatus.
/// Retrieves the moderation status of a subject.
- (void)registerComAtprotoAdminGetSubjectStatus:(XrpcMethodHandler)handler;

// MARK: - ComAtproto Label Methods

/// Registers a handler for com.atproto.label.queryLabels.
/// Queries labels from the label service.
- (void)registerComAtprotoLabelQueryLabels:(XrpcMethodHandler)handler;

@end

NS_ASSUME_NONNULL_END
