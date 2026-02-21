#import "PDSRelayService.h"
#import "PDSRecordService.h"
#import "Debug/PDSLogger.h"
#import "Compat/PDSTypes.h"

#ifndef MSEC_PER_SEC
#define MSEC_PER_SEC 1000ULL
#endif

@interface PDSRelayService ()

@property (nonatomic, copy) NSArray<NSString *> *relays;
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingDids;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_queue_t queue;
@property (nonatomic, PDS_DISPATCH_QUEUE_STRONG) dispatch_source_t timer;

@end

@implementation PDSRelayService

- (instancetype)initWithRelays:(NSArray<NSString *> *)relays hostname:(NSString *)hostname {
    self = [super init];
    if (self) {
        _relays = [relays copy];
        _hostname = [hostname copy];
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        _pendingDids = [NSMutableSet set];
        _queue = dispatch_queue_create("com.atproto.pds.relay.service", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRecordChange:)
                                                 name:PDSRecordDidChangeNotification
                                               object:nil];
    PDS_LOG_INFO(@"PDSRelayService started with %lu relays", (unsigned long)self.relays.count);
}

- (void)stop {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (self.timer) {
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    }
}

- (void)handleRecordChange:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *did = userInfo[@"did"];
    if (!did) return;

    dispatch_async(self.queue, ^{
        [self.pendingDids addObject:did];
        [self scheduleNotification];
    });
}

- (void)scheduleNotification {
    if (self.timer) return;

    self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
    // Debounce for 1 second to avoid spamming relays for batch operations
    dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, 100 * MSEC_PER_SEC);
    
    dispatch_source_set_event_handler(self.timer, ^{
        [self processPendingNotifications];
        dispatch_source_cancel(self.timer);
        self.timer = nil;
    });
    
    dispatch_resume(self.timer);
}

- (void)processPendingNotifications {
    if (self.pendingDids.count == 0 || self.relays.count == 0) return;

    NSSet *didsToNotify = [self.pendingDids copy];
    [self.pendingDids removeAllObjects];

    PDS_LOG_DEBUG(@"PDSRelayService notifying %lu relays of updates for %lu DIDs", (unsigned long)self.relays.count, (unsigned long)didsToNotify.count);

    for (NSString *relayHost in self.relays) {
        [self notifyRelay:relayHost];
    }
}

- (void)notifyRelay:(NSString *)relayHost {
    NSURLComponents *components = [NSURLComponents componentsWithString:relayHost];
    if (!components.scheme) {
        components.scheme = @"https";
    }
    components.path = @"/xrpc/com.atproto.sync.requestCrawl";
    
    NSURL *url = components.URL;
    if (!url) {
        PDS_LOG_ERROR(@"PDSRelayService: Invalid relay URL for host: %@", relayHost);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSDictionary *body = @{@"hostname": self.hostname ?: @""};
    NSError *error = nil;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:&error];
    
    if (error) {
        PDS_LOG_ERROR(@"PDSRelayService: Failed to serialize requestCrawl body: %@", error);
        return;
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (error) {
            PDS_LOG_ERROR(@"PDSRelayService: Failed to notify relay %@: %@", relayHost, error.localizedDescription);
        } else if (httpResponse.statusCode >= 300) {
            PDS_LOG_WARN(@"PDSRelayService: Relay %@ returned status %ld", relayHost, (long)httpResponse.statusCode);
        } else {
            PDS_LOG_DEBUG(@"PDSRelayService: Successfully notified relay %@", relayHost);
        }
    }];
    [task resume];
}

@end
