// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSPerDidWriteDispatcher.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "Core/PDSPerDidWriteDispatcher.h"
#import "Compat/PDSTypes.h"
#import "Debug/PDSLogger.h"
#include <pthread.h>

// ---------------------------------------------------------------------------
// Per-DID write state
// ---------------------------------------------------------------------------

/*!
 @class PDSPerDidWriteState

 @abstract Internal state for a single DID's write queue.

 @discussion Protected by its own pthread_mutex. The mutex is stored as
 an ivar (not a property) because pthread_mutex_t is a C struct that
 cannot be accessed via ObjC property dot syntax (address-of operator
 does not work on property expressions).
 */
@interface PDSPerDidWriteState : NSObject {
@public
    pthread_mutex_t _mutex;
}

/*! The DID this state belongs to. */
@property (nonatomic, copy, readonly) NSString *did;

/*! Whether a write is currently in progress for this DID. */
@property (nonatomic, assign) BOOL isActive;

/*! Queued write blocks waiting for the current write to complete. */
@property (nonatomic, strong) NSMutableArray<PDSWriteBlock> *pendingWork;

/*! Time of last activity (used for idle eviction). */
@property (nonatomic, assign) NSTimeInterval lastActivityTime;

+ (instancetype)stateForDid:(NSString *)did;
- (void)destroyMutex;

@end

@implementation PDSPerDidWriteState

+ (instancetype)stateForDid:(NSString *)did {
    PDSPerDidWriteState *state = [[self alloc] init];
    if (state) {
        state->_did = [did copy];
        pthread_mutex_init(&state->_mutex, NULL);
        state->_isActive = NO;
        state->_pendingWork = [NSMutableArray array];
        state->_lastActivityTime = 0;
    }
    return state;
}

- (void)destroyMutex {
    pthread_mutex_destroy(&_mutex);
}

@end

// ---------------------------------------------------------------------------
// PDSPerDidWriteDispatcher
// ---------------------------------------------------------------------------

static const NSTimeInterval kDefaultIdleEvictionSeconds = 60.0;

@interface PDSPerDidWriteDispatcher ()

/*! Serial gate queue — acquires concurrency semaphore before dispatching
    to the worker pool. Prevents thread explosion on Linux/GNUstep where
    dispatch_async to a concurrent queue with a blocking semaphore would
    create one thread per pending block. */
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t gateQueue;
#else
@property (nonatomic, strong) dispatch_queue_t gateQueue;
#endif

/*! Concurrent worker pool — executes write blocks. */
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t workerQueue;
#else
@property (nonatomic, strong) dispatch_queue_t workerQueue;
#endif

/*! Semaphore limiting concurrent writers. */
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_semaphore_t concurrencySemaphore;
#else
@property (nonatomic, strong) dispatch_semaphore_t concurrencySemaphore;
#endif

/*! Serial queue protecting didStateMap. */
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_queue_t stateMapQueue;
#else
@property (nonatomic, strong) dispatch_queue_t stateMapQueue;
#endif

/*! Per-DID write state. Key: DID string, Value: PDSPerDidWriteState. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, PDSPerDidWriteState *> *didStateMap;

/*! Timer for idle eviction. */
#if defined(GNUSTEP)
@property (nonatomic, assign) dispatch_source_t evictionTimer;
#else
@property (nonatomic, strong) dispatch_source_t evictionTimer;
#endif

/*! Whether the dispatcher has been stopped. */
@property (nonatomic, assign) BOOL stopped;

@end

@implementation PDSPerDidWriteDispatcher

