// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSSignalManager.m

 @abstract Implementation of lifecycle signal management.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "PDSSignalManager.h"
#import "Compat/PDSTypes.h"
#import <signal.h>
#import <string.h>

@interface PDSSignalManager ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<PDSSignalHandlerBlock> *> *handlers;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSValue *> *sources;
@end

@implementation PDSSignalManager

+ (instancetype)sharedManager {
    static PDSSignalManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[PDSSignalManager alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _handlers = [NSMutableDictionary dictionary];
        _sources = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)installIgnoredSignals {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_IGN;
    sigemptyset(&sa.sa_mask);

    // Ignore SIGPIPE — prevents EPIPE crashes when clients disconnect
    sigaction(SIGPIPE, &sa, NULL);

    // Ignore SIGHUP at the process level so dispatch_source can receive it.
    // If you want to handle SIGHUP (e.g. for config reload), use
    // registerHandlerForSignal:SIGHUP instead of installIgnoredSignals.
    sigaction(SIGHUP, &sa, NULL);
}

- (void)registerHandlerForSignal:(int)signalNumber
                          handler:(PDSSignalHandlerBlock)handler {
    if (!handler) return;

    NSNumber *key = @(signalNumber);

    // Add the handler to the list
    @synchronized(self.handlers) {
        NSMutableArray *list = self.handlers[key];
        if (!list) {
            list = [NSMutableArray array];
            self.handlers[key] = list;
        }
        [list addObject:handler];
    }

    // Create dispatch source if one doesn't exist for this signal
    @synchronized(self.sources) {
        if (!self.sources[key]) {
            // Unblock the signal so dispatch_source can receive it
            sigset_t mask;
            sigemptyset(&mask);
            sigaddset(&mask, signalNumber);
            sigprocmask(SIG_BLOCK, &mask, NULL);

            // For SIGHUP, switch from SIG_IGN to a pending state so
            // the dispatch source can receive it
            if (signalNumber == SIGHUP) {
                struct sigaction sa;
                memset(&sa, 0, sizeof(sa));
                sa.sa_handler = SIG_DFL;
                sigemptyset(&sa.sa_mask);
                sigaction(SIGHUP, &sa, NULL);
            }

            dispatch_source_t source = dispatch_source_create(
                DISPATCH_SOURCE_TYPE_SIGNAL,
                (uintptr_t)signalNumber,
                0,
                dispatch_get_main_queue());

            __weak typeof(self) weakSelf = self;
            dispatch_source_set_event_handler(source, ^{
                PDSSignalManager *strongSelf = weakSelf;
                if (!strongSelf) return;

                NSArray<PDSSignalHandlerBlock> *handlersCopy = nil;
                @synchronized(strongSelf.handlers) {
                    NSMutableArray *list = strongSelf.handlers[key];
                    if (list) {
                        handlersCopy = [list copy];
                    }
                }

                for (PDSSignalHandlerBlock block in handlersCopy) {
                    block(signalNumber);
                }
            });

            dispatch_resume(source);
            self.sources[key] = [NSValue valueWithPointer:(void *)source];
        }
    }
}

- (void)unregisterHandlerForSignal:(int)signalNumber {
    NSNumber *key = @(signalNumber);

    @synchronized(self.handlers) {
        [self.handlers removeObjectForKey:key];
    }

    @synchronized(self.sources) {
        NSValue *val = self.sources[key];
        if (val) {
            dispatch_source_t source = (dispatch_source_t)[val pointerValue];
            dispatch_source_cancel(source);
            [self.sources removeObjectForKey:key];
        }
    }

    // Restore default signal disposition
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = SIG_DFL;
    sigemptyset(&sa.sa_mask);
    sigaction(signalNumber, &sa, NULL);

    // Unblock the signal
    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, signalNumber);
    sigprocmask(SIG_UNBLOCK, &mask, NULL);
}

@end
