# Objective-C Rate Limiting and DoS Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:11Z

## Counts
- Unbounded loops: 2
- Unbounded collections: 793
- Memory allocation sites: 56
- WebSocket handlers: 243
- HTTP handlers: 192
- Rate limiting usage: 247
- File size checks: 808
- Timeout configurations: 154

## High priority (handlers without rate limiting)
- ./Garazyk/Sources/AdminUIServer/UIServerRuntime.m
- ./Garazyk/Sources/App/MSTViewer/MSTViewerHandler.h
- ./Garazyk/Sources/App/MSTViewer/MSTViewerHandler.m
- ./Garazyk/Sources/App/OAuthDemo/OAuthDemoHandler.h
- ./Garazyk/Sources/App/OAuthDemo/OAuthDemoHandler.m
- ./Garazyk/Sources/App/server_main.m
- ./Garazyk/Sources/CLI/PDSCLIServeCommand.m
- ./Garazyk/Sources/Germ/Server/Runtime/GermRuntime.m
- ./Garazyk/Sources/Germ/Server/XrpcGermIdentityPack.m
- ./Garazyk/Sources/Germ/Server/XrpcGermMailboxPack.m
- ./Garazyk/Sources/MediaCore/ATProtoMediaXrpcPack.m
- ./Garazyk/Sources/Network/ATProtoHttpMSTViewerRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpOAuthDemoRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpRelayAPIRoutePack.m
- ./Garazyk/Sources/Network/ATProtoHttpXrpcRoutePack.m
- ./Garazyk/Sources/Network/HttpRouter.h
- ./Garazyk/Sources/Network/HttpRouter.m
- ./Garazyk/Sources/Network/XrpcAdminPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyFeedPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyGraphPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyPack.m
- ./Garazyk/Sources/Network/XrpcAppBskyUnspeccedPack.m
- ./Garazyk/Sources/Network/XrpcChatBskyConvoPack.m
- ./Garazyk/Sources/Network/XrpcHandler.h
- ./Garazyk/Sources/Network/XrpcHandlerContext.h
- ./Garazyk/Sources/Network/XrpcHandlerContext.m
- ./Garazyk/Sources/Network/XrpcLabelPack.m
- ./Garazyk/Sources/Network/XrpcLexiconResolver.m
- ./Garazyk/Sources/Network/XrpcMethodRegistry.h
- ./Garazyk/Sources/Network/XrpcModerationPack.m
- ./Garazyk/Sources/Network/XrpcProxyHandler.h
- ./Garazyk/Sources/Network/XrpcProxyHandler.m
- ./Garazyk/Sources/Network/XrpcProxyInterceptor.m
- ./Garazyk/Sources/Network/XrpcRoutePackRegistrar.m
- ./Garazyk/Sources/Network/XrpcServerPack.m
- ./Garazyk/Sources/Network/XrpcSyncPack.m
- ./Garazyk/Sources/Network/XrpcToolsOzonePack.m
- ./Garazyk/Sources/Network/XrpcVendorPack.m
- ./Garazyk/Sources/Sync/Relay/RelayAPIHandler.h
- ./Garazyk/Sources/Sync/Relay/RelayAPIHandler.m
- ./Garazyk/Sources/Video/VideoXrpcPack.m

## Detailed findings

### Unbounded loops
  ./Garazyk/Sources/CLI/PDSCLIInputHelper.m:134:    while (YES) {
  ./Garazyk/Sources/Network/HttpResponse.m:186:        while (YES) {

### Memory allocation without size limits
  ./Garazyk/Sources/Lexicon/ATProtoLexiconRegistry.m:93:    NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
  ./Garazyk/Sources/Compat/Foundation/NSDataCompat.h:16:+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
  ./Garazyk/Sources/Compat/Foundation/NSDataCompat.m:9:+ (nullable NSData *)dataWithContentsOfFile:(NSString *)path
  ./Garazyk/Sources/Compat/Foundation/NSDataCompat.m:12:    NSData *data = [NSData dataWithContentsOfFile:path];
  ./Garazyk/Sources/Sync/Relay/RelayConfiguration.m:51:    NSData *data = [NSData dataWithContentsOfFile:path];
  ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFNetwork.m:28:    struct __CFHTTPMessage *msg = calloc(1, sizeof(struct __CFHTTPMessage));
  ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFNetwork.m:108:    struct __CFURL *url = calloc(1, sizeof(struct __CFURL));
  ./Garazyk/Sources/Blob/PDSDiskBlobProvider.m:70:    return [NSData dataWithContentsOfURL:blobURL options:NSDataReadingMappedIfSafe error:error];
  ./Garazyk/Sources/CLI/PDSCLIHealthCommand.m:83:    NSString *pidContent = [NSString stringWithContentsOfFile:pidPath encoding:NSUTF8StringEncoding error:nil];
  ./Garazyk/Sources/Compat/PlatformShims/CrashReporting/PDSCrashReporter.m:200:    ss.ss_sp = malloc(SIGSTKSZ);
  ./Garazyk/Sources/Video/VideoTranscoder.m:65:            result = [NSData dataWithContentsOfURL:outputURL];
  ./Garazyk/Sources/CLI/PDSCLIDispatcher.m:46:    NSData *data = [NSData dataWithContentsOfFile:configPath options:0 error:&error];
  ./Garazyk/Sources/CLI/PDSCLIDispatcher.m:48:    NSData *data = [NSData dataWithContentsOfFile:configPath];
  ./Garazyk/Sources/Compat/PlatformShims/Security/SecKey.m:82:    SecKeyRef key = malloc(sizeof(struct SecKey));
  ./Garazyk/Sources/Compat/PlatformShims/Security/SecKey.m:93:    SecKeyRef publicKey = malloc(sizeof(struct SecKey));
  ... and 41 more

### WebSocket entry points
  ./Garazyk/Sources/Sync/Relay/RelayClient.m:6:#import "Sync/WebSocket/WebSocketConnection.h"
  ./Garazyk/Sources/Sync/Firehose/Firehose.h:313: @discussion Propagates to the underlying WebSocketConnection, causing
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:24:#import "Sync/WebSocket/WebSocketConnection.h"
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:25:#import "Sync/WebSocket/WebSocketServer.h"
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:43:@interface SubscribeReposHandler () <WebSocketServerDelegate,
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:44:                                     WebSocketConnectionDelegate>
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:46:@property(nonatomic, strong) WebSocketServer *webSocketServer;
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:58:    NSMutableSet<WebSocketConnection *> *attachedConnections;
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:71:                  toConnection:(WebSocketConnection *)connection;
  ./Garazyk/Sources/Sync/Firehose/SubscribeReposHandler.m:72:- (void)detachConnection:(WebSocketConnection *)connection;

## Notes
- Unbounded loops need explicit break conditions.
- Handlers without rate limiting need manual review.
- Memory allocations need size validation for user input.
- WebSocket needs message size limits and backpressure.