- (instancetype)initWithConcurrencyLimit:(NSUInteger)concurrencyLimit
                    idleEvictionSeconds:(NSTimeInterval)idleEvictionSeconds {
    if (self = [super init]) {
        _concurrencyLimit = concurrencyLimit > 0 ? concurrencyLimit : 32;
        _idleEvictionSeconds = idleEvictionSeconds > 0 ? idleEvictionSeconds : kDefaultIdleEvictionSeconds;
        _stopped = NO;

        _workerQueue = dispatch_queue_create("dev.garazyk.pds.write-dispatcher.workers",
                                              DISPATCH_QUEUE_CONCURRENT);
        _gateQueue = dispatch_queue_create("dev.garazyk.pds.write-dispatcher.gate",
                                            DISPATCH_QUEUE_SERIAL);
        _concurrencySemaphore = dispatch_semaphore_create((int64_t)_concurrencyLimit);
        _stateMapQueue = dispatch_queue_create("dev.garazyk.pds.write-dispatcher.statemap",
                                                DISPATCH_QUEUE_SERIAL);
        _didStateMap = [NSMutableDictionary dictionary];

        // Set up idle eviction timer
        if (_idleEvictionSeconds > 0) {
            _evictionTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     _stateMapQueue);
            uint64_t intervalNs = (uint64_t)(_idleEvictionSeconds * NSEC_PER_SEC);
            dispatch_source_set_timer(_evictionTimer,
                                      dispatch_time(DISPATCH_TIME_NOW, intervalNs),
                                      intervalNs,
                                      intervalNs / 10);

            __weak typeof(self) weakSelf = self;
            dispatch_source_t timer = _evictionTimer;
#ifndef __APPLE__
            dispatch_retain(timer);
#endif
            dispatch_source_set_event_handler(_evictionTimer, ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) {
#ifndef __APPLE__
                    dispatch_release(timer);
#endif
                    return;
                }
                [strongSelf _evictIdleStates];
            });
            dispatch_resume(_evictionTimer);
#ifndef __APPLE__
            dispatch_release(timer);
#endif
        }
    }
    return self;
}

- (void)dealloc {
    [self _stopInternal];
}

- (void)_stopInternal {
    if (self.stopped) return;
    self.stopped = YES;

    if (self.evictionTimer) {
        dispatch_source_cancel(self.evictionTimer);
    }

    // Destroy all per-DID mutexes
    for (PDSPerDidWriteState *state in self.didStateMap.allValues) {
        [state destroyMutex];
    }
    [self.didStateMap removeAllObjects];
}

#pragma mark - Public Methods

- (void)dispatchWriteForDid:(NSString *)did block:(PDSWriteBlock)block {
    if (self.stopped || !did || !block) return;

    // Capture dispatch objects as strong locals for GNUstep
    dispatch_semaphore_t semaphore = self.concurrencySemaphore;
    dispatch_queue_t workerQ = self.workerQueue;
    dispatch_queue_t gateQ = self.gateQueue;
#ifndef __APPLE__
    dispatch_retain(semaphore);
    dispatch_retain(workerQ);
    dispatch_retain(gateQ);
#endif

    // Get or create per-DID state on the serial stateMapQueue.
    // This is fast (dictionary lookup + mutex lock/unlock) and does not
    // block on the concurrency semaphore.
    __block PDSPerDidWriteState *state = nil;
    __block BOOL shouldDispatch = NO;
    dispatch_sync(self.stateMapQueue, ^{
        state = self.didStateMap[did];
        if (!state) {
            state = [PDSPerDidWriteState stateForDid:did];
            self.didStateMap[did] = state;
        }
        state.lastActivityTime = [NSDate timeIntervalSinceReferenceDate];

        pthread_mutex_lock(&state->_mutex);
        if (state.isActive) {
            // A write is already in progress for this DID — queue it
            [state.pendingWork addObject:[block copy]];
            pthread_mutex_unlock(&state->_mutex);
            PDS_LOG_DEBUG(@"[WriteDispatcher] Queued write for did=%@ (pending=%lu)",
                          did, (unsigned long)state.pendingWork.count);
        } else {
            // No write in progress — mark active and dispatch
            state.isActive = YES;
            shouldDispatch = YES;
            pthread_mutex_unlock(&state->_mutex);
        }
    });

    if (shouldDispatch) {
        // Dispatch through the gate queue. The gate queue is serial, so
        // only one thread at a time waits on the semaphore. This prevents
        // thread explosion on Linux/GNUstep.
        dispatch_async(gateQ, ^{
            // Wait for a concurrency slot on the gate queue (serial, so
            // at most one thread is parked here at a time)
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

            // Now dispatch the actual work to the concurrent worker pool
            dispatch_async(workerQ, ^{
                @autoreleasepool {
                    NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
                    PDS_LOG_DEBUG(@"[WriteDispatcher] Starting write for did=%@", did);

                    block();

                    NSTimeInterval elapsed = ([NSDate timeIntervalSinceReferenceDate] - start) * 1000.0;
                    PDS_LOG_DEBUG(@"[WriteDispatcher] Completed write for did=%@ (%.1fms)", did, elapsed);

                    // Release concurrency slot
                    dispatch_semaphore_signal(semaphore);

                    // Process any pending work for this DID
                    [self _processNextPendingForDid:did state:state
                                            semaphore:semaphore workerQueue:workerQ
                                              gateQueue:gateQ];
                }
            });
        });
    }

#ifndef __APPLE__
    dispatch_release(semaphore);
    dispatch_release(workerQ);
    dispatch_release(gateQ);
#endif
}

