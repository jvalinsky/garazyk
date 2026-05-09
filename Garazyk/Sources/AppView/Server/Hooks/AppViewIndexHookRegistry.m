/*!
 @file AppViewIndexHookRegistry.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Hooks/AppViewIndexHookRegistry.h"
#import "AppView/Server/Hooks/AppViewIndexHook.h"
#import "AppView/Server/AppViewDatabase.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

@interface AppViewIndexHookRegistry ()

@property (nonatomic, strong) AppViewDatabase *database;
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<AppViewIndexHook>> *hooks;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t hookQueue;

@end

@implementation AppViewIndexHookRegistry

- (instancetype)initWithDatabase:(AppViewDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _hooks = [NSMutableDictionary dictionary];
        _hookQueue = dispatch_queue_create("com.garazyk.appview.index-hooks",
                                           DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)registerHook:(id<AppViewIndexHook>)hook {
    if (!hook) return;
    NSString *identifier = [hook hookIdentifier];
    if (!identifier) return;

    dispatch_barrier_async(self.hookQueue, ^{
        self.hooks[identifier] = hook;
    });

    PDS_LOG_INFO(@"[IndexHookRegistry] Registered hook: %@", identifier);
}

- (void)unregisterHook:(NSString *)hookIdentifier {
    if (!hookIdentifier) return;

    dispatch_barrier_async(self.hookQueue, ^{
        [self.hooks removeObjectForKey:hookIdentifier];
    });

    PDS_LOG_INFO(@"[IndexHookRegistry] Unregistered hook: %@", hookIdentifier);
}

- (void)fireDidIndexRecord:(NSDictionary *)record
                       uri:(NSString *)uri
                        did:(NSString *)did
                collection:(NSString *)collection {
    NSArray<id<AppViewIndexHook>> *matchingHooks = [self matchingHooksForCollection:collection];

    for (id<AppViewIndexHook> hook in matchingHooks) {
        id<AppViewIndexHook> retainedHook = hook;
        dispatch_async(self.hookQueue, ^{
            @try {
                [retainedHook didIndexRecord:record
                                         uri:uri
                                          did:did
                                  collection:collection];
            } @catch (NSException *exception) {
                PDS_LOG_WARN(@"[IndexHookRegistry] Hook %@ threw exception: %@",
                             [retainedHook hookIdentifier],
                             exception.reason ?: @"unknown");
                [self recordHookFailure:retainedHook
                                    uri:uri
                                    did:did
                            collection:collection
                              eventType:@"index"
                           errorMessage:exception.reason];
            }
        });
    }
}

- (void)fireDidDeleteRecordWithURI:(NSString *)uri
                               did:(NSString *)did
                        collection:(NSString *)collection {
    NSArray<id<AppViewIndexHook>> *matchingHooks = [self matchingHooksForCollection:collection];

    for (id<AppViewIndexHook> hook in matchingHooks) {
        id<AppViewIndexHook> retainedHook = hook;
        dispatch_async(self.hookQueue, ^{
            @try {
                [retainedHook didDeleteRecordWithURI:uri
                                                  did:did
                                           collection:collection];
            } @catch (NSException *exception) {
                PDS_LOG_WARN(@"[IndexHookRegistry] Hook %@ threw exception: %@",
                             [retainedHook hookIdentifier],
                             exception.reason ?: @"unknown");
                [self recordHookFailure:retainedHook
                                    uri:uri
                                    did:did
                            collection:collection
                              eventType:@"delete"
                           errorMessage:exception.reason];
            }
        });
    }
}

- (NSUInteger)registeredHookCount {
    __block NSUInteger count = 0;
    dispatch_sync(self.hookQueue, ^{
        count = self.hooks.count;
    });
    return count;
}

#pragma mark - Private

- (NSArray<id<AppViewIndexHook>> *)matchingHooksForCollection:(NSString *)collection {
    __block NSMutableArray<id<AppViewIndexHook>> *matching = [NSMutableArray array];
    dispatch_sync(self.hookQueue, ^{
        for (id<AppViewIndexHook> hook in self.hooks.allValues) {
            NSArray *hookCollections = [hook collections];
            // nil collections = fire for all collections
            if (!hookCollections || hookCollections.count == 0 ||
                [hookCollections containsObject:collection]) {
                [matching addObject:hook];
            }
        }
    });
    return [matching copy];
}

- (void)recordHookFailure:(id<AppViewIndexHook>)hook
                      uri:(NSString *)uri
                      did:(NSString *)did
              collection:(NSString *)collection
                eventType:(NSString *)eventType
             errorMessage:(nullable NSString *)errorMessage {
    NSString *hookId = [hook hookIdentifier];
    NSString *sql = @"INSERT INTO dead_letter_hooks (hook_id, uri, did, collection, event_type, error_message) VALUES (?, ?, ?, ?, ?, ?)";
    NSArray *params = @[hookId, uri, did, collection, eventType, errorMessage ?: @"unknown"];

    // Use the database's executeParameterizedUpdate for INSERT
    NSError *error = nil;
    [self.database executeParameterizedUpdate:sql params:params error:&error];
    if (error) {
        PDS_LOG_WARN(@"[IndexHookRegistry] Failed to record hook failure for %@: %@",
                     hookId, error.localizedDescription);
    }
}

@end
