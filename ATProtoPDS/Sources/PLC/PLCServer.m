#import "PLC/PLCServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "PLC/PLCOperation.h"

@interface PLCServer ()
@property (nonatomic, strong) id<PLCStore> store;
@property (nonatomic, strong) PLCAuditor *auditor;
@property (nonatomic, strong) HttpServer *httpServer;
@end

@implementation PLCServer

- (instancetype)initWithStore:(id<PLCStore>)store auditor:(PLCAuditor *)auditor port:(NSUInteger)port {
    self = [super init];
    if (self) {
        _store = store;
        _auditor = auditor;
        _httpServer = [HttpServer serverWithPort:port];
        [self setupRoutes];
    }
    return self;
}

- (void)setupRoutes {
    __weak typeof(self) weakSelf = self;
    
    [self.httpServer addRoute:@"GET" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetDID:req response:resp];
    }];
    
    [self.httpServer addRoute:@"POST" path:@"/:did" handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handlePostDID:req response:resp];
    }];
}

- (void)handleGetDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = req.pathParameters[@"did"];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSError *error = nil;
    NSArray<PLCOperation *> *history = [self.store getHistoryForDID:did error:&error];
    if (error) {
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": error.localizedDescription}];
        return;
    }
    
    if (!history) {
        resp.statusCode = HttpStatusNotFound;
        [resp setJsonBody:@{@"error": @"DID not found"}];
        return;
    }
    
    NSMutableArray *historyDicts = [NSMutableArray array];
    for (PLCOperation *op in history) {
        [historyDicts addObject:[op toDictionary]];
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:historyDicts];
}

- (void)handlePostDID:(HttpRequest *)req response:(HttpResponse *)resp {
    NSString *did = req.pathParameters[@"did"];
    if (!did) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing DID"}];
        return;
    }
    
    NSDictionary *json = req.jsonBody;
    if (!json) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"Missing JSON body"}];
        return;
    }
    
    NSError *error = nil;
    PLCOperation *op = [PLCOperation operationFromDictionary:json error:&error];
    if (!op) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Invalid operation format: %@", error.localizedDescription]}];
        return;
    }
    
    if (![op.did isEqualToString:did]) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": @"DID mismatch"}];
        return;
    }
    
    // Validate using auditor
    if (![self.auditor verifyOperation:op error:&error]) {
        resp.statusCode = HttpStatusBadRequest;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Audit failed: %@", error.localizedDescription]}];
        return;
    }
    
    // Append to store
    if (![self.store appendOperation:op error:&error]) {
        resp.statusCode = HttpStatusInternalServerError;
        [resp setJsonBody:@{@"error": [NSString stringWithFormat:@"Failed to append: %@", error.localizedDescription]}];
        return;
    }
    
    resp.statusCode = HttpStatusOK;
    [resp setJsonBody:@{@"status": @"ok"}];
}

- (BOOL)startWithError:(NSError **)error {
    return [self.httpServer startWithError:error];
}

- (void)stop {
    [self.httpServer stop];
}

@end