#pragma mark - Internal Pending Work Processing

- (void)_processNextPendingForDid:(NSString *)did
                            state:(PDSPerDidWriteState *)state
                        semaphore:(dispatch_semaphore_t)semaphore
                      workerQueue:(dispatch_queue_t)workerQueue
                        gateQueue:(dispatch_queue_t)gateQueue {
    pthread_mutex_lock(&state->_mutex);
    state.lastActivityTime = [NSDate timeIntervalSinceReferenceDate];

    if (state.pendingWork.count > 0) {
        PDSWriteBlock nextBlock = state.pendingWork[0];
        [state.pendingWork removeObjectAtIndex:0];
        pthread_mutex_unlock(&state->_mutex);

        PDS_LOG_DEBUG(@"[WriteDispatcher] Dequeued next write for did=%@ (remaining=%lu)",
                      did, (unsigned long)state.pendingWork.count);

        // Dispatch through the gate queue to wait for a concurrency slot
        dispatch_async(gateQueue, ^{
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

            dispatch_async(workerQueue, ^{
                @autoreleasepool {
                    NSTimeInterval nextStart = [NSDate timeIntervalSinceReferenceDate];
                    nextBlock();
                    NSTimeInterval nextElapsed = ([NSDate timeIntervalSinceReferenceDate] - nextStart) * 1000.0;
                    PDS_LOG_DEBUG(@"[WriteDispatcher] Completed queued write for did=%@ (%.1fms)",
                                  did, nextElapsed);
                    dispatch_semaphore_signal(semaphore);
                    [self _processNextPendingForDid:did state:state
                                            semaphore:semaphore workerQueue:workerQueue
                                              gateQueue:gateQueue];
                }
            });
        });
    } else {
        state.isActive = NO;
        pthread_mutex_unlock(&state->_mutex);
        PDS_LOG_DEBUG(@"[WriteDispatcher] No more pending writes for did=%@", did);
    }
}

#pragma mark - Idle Eviction

- (void)_evictIdleStates {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval threshold = self.idleEvictionSeconds;
    NSMutableArray<NSString *> *keysToRemove = [NSMutableArray array];

    for (NSString *did in self.didStateMap) {
        PDSPerDidWriteState *state = self.didStateMap[did];
        pthread_mutex_lock(&state->_mutex);
        BOOL isIdle = !state.isActive && state.pendingWork.count == 0 &&
                      (now - state.lastActivityTime) > threshold;
        pthread_mutex_unlock(&state->_mutex);

        if (isIdle) {
            [keysToRemove addObject:did];
        }
    }

    for (NSString *did in keysToRemove) {
        PDSPerDidWriteState *state = self.didStateMap[did];
        [state destroyMutex];
        [self.didStateMap removeObjectForKey:did];
        PDS_LOG_DEBUG(@"[WriteDispatcher] Evicted idle state for did=%@", did);
    }

    if (keysToRemove.count > 0) {
        PDS_LOG_DEBUG(@"[WriteDispatcher] Evicted %lu idle DID states",
                      (unsigned long)keysToRemove.count);
    }
}

#pragma mark - Diagnostics

- (NSUInteger)activeDidCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.stateMapQueue, ^{
        for (PDSPerDidWriteState *state in self.didStateMap.allValues) {
            pthread_mutex_lock(&state->_mutex);
            if (state.isActive) count++;
            pthread_mutex_unlock(&state->_mutex);
        }
    });
    return count;
}

- (NSUInteger)pendingWriteCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.stateMapQueue, ^{
        for (PDSPerDidWriteState *state in self.didStateMap.allValues) {
            pthread_mutex_lock(&state->_mutex);
            count += state.pendingWork.count;
            pthread_mutex_unlock(&state->_mutex);
        }
    });
    return count;
}

- (NSUInteger)totalDidCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.stateMapQueue, ^{
        count = self.didStateMap.count;
    });
    return count;
}

@end
