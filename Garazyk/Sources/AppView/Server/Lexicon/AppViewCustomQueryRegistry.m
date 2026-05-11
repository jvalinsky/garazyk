// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file AppViewCustomQueryRegistry.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Lexicon/AppViewCustomQueryRegistry.h"
#import "Compat/PDSTypes.h"

NSErrorDomain const AppViewCustomQueryRegistryErrorDomain = @"AppViewCustomQueryRegistry";

@interface AppViewCustomQueryRegistry ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, id<AppViewLexiconQueryHandler>> *handlers;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t registryQueue;

@end

@implementation AppViewCustomQueryRegistry

- (instancetype)init {
    self = [super init];
    if (self) {
        _handlers = [NSMutableDictionary dictionary];
        _registryQueue = dispatch_queue_create("com.garazyk.appview.custom-query-registry",
                                               DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)registerHandler:(id<AppViewLexiconQueryHandler>)handler forNSID:(NSString *)nsid {
    if (!handler || !nsid) return;

    dispatch_barrier_async(self.registryQueue, ^{
        self.handlers[nsid] = handler;
    });
}

- (nullable id<AppViewLexiconQueryHandler>)handlerForNSID:(NSString *)nsid {
    if (!nsid) return nil;

    __block id<AppViewLexiconQueryHandler> handler = nil;
    dispatch_sync(self.registryQueue, ^{
        handler = self.handlers[nsid];
    });
    return handler;
}

- (BOOL)hasHandlerForNSID:(NSString *)nsid {
    return [self handlerForNSID:nsid] != nil;
}

- (NSArray<NSString *> *)registeredNSIDs {
    __block NSArray<NSString *> *nsids = nil;
    dispatch_sync(self.registryQueue, ^{
        nsids = [self.handlers.allKeys copy];
    });
    return nsids;
}

- (void)unregisterHandlerForNSID:(NSString *)nsid {
    if (!nsid) return;

    dispatch_barrier_async(self.registryQueue, ^{
        [self.handlers removeObjectForKey:nsid];
    });
}

@end
