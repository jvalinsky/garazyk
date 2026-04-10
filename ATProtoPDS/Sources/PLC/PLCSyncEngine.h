/*!
 @file PLCSyncEngine.h

 @abstract Sync orchestration engine for PLC replica.

 @discussion
    PLCSyncEngine manages the complete sync lifecycle for a PLC read replica:
    - Initial backfill from /export endpoint
    - Live sync via polling (WebSocket deferred)
    - Parallel operation validation via worker queue
    - Error recovery with exponential backoff
    
    The engine publishes metrics for monitoring sync progress.

 @copyright Copyright (c) 2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PLC/PLCSyncClient.h"
#import "PLC/PLCReplicaStore.h"
#import "PLC/PLCAuditor.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PLCSyncState) {
    PLCSyncStateIdle,
    PLCSyncStateBackfilling,
    PLCSyncStateLiveSyncing,
    PLCSyncStatePaused,
    PLCSyncStateError
};

@protocol PLCSyncEngineDelegate <NSObject>
@optional
- (void)syncEngineDidStartBackfill:(id)engine;
- (void)syncEngine:(id)engine backfillProgress:(float)progress operationsIngested:(NSUInteger)count;
- (void)syncEngineDidCompleteBackfill:(id)engine operationsIngested:(NSUInteger)count;
- (void)syncEngine:(id)engine didIngestOperations:(NSArray *)ops count:(NSUInteger)count;
- (void)syncEngine:(id)engine didEncounterError:(NSError *)error;
- (void)syncEngineStateDidChange:(id)engine fromState:(PLCSyncState)fromState toState:(PLCSyncState)toState;
@end

@interface PLCSyncEngine : NSObject

@property (nonatomic, weak, nullable) id<PLCSyncEngineDelegate> delegate;
@property (nonatomic, assign, readonly) PLCSyncState state;
@property (nonatomic, assign) NSUInteger numWorkers;
@property (nonatomic, assign) NSUInteger batchSize;
@property (nonatomic, assign) NSTimeInterval pollInterval;
@property (nonatomic, assign) NSUInteger maxRetries;
@property (nonatomic, assign) NSTimeInterval maxRetryDelay;

@property (nonatomic, assign, readonly) NSUInteger totalOperationsIngested;
@property (nonatomic, assign, readonly) NSUInteger totalOperationsFailed;
@property (nonatomic, strong, readonly, nullable) NSDate *lastSyncDate;
@property (nonatomic, assign, readonly) NSInteger currentCursor;

- (instancetype)initWithStore:(PLCReplicaStore *)store
                       client:(PLCSyncClient *)client
                      auditor:(PLCAuditor *)auditor NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;
- (void)pause;
- (void)resume;

- (BOOL)syncOnceWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END