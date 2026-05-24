// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "PLCReplicaServer.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PLC/PLCMetrics.h"

@interface PLCReplicaServer ()

@property (nonatomic, assign, readwrite, getter=isReadOnlyMode) BOOL readOnlyMode;

@end

@implementation PLCReplicaServer

- (instancetype)initWithStore:(id<PLCStore>)store
                      auditor:(PLCAuditor *)auditor
                         port:(NSUInteger)port {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initWithStore:(id<PLCStore>)store
                      auditor:(PLCAuditor *)auditor
                         port:(NSUInteger)port
                 readOnlyMode:(BOOL)readOnly {
    return [self initWithStore:store auditor:auditor host:@"127.0.0.1" port:port readOnlyMode:readOnly];
}

- (instancetype)initWithStore:(id<PLCStore>)store
                      auditor:(PLCAuditor *)auditor
                         host:(NSString *)host
                         port:(NSUInteger)port
                 readOnlyMode:(BOOL)readOnly {
    self = [super initWithStore:store auditor:auditor host:host port:port];
    if (self) {
        _readOnlyMode = readOnly;
        [self setupReplicaRoutes];
    }
    return self;
}

- (void)setupReplicaRoutes {
    if (!self.readOnlyMode) {
        return;
    }
    
    __weak typeof(self) weakSelf = self;
    
    for (NSString *method in @[@"POST", @"PUT", @"DELETE"]) {
        [self.httpServer addRoute:method path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
            [weakSelf setCorsHeaders:resp forRequest:req];
            [[PLCMetrics sharedMetrics] recordRequest];
            resp.statusCode = 405;
            [resp setJsonBody:@{
                @"error": @"Method not allowed",
                @"message": @"This is a read-only PLC replica. POST operations are not supported."
            }];
        }];
    }
    
    [self.httpServer addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf setCorsHeaders:resp forRequest:req];
        [weakSelf handleGetHealth:req response:resp];
    }];
}

- (void)handleGetHealth:(HttpRequest *)req response:(HttpResponse *)resp {
    NSMutableDictionary *health = [NSMutableDictionary dictionary];
    health[@"status"] = @"ok";
    health[@"mode"] = @"replica";
    health[@"readOnly"] = @(self.readOnlyMode);
    
    if ([self.store respondsToSelector:@selector(totalOperationCountWithError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSNumber *opCount = (NSNumber *)[self.store performSelector:@selector(totalOperationCountWithError:) withObject:(NSError *)nil];
#pragma clang diagnostic pop
        if (opCount) {
            health[@"operationsCount"] = opCount;
        }
    }
    
    if ([self.store respondsToSelector:@selector(uniqueDIDCountWithError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSNumber *didCount = (NSNumber *)[self.store performSelector:@selector(uniqueDIDCountWithError:) withObject:(NSError *)nil];
#pragma clang diagnostic pop
        if (didCount) {
            health[@"didsCount"] = didCount;
        }
    }
    
    if ([self.store respondsToSelector:@selector(lastSyncTimestampWithError:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        NSDate *lastSync = (NSDate *)[self.store performSelector:@selector(lastSyncTimestampWithError:) withObject:(NSError *)nil];
#pragma clang diagnostic pop
        if (lastSync) {
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
            health[@"lastSync"] = [formatter stringFromDate:lastSync];
        }
    }
    
    resp.statusCode = 200;
    [resp setJsonBody:health];
}

@end
