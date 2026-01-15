#import <Foundation/Foundation.h>
#import "XrpcHandler.h"
#import "../PDSController.h"
#import "HttpRequest.h"
#import "HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

/// XrpcMethodRegistry provides a centralized registration mechanism for all
/// AT Protocol XRPC methods supported by the PDS.
///
/// This registry aggregates method registrations from various PDS subsystems
/// (server, repo, sync, identity, moderation, admin) and registers them with
/// the XrpcDispatcher. It serves as a configuration point for enabling or
/// disabling specific protocol features.
///
/// Usage:
/// @code
/// XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];
/// [XrpcMethodRegistry registerMethodsWithDispatcher:dispatcher
///                                        controller:controller];
/// @endcode
@interface XrpcMethodRegistry : NSObject

/// Registers all PDS XRPC methods with the provided dispatcher.
///
/// This method registers methods for all AT Protocol namespaces including:
/// - com.atproto.server (session and account management)
/// - com.atproto.repo (repository operations)
/// - com.atproto.sync (data synchronization)
/// - com.atproto.identity (DID and handle resolution)
/// - com.atproto.moderation (content moderation)
/// - com.atproto.admin (administrative operations)
/// - com.atproto.label (labeling service)
///
/// @param dispatcher The XrpcDispatcher instance to register methods with.
/// @param controller The PDSController providing access to PDS subsystems.
+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                            controller:(PDSController *)controller;

@end

NS_ASSUME_NONNULL_END
