/*!
 @file AppViewAdminRoutePack.h

 @abstract Internal admin HTTP endpoints for AppView management.

 Endpoints:
  POST /admin/backfill/repos         — enqueue a list of DIDs for backfill
  POST /admin/backfill/scope/rebuild — recompute the relevance set from seeds
  GET  /admin/backfill/status        — queue depth, worker health, lag metrics

 All endpoints require the admin bearer token (same as existing admin auth).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpServer;
@class AppViewBackfillOrchestrator;
@class AppViewRelevanceSet;
@class AppViewIngestEngine;
@class AppViewDatabase;
@class ActorService;

@interface AppViewAdminRoutePack : NSObject

+ (void)registerWithServer:(HttpServer *)server
              orchestrator:(AppViewBackfillOrchestrator *)orchestrator
              relevanceSet:(AppViewRelevanceSet *)relevanceSet
              ingestEngine:(AppViewIngestEngine *)ingestEngine
                  database:(AppViewDatabase *)database
              actorService:(ActorService *)actorService
               adminSecret:(NSString *)adminSecret;

@end

NS_ASSUME_NONNULL_END
