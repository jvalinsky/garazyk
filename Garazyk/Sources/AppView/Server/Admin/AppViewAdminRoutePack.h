#import <Foundation/Foundation.h>

@class AppViewBackfillOrchestrator;
@class AppViewIngestEngine;
@class AppViewDatabase;
@class HttpServer;

NS_ASSUME_NONNULL_BEGIN

@interface AppViewAdminRoutePack : NSObject

- (instancetype)initWithOrchestrator:(nullable AppViewBackfillOrchestrator *)orchestrator
                        ingestEngine:(AppViewIngestEngine *)ingestEngine
                            database:(AppViewDatabase *)database
                         adminSecret:(nullable NSString *)adminSecret;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
