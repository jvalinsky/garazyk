#import "App/Explore/ExploreHandler.h"
#import "App/Explore/ExploreCache.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "App/PDSConfiguration.h"
#import "Debug/PDSLogger.h"
#import "Database/PDSDatabase.h"
#import "Core/CID.h"
#import "Core/TID.h"
#import "Compat/Foundation/NSDataCompat.h"
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

#pragma mark - API Endpoint Descriptor Classes

@implementation APIParameterDescriptor

+ (instancetype)initWithName:(NSString *)name in:(NSString *)inLocation type:(NSString *)type description:(NSString *)description required:(BOOL)required {
    APIParameterDescriptor *param = [[APIParameterDescriptor alloc] init];
    param.name = name;
    param.in = inLocation;
    param.type = type;
    param.paramDescription = description;
    param.required = required;
    param.deprecated = NO;
    return param;
}

- (NSDictionary *)openAPIDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"name"] = self.name;
    dict[@"in"] = self.in;
    NSMutableDictionary *schema = [NSMutableDictionary dictionary];
    schema[@"type"] = self.type;
    if (self.paramDescription.length > 0) {
        schema[@"description"] = self.paramDescription;
    }
    dict[@"schema"] = schema;
    dict[@"required"] = self.required ? @YES : @NO;
    if (self.deprecated) {
        dict[@"deprecated"] = @YES;
    }
    return [dict copy];
}

@end

@implementation APIResponseDescriptor

+ (instancetype)initWithStatusCode:(NSString *)statusCode description:(NSString *)description {
    APIResponseDescriptor *resp = [[APIResponseDescriptor alloc] init];
    resp.statusCode = statusCode;
    resp.responseDescription = description;
    return resp;
}

- (NSDictionary *)openAPIDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"description"] = self.responseDescription;

    if (self.schemaRef.length > 0 || self.arrayItemRef.length > 0) {
        NSMutableDictionary *content = [NSMutableDictionary dictionary];
        NSMutableDictionary *mediaType = [NSMutableDictionary dictionary];

        if (self.arrayItemRef.length > 0) {
            mediaType[@"schema"] = @{
                @"type": @"array",
                @"items": @{@"$ref": self.arrayItemRef}
            };
        } else if (self.schemaRef.length > 0) {
            mediaType[@"schema"] = @{@"$ref": self.schemaRef};
        }

        content[@"application/json"] = mediaType;
        dict[@"content"] = content;
    }

    return [dict copy];
}

@end

@implementation APIEndpointDescriptor

+ (instancetype)descriptorWithPath:(NSString *)path
                            method:(NSString *)method
                           summary:(NSString *)summary
                      endpointName:(NSString *)endpointName
                      operationId:(NSString *)operationId
                             tags:(NSArray<NSString *> *)tags
                        parameters:(NSArray<APIParameterDescriptor *> *)parameters
                        responses:(NSArray<APIResponseDescriptor *> *)responses {
    APIEndpointDescriptor *desc = [[APIEndpointDescriptor alloc] init];
    desc.path = path;
    desc.method = method;
    desc.summary = summary;
    desc.endpointName = endpointName;
    desc.operationId = operationId;
    desc.tags = tags;
    desc.parameters = parameters ?: @[];
    desc.responses = responses ?: @[];
    return desc;
}

- (NSDictionary *)openAPIDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    if (self.operationId.length > 0) {
        dict[@"operationId"] = self.operationId;
    }
    if (self.summary.length > 0) {
        dict[@"summary"] = self.summary;
    }
    if (self.endpointDescription.length > 0) {
        dict[@"description"] = self.endpointDescription;
    }
    if (self.tags.count > 0) {
        dict[@"tags"] = self.tags;
    }
    if (self.deprecated) {
        dict[@"deprecated"] = @YES;
    }

    if (self.parameters.count > 0) {
        NSMutableArray *paramDicts = [NSMutableArray array];
        for (APIParameterDescriptor *param in self.parameters) {
            [paramDicts addObject:[param openAPIDict]];
        }
        dict[@"parameters"] = paramDicts;
    }

    if (self.responses.count > 0) {
        NSMutableDictionary *responses = [NSMutableDictionary dictionary];
        for (APIResponseDescriptor *resp in self.responses) {
            responses[resp.statusCode] = [resp openAPIDict];
        }
        dict[@"responses"] = responses;
    }

    return [dict copy];
}

@end

#pragma mark - ExploreHandler

@interface ExploreHandler ()
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, copy) NSString *cacheDirectory;
@property (nonatomic, copy) NSString *plcServerURL;
@property (nonatomic, assign) NSTimeInterval didTTL;
@property (nonatomic, assign) NSTimeInterval plcTTL;
@property (nonatomic, assign) NSTimeInterval accountTTL;
@property (nonatomic, strong) ExploreCache *cache;
/*! Controller - set once at init, never changed. Owner (singleton) outlives controller. */
@property (nonatomic, strong) PDSController *controller;

- (NSString *)formatAccountsAsJSON:(NSArray<PDSDatabaseAccount *> *)accounts;
@end

@implementation ExploreHandler

+ (instancetype)sharedHandler {
    static ExploreHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ExploreHandler alloc] init];
    });
    return instance;
}

- (NSString *)didFromURI:(NSString *)uri {
    if (!uri) return nil;
    if ([uri hasPrefix:@"at://"]) {
        NSString *path = [uri substringFromIndex:5];
        NSArray *components = [path componentsSeparatedByString:@"/"];
        if (components.count > 0) {
            return components[0];
        }
    }
    return nil;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [ExploreCache sharedCache];
        _enabled = YES;
        _cacheDirectory = @"/tmp/pds-explore-cache";
        _plcServerURL = [PDSConfiguration sharedConfiguration].plcURL ?: @"http://localhost:2582";
        _didTTL = 3600;
        _plcTTL = 86400;
        _accountTTL = 300;
        [self loadConfiguration];
    }
    return self;
}

- (void)setController:(PDSController *)controller {
    _controller = controller;
}

- (void)loadConfiguration {
    NSString *configPath = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"yaml"];
    if (!configPath) {
        NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
        configPath = [[appSupport stringByAppendingPathComponent:@"ATProtoPDS"] stringByAppendingPathComponent:@"config.yaml"];
    }
    
    if (configPath) {
        NSString *content = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
        if (content) {
            [self parseConfig:content];
        }
    }
}

- (void)parseConfig:(NSString *)content {
    NSArray *lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    BOOL inExploreSection = NO;
    NSString *(^valueForLine)(NSString *) = ^NSString *(NSString *line) {
        NSRange colonRange = [line rangeOfString:@":"];
        if (colonRange.location == NSNotFound) {
            return nil;
        }
        NSString *value = [line substringFromIndex:colonRange.location + 1];
        return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    };
    
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([trimmed hasPrefix:@"explore:"]) {
            inExploreSection = YES;
            continue;
        }
        
        if (inExploreSection && [trimmed hasPrefix:@"#"]) {
            continue;
        }
        
        if (inExploreSection && trimmed.length > 0 && ![line hasPrefix:@"  "] && ![line hasPrefix:@"\t"]) {
            inExploreSection = NO;
        }
        
        if (!inExploreSection) continue;
        
        if ([trimmed containsString:@"enabled:"]) {
            NSString *value = valueForLine(trimmed);
            self.enabled = value.boolValue;
        }
        else if ([trimmed containsString:@"plc_server:"]) {
            self.plcServerURL = valueForLine(trimmed);
        }
        else if ([trimmed containsString:@"cache_directory:"]) {
            NSString *value = valueForLine(trimmed);
            self.cacheDirectory = [value stringByExpandingTildeInPath];
        }
        else if ([trimmed containsString:@"did_ttl_seconds:"]) {
            self.didTTL = valueForLine(trimmed).doubleValue;
        }
        else if ([trimmed containsString:@"plc_log_ttl_seconds:"]) {
            self.plcTTL = valueForLine(trimmed).doubleValue;
        }
        else if ([trimmed containsString:@"account_list_ttl_seconds:"]) {
            self.accountTTL = valueForLine(trimmed).doubleValue;
        }
    }
}

- (BOOL)canHandleRequest:(HttpRequest *)request {
    return self.enabled;
}

- (NSString *)assetsPath {
    NSString *assetsPath = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSBundle *bundle = [NSBundle mainBundle];
    assetsPath = [bundle pathForResource:@"Explore/Assets" ofType:@""];
    
    if (!assetsPath && self.controller.dataDirectory) {
        NSString *dataDir = self.controller.dataDirectory;
        if (![dataDir isAbsolutePath]) {
            dataDir = [[fm currentDirectoryPath] stringByAppendingPathComponent:dataDir];
        }
        dataDir = [dataDir stringByResolvingSymlinksInPath];
        
        NSString *exploreInData = [dataDir stringByAppendingPathComponent:@"Explore/Assets"];
        if ([fm fileExistsAtPath:exploreInData]) {
            assetsPath = exploreInData;
        } else {
            NSString *siblingAssets = [[dataDir stringByAppendingPathComponent:@".."] stringByAppendingPathComponent:@"Explore/Assets"];
            siblingAssets = [siblingAssets stringByResolvingSymlinksInPath];
            if ([fm fileExistsAtPath:siblingAssets]) {
                assetsPath = siblingAssets;
            }
        }
    }
    
    if (!assetsPath) {
        NSString *cwd = [fm currentDirectoryPath];
        NSString *projectAssets = [cwd stringByAppendingPathComponent:@"Garazyk/Sources/App/Explore/Assets"];
        if ([fm fileExistsAtPath:projectAssets]) {
            assetsPath = projectAssets;
        } else {
            NSString *dataAssets = [cwd stringByAppendingPathComponent:@"data/Explore/Assets"];
            if ([fm fileExistsAtPath:dataAssets]) {
                assetsPath = dataAssets;
            }
        }
    }
    
    PDS_LOG_EXPLORE_DEBUG(@"ExploreHandler assetsPath: %@", assetsPath ?: @"(nil)");
    return assetsPath;
}

- (NSString *)staticFilePath:(NSString *)subpath {
    NSString *assets = [self assetsPath];
    if (!assets) return nil;
    return [assets stringByAppendingPathComponent:subpath];
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    PDS_LOG_DEBUG_C(PDSLogComponentExplore, @"ExploreHandler handleRequest: %@", path);

    if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) {
        [self serveIndex:response];
    }
    else if ([path hasPrefix:@"/css/"]) {
        NSString *subpath = [path substringFromIndex:1];
        NSString *contentType = @"text/css; charset=utf-8";
        if ([path hasSuffix:@".woff2"]) contentType = @"font/woff2";
        else if ([path hasSuffix:@".woff"]) contentType = @"font/woff";
        [self serveStaticFile:subpath response:response contentType:contentType];
    }
    else if ([path hasPrefix:@"/js/"]) {
        NSString *subpath = [path substringFromIndex:1];
        [self serveStaticFile:subpath response:response contentType:@"application/javascript; charset=utf-8"];
    }
    else if ([path hasPrefix:@"/api/pds/"]) {
        NSString *endpoint = request.pathParameters[@"endpoint"] ?: [self apiEndpointForPath:request.path];
        [self handleApiRequest:request response:response endpoint:endpoint];
    }
    else if ([path hasPrefix:@"/vendor/"]) {
        [self serveVendor:request response:response];
    }
    else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Not Found", @"path": path}];
    }
}

#pragma mark - Static Files

- (void)serveIndex:(HttpResponse *)response {
    NSString *indexPath = [self staticFilePath:@"index.html"];
    
    if (!indexPath) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Assets path not configured"}];
        return;
    }
    
    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:indexPath encoding:NSUTF8StringEncoding error:&error];
    
    if (error || !html) {
        NSString *fallbackHtml = @"<!DOCTYPE html>"
        "<html lang=\"en\">"
        "<head>"
        "    <meta charset=\"UTF-8\">"
        "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
        "    <title>ATProto PDS Explorer</title>"
        "</head>"
        "<body>"
        "    <h1>ATProto PDS Explorer</h1>"
        "    <p>Error: Could not load index.html</p>"
        "</body>"
        "</html>";
        html = fallbackHtml;
    }
    
    response.statusCode = 200;
    response.contentType = @"text/html; charset=utf-8";
    response.keepAlive = NO;
    [response setBody:[html dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)serveStaticFile:(NSString *)subpath response:(HttpResponse *)response contentType:(NSString *)contentType {
    NSString *filePath = [self staticFilePath:subpath];
    if (!filePath) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Assets path not configured"}];
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"File not found", @"path": subpath}];
        return;
    }
    
    response.statusCode = 200;
    response.contentType = contentType;
    response.keepAlive = NO;
    [response setBodyData:data];
}

- (void)serveVendor:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    
    NSString *relativePath;
    if ([path hasPrefix:@"/vendor/"]) {
        relativePath = [path substringFromIndex:[@"/vendor/" length]];
    } else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Invalid vendor path", @"path": path}];
        return;
    }
    
    NSString *vendorPath = [self staticFilePath:[NSString stringWithFormat:@"vendor/%@", relativePath]];
    
    if (!vendorPath) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Assets path not configured"}];
        return;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:vendorPath];
    
    if (!data) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Vendor file not found", @"path": path}];
        return;
    }
    
    NSString *extension = [path pathExtension].lowercaseString;
    NSString *contentType;
    if ([extension isEqualToString:@"js"]) {
        contentType = @"application/javascript; charset=utf-8";
    } else if ([extension isEqualToString:@"css"]) {
        contentType = @"text/css; charset=utf-8";
    } else if ([extension isEqualToString:@"json"]) {
        contentType = @"application/json; charset=utf-8";
    } else {
        contentType = @"application/octet-stream";
    }
    
    response.statusCode = 200;
    response.contentType = contentType;
    response.keepAlive = NO;
    [response setBodyData:data];
}
#pragma mark - API Endpoints

- (void)handleApiRequest:(HttpRequest *)request response:(HttpResponse *)response endpoint:(NSString *)endpoint {
    PDS_LOG_DEBUG_C(PDSLogComponentExplore, @"handleApiRequest: path=%@, endpoint=%@", request.path, endpoint);
    
    // Robust query parsing using NSURLComponents
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSString *urlString = [NSString stringWithFormat:@"http://localhost%@", request.path];
    if (request.queryString) {
        urlString = [urlString stringByAppendingFormat:@"?%@", request.queryString];
    }
    
    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name) {
            params[item.name] = item.value ?: @"";
        }
    }

    
    response.statusCode = 200;
    response.contentType = @"application/json; charset=utf-8";
    
    if ([endpoint isEqualToString:@"lookup"]) {
        [self handleApiLookup:params response:response];
    }
    else if ([endpoint isEqualToString:@"did"]) {
        [self handleApiDid:params response:response];
    }
    else if ([endpoint isEqualToString:@"plc-log"]) {
        [self handleApiPlcLog:params response:response];
    }
    else if ([endpoint isEqualToString:@"accounts"]) {
        [self handleApiAccounts:params response:response];
    }
    else if ([endpoint isEqualToString:@"describe"]) {
        [self handleApiDescribe:params response:response];
    }
    else if ([endpoint isEqualToString:@"records"]) {
        [self handleApiRecords:params response:response];
    }
    else if ([endpoint isEqualToString:@"record"]) {
        [self handleApiRecord:params response:response];
    }
    else if ([endpoint isEqualToString:@"blob"]) {
        [self handleApiBlob:params response:response];
    }
    else if ([endpoint isEqualToString:@"cid-decode"]) {
        [self handleApiCidDecode:params response:response];
    }
    else if ([endpoint isEqualToString:@"repositories"]) {
        [self handleApiRepositories:params response:response];
    }
    else if ([endpoint isEqualToString:@"collections"]) {
        [self handleApiCollections:params response:response];
    }
    else if ([endpoint isEqualToString:@"account-details"]) {
        [self handleApiAccountDetails:params response:response];
    }
    else if ([endpoint isEqualToString:@"account-records"]) {
        [self handleApiAccountRecords:params response:response];
    }
    else if ([endpoint isEqualToString:@"record-details"]) {
        [self handleApiRecordDetails:params response:response];
    }
    else if ([endpoint isEqualToString:@"cid-info"]) {
        [self handleApiCidInfo:params response:response];
    }
    else if ([endpoint isEqualToString:@"create-record"]) {
        [self handleApiCreateRecord:params response:response];
    }
    else if ([endpoint isEqualToString:@"debug-paths"]) {
        NSString *dbPath = nil;
        if (self.controller.dataDirectory) {
            dbPath = [self.controller.dataDirectory stringByAppendingPathComponent:@"service/service.db"];
        } else {
            NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
            dbPath = [cwd stringByAppendingPathComponent:@"data/service/service.db"];
        }
        BOOL dbExists = [[NSFileManager defaultManager] fileExistsAtPath:dbPath];
        [response setJsonBody:@{
            @"dataDirectory": self.controller.dataDirectory ?: @"",
            @"dbPath": dbPath ?: @"",
            @"dbExists": @(dbExists),
            @"assetsPath": [self assetsPath] ?: @"",
            @"cssPath": [self staticFilePath:@"css/style.css"] ?: @"",
            @"jsPath": [self staticFilePath:@"js/ui.js"] ?: @""
        }];
    }
    else if ([endpoint isEqualToString:@"docs"]) {
        [self handleApiDocs:params response:response];
    }
    else if ([endpoint isEqualToString:@"openapi.yaml"] || [endpoint isEqualToString:@"openapi.json"]) {
        PDS_LOG_DEBUG_C(PDSLogComponentExplore, @"[ExploreHandler] OpenAPI spec request received");
        response.statusCode = HttpStatusOK;
        [self handleApiOpenapiSpec:params response:response];
    }
    else if ([endpoint isEqualToString:@"feed-posts"]) {
        [self handleApiFeedPosts:params response:response];
    }
    else if ([endpoint isEqualToString:@"feed-likes"]) {
        [self handleApiFeedLikes:params response:response];
    }
    else if ([endpoint isEqualToString:@"feed-reposts"]) {
        [self handleApiFeedReposts:params response:response];
    }
    else if ([endpoint isEqualToString:@"graph-follows"]) {
        [self handleApiFollows:params response:response];
    }
    else if ([endpoint isEqualToString:@"actor-profile"]) {
        [self handleApiActorProfile:params response:response];
    }
    else {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{@"error": @"Unknown endpoint", @"endpoint": endpoint}];
    }
}

- (NSString *)apiEndpointForPath:(NSString *)path {
    // Robust path parsing
    if (!path) return @"";
    
    // Check prefix first
    NSString *prefix = @"/api/pds/";
    if ([path hasPrefix:prefix]) {
        NSString *suffix = [path substringFromIndex:prefix.length];
        // Split by '/' and take first component
        NSArray *components = [suffix componentsSeparatedByString:@"/"];
        return components.firstObject ?: @"";
    }
    return @"";
}

- (void)handleApiRepositories:(NSDictionary *)params response:(HttpResponse *)response {
    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *accounts = [self.controller getAllAccountsWithError:&error];

    if (!accounts) {
        [response setJsonBody:@{
            @"repositories": @[],
            @"error": error.localizedDescription ?: @"Failed to get accounts"
        }];
        return;
    }

    NSMutableArray *accountData = [NSMutableArray array];
    for (PDSDatabaseAccount *account in accounts) {
        [accountData addObject:@{
            @"did": account.did ?: @"",
            @"handle": account.handle ?: @"",
            @"email": account.email ?: [NSNull null],
            @"createdAt": @(account.createdAt),
            @"updatedAt": @(account.updatedAt)
        }];
    }

    [response setJsonBody:@{
        @"repositories": accountData,
        @"count": @(accountData.count)
    }];
}

- (void)handleApiCreateRecord:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *collection = params[@"collection"];
    NSString *valueJson = params[@"value"];
    NSString *rkey = [params[@"rkey"] isKindOfClass:[NSString class]]
        ? [(NSString *)params[@"rkey"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : nil;

    if (!did || !collection || !valueJson) {
        [response setJsonBody:@{
            @"error": @"Missing required parameters",
            @"required": @[@"did", @"collection", @"value"]
        }];
        return;
    }
    
    if (rkey.length == 0) {
        if ([collection isEqualToString:@"app.bsky.feed.post"]) {
            // app.bsky.feed.post has key type "tid"; generate a proper rkey when omitted.
            rkey = [TID tid].stringValue;
        } else {
            [response setJsonBody:@{
                @"error": @"Missing required parameters",
                @"required": @[@"did", @"collection", @"rkey", @"value"],
                @"note": @"rkey is required for non-post collections. app.bsky.feed.post auto-generates a TID rkey when omitted."
            }];
            return;
        }
    }

    NSError *jsonError = nil;
    NSData *valueData = [valueJson dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *value = [NSJSONSerialization JSONObjectWithData:valueData options:0 error:&jsonError];

    if (!value || jsonError) {
        [response setJsonBody:@{
            @"error": @"Invalid JSON in value parameter",
            @"details": jsonError.localizedDescription ?: @"Unknown error"
        }];
        return;
    }

    NSError *error = nil;
    if ([self.controller putRecord:collection rkey:rkey value:value forDid:did validationMode:PDSValidationModeRequired error:&error]) {
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSDictionary *record = [self.controller getRecord:uri forDid:did error:nil];
        
        [response setJsonBody:@{
            @"uri": uri,
            @"did": did,
            @"collection": collection,
            @"rkey": rkey,
            @"cid": record[@"cid"] ?: @"",
            @"value": value,
            @"createdAt": record[@"createdAt"] ?: [[NSDate date] description]
        }];
    } else {
        [response setJsonBody:@{
            @"error": error.localizedDescription ?: @"Failed to create record",
            @"did": did
        }];
    }
}

- (NSString *)generateCIDForValue:(NSDictionary *)value {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (!jsonData) return nil;

    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(jsonData.bytes, (CC_LONG)jsonData.length, hash);

    NSMutableData *multihash = [NSMutableData data];
    [multihash appendBytes:(uint8_t[]){0x12, 0x20} length:2];
    [multihash appendBytes:hash length:CC_SHA256_DIGEST_LENGTH];

    NSMutableData *cidData = [NSMutableData data];
    [cidData appendBytes:(uint8_t[]){0x01, 0x71} length:2];
    [cidData appendData:multihash];

    return [NSString stringWithFormat:@"b%@", [self base32Encode:cidData]];
}

- (NSString *)base32Encode:(NSData *)data {
    static const char *alphabet = "abcdefghijklmnopqrstuvwxyz234567";
    NSMutableString *result = [NSMutableString string];
    NSUInteger length = data.length;
    NSUInteger i = 0;

    while (i < length) {
        uint8_t byte = ((uint8_t *)data.bytes)[i++];
        [result appendFormat:@"%c", alphabet[byte >> 3]];
        uint8_t nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((byte & 0x07) << 2) | (nextByte >> 6)]];
        if (i >= length + 1) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 1) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[((nextByte & 0x0F) << 1) | (nextByte >> 7)]];
        if (i >= length) break;
        [result appendFormat:@"%c", alphabet[(nextByte >> 2) & 0x1F]];
        if (i >= length) break;
        nextByte = (i < length) ? ((uint8_t *)data.bytes)[i++] : 0;
        [result appendFormat:@"%c", alphabet[nextByte & 0x1F]];
    }

    return result;
}

- (void)handleApiAccountDetails:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *account = [self.controller getAccountForDid:did error:&error];

    if (!account) {
        [response setJsonBody:@{@"error": @"Account not found", @"did": did}];
        return;
    }

    [response setJsonBody:account];
}

- (void)handleApiCollections:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *stats = [self.controller getRepoStatsForDid:did error:&error];

    if (stats) {
        [response setJsonBody:stats];
    } else {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to get collections", @"did": did}];
    }
}

- (void)handleApiDescribe:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *repoDesc = [self.controller describeRepo:did error:&error];
    if (repoDesc) {
        [response setJsonBody:repoDesc];
    } else {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to describe repository", @"did": did}];
    }
}

- (void)handleApiAccountRecords:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSString *collection = params[@"collection"];
    NSString *limitStr = params[@"limit"] ?: @"50";

    NSUInteger limit = [limitStr integerValue];
    if (limit > 200) limit = 200;

    NSError *error = nil;
    NSArray *records = [self.controller listRecords:collection forDid:did limit:limit cursor:nil error:&error];

    if (records) {
        [response setJsonBody:@{
            @"did": did,
            @"collection": collection ?: [NSNull null],
            @"records": records,
            @"count": @(records.count)
        }];
    } else {
        [response setJsonBody:@{
            @"did": did,
            @"collection": collection ?: [NSNull null],
            @"records": @[],
            @"error": error.localizedDescription ?: @"Failed to fetch records"
        }];
    }
}

- (void)handleApiRecordDetails:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *uri = params[@"uri"];
    if (!uri) {
        [response setJsonBody:@{@"error": @"Missing uri parameter"}];
        return;
    }

    // Extract DID from URI safely
    NSString *did = [self didFromURI:uri];

    if (!did) {
        [response setJsonBody:@{@"error": @"Invalid URI format"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *record = [self.controller getRecord:uri forDid:did error:&error];
    
    if (record) {
        [response setJsonBody:record];
    } else {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Record not found", @"uri": uri}];
    }
}

- (void)handleApiCidInfo:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Missing cid parameter"}];
        return;
    }

    NSDictionary *cidInfo = [self decodeCid:cid];

    if ([cidInfo[@"error"] length] > 0) {
        [response setJsonBody:cidInfo];
        return;
    }

    // Add some additional formatting for display
    NSMutableDictionary *formattedInfo = [cidInfo mutableCopy];
    formattedInfo[@"formatted"] = @{
        @"multibasePrefix": [NSString stringWithFormat:@"%@ (base%d)", cidInfo[@"multibase"],
                           [cidInfo[@"multibase"] isEqualToString:@"b"] ? 32 :
                           [cidInfo[@"multibase"] isEqualToString:@"z"] ? 58 : 0],
        @"codecDescription": [self codecDescriptionForCode:cidInfo[@"codec"] ?: @0],
        @"hashDescription": [self hashDescriptionForCode:cidInfo[@"hashAlgorithm"] ?: @0]
    };

    [response setJsonBody:formattedInfo];
}

- (NSString *)codecDescriptionForCode:(id)code {
    unsigned long long codecCode = 0;
    if ([code isKindOfClass:[NSNumber class]]) {
        codecCode = [code unsignedLongLongValue];
    } else if ([code isKindOfClass:[NSString class]]) {
        // Parse hex string like "0x71"
        NSString *hexStr = (NSString *)code;
        if ([hexStr hasPrefix:@"0x"]) {
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            [scanner scanHexLongLong:&codecCode];
        }
    }
    switch (codecCode) {
        case 0x55: return @"Raw binary data";
        case 0x70: return @"MerkleDAG protobuf";
        case 0x71: return @"MerkleDAG CBOR";
        case 0x72: return @"MerkleDAG JSON";
        case 0x129: return @"DAG-JSON";
        default: return @"Unknown codec";
    }
}

- (NSString *)hashDescriptionForCode:(id)code {
    unsigned long long hashCode = 0;
    if ([code isKindOfClass:[NSNumber class]]) {
        hashCode = [code unsignedLongLongValue];
    } else if ([code isKindOfClass:[NSString class]]) {
        // Parse hex string like "0x12"
        NSString *hexStr = (NSString *)code;
        if ([hexStr hasPrefix:@"0x"]) {
            NSScanner *scanner = [NSScanner scannerWithString:hexStr];
            [scanner scanHexLongLong:&hashCode];
        }
    }
    switch (hashCode) {
        case 0x11: return @"SHA-1";
        case 0x12: return @"SHA-256 (recommended)";
        case 0x13: return @"SHA-512";
        case 0xb220: return @"Blake2b-256";
        case 0xb240: return @"Blake2b-512";
        default: return @"Unknown hash algorithm";
    }
}

- (NSDictionary *)parseQueryString:(NSString *)query {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        if (kv.count == 2) {
            NSString *key = [kv[0] stringByRemovingPercentEncoding];
            NSString *value = [kv[1] stringByRemovingPercentEncoding];
            params[key] = value;
        }
    }
    return [params copy];
}

#pragma mark - API Handlers

- (void)handleApiLookup:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *handle = params[@"handle"];
    
    if (did) {
        NSString *resolvedDid = [self resolveHandleFromDid:did];
        if (resolvedDid) {
            [response setJsonBody:@{@"did": resolvedDid, @"handle": handle ?: resolvedDid}];
        } else {
            [response setJsonBody:@{@"error": @"DID not found"}];
        }
    }
    else if (handle) {
        NSString *resolvedDid = [self resolveHandleToDid:handle];
        if (resolvedDid) {
            [response setJsonBody:@{@"did": resolvedDid, @"handle": handle}];
        } else {
            [response setJsonBody:@{@"error": @"Handle not found"}];
        }
    }
    else {
        [response setJsonBody:@{@"error": @"Missing did or handle parameter"}];
    }
}

- (void)handleApiDid:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }
    
    NSString *cached = [self.cache getDidDocument:did];
    if (cached) {
        NSData *data = [cached dataUsingEncoding:NSUTF8StringEncoding];
        [response setBody:data];
        return;
    }
    
    NSString *doc = [self fetchDidDocument:did];
    if (doc) {
        [self.cache setDidDocument:did value:doc];
        [response setBody:[doc dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"error": @"Failed to fetch DID document"}];
    }
}

- (void)handleApiPlcLog:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }
    
    NSString *cached = [self.cache getPlcLog:did];
    if (cached) {
        NSData *data = [cached dataUsingEncoding:NSUTF8StringEncoding];
        [response setBody:data];
        return;
    }
    
    NSString *log = [self fetchPlcLog:did];
    if (log) {
        [self.cache setPlcLog:did value:log];
        [response setBody:[log dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"error": @"Failed to fetch PLC log"}];
    }
}

- (void)handleApiAccounts:(NSDictionary *)params response:(HttpResponse *)response {
    // Account listings should reflect recent CLI/admin changes immediately.
    // Avoid server-side response caching for this endpoint.
    NSString *accounts = [self fetchAccountList];
    if (accounts) {
        [response setBody:[accounts dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
        [response setJsonBody:@{@"accounts": @[]}];
    }
}

- (void)handleApiRecords:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *collection = params[@"collection"];
    NSString *did = params[@"did"];
    NSString *limitStr = params[@"limit"] ?: @"20";
    NSString *cursor = params[@"cursor"];
    
    if (!collection) {
        [response setJsonBody:@{@"error": @"Missing collection parameter"}];
        return;
    }
    
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }
    
    NSUInteger limit = [limitStr integerValue];
    NSError *error = nil;
    NSArray *records = [self.controller listRecords:collection forDid:did limit:limit cursor:cursor error:&error];
    
    if (records) {
        [response setJsonBody:@{
            @"records": records,
            @"cursor": records.lastObject[@"uri"] ?: [NSNull null]
        }];
    } else {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to fetch records", @"records": @[]}];
    }
}

- (void)handleApiRecord:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *uri = params[@"uri"];
    if (!uri) {
        [response setJsonBody:@{@"error": @"Missing uri parameter"}];
        return;
    }

    // Extract DID from URI safely
    NSString *did = [self didFromURI:uri];

    if (!did) {
        [response setJsonBody:@{@"error": @"Invalid URI format"}];
        return;
    }

    NSError *error = nil;
    NSDictionary *record = [self.controller getRecord:uri forDid:did error:&error];
    
    if (record) {
        [response setJsonBody:record];
    } else {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Record not found", @"uri": uri}];
    }
}

- (void)handleApiBlob:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Missing cid parameter"}];
        return;
    }
    
    NSString *mimeType = nil;
    NSData *blobData = [self fetchBlob:cid mimeType:&mimeType];
    if (blobData) {
        response.statusCode = 200;
        [response setHeader:mimeType ?: @"application/octet-stream" forKey:@"Content-Type"];
        [response setHeader:[NSString stringWithFormat:@"attachment; filename=\"%@\"", cid] forKey:@"Content-Disposition"];
        [response setBody:blobData];
    } else {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"Blob not found"}];
    }
}

- (void)handleApiCidDecode:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *cid = params[@"cid"];
    if (!cid) {
        [response setJsonBody:@{@"error": @"Missing cid parameter"}];
        return;
    }
    
    NSDictionary *decoded = [self decodeCid:cid];
    [response setJsonBody:decoded];
}

#pragma mark - Feed View Endpoints

- (void)handleApiFeedPosts:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *limitStr = params[@"limit"] ?: @"20";
    NSString *cursor = params[@"cursor"];
    NSString *filter = params[@"filter"] ?: @"author";

    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSUInteger limit = [limitStr integerValue];
    if (limit > 100) limit = 100;

    NSError *error = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.feed.post" forDid:did limit:limit cursor:cursor error:&error];

    if (!records) {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to fetch posts", @"posts": @[]}];
        return;
    }

    NSMutableArray *posts = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSDictionary *postRecord = record[@"value"];
        if (!postRecord) continue;

        NSString *authorHandle = [self resolveDidToHandle:did];

        NSDictionary *post = @{
            @"uri": record[@"uri"] ?: @"",
            @"cid": record[@"cid"] ?: @"",
            @"author": @{
                @"did": did,
                @"handle": authorHandle ?: did,
                @"displayName": [self getDisplayNameForDid:did] ?: @"",
                @"avatar": [self getAvatarForDid:did] ?: @""
            },
            @"record": @{
                @"text": postRecord[@"text"] ?: @"",
                @"createdAt": postRecord[@"createdAt"] ?: @"",
                @"langs": postRecord[@"langs"] ?: @[],
                @"reply": postRecord[@"reply"] ?: [NSNull null],
                @"embed": postRecord[@"embed"] ?: [NSNull null]
            },
            @"replyCount": @0,
            @"repostCount": @0,
            @"likeCount": @0,
            @"quoteCount": @0,
            @"indexedAt": record[@"createdAt"] ?: @""
        };
        [posts addObject:post];
    }

    [response setJsonBody:@{
        @"posts": posts,
        @"cursor": records.lastObject[@"uri"] ?: [NSNull null],
        @"count": @(posts.count)
    }];
}

- (void)handleApiFeedLikes:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *limitStr = params[@"limit"] ?: @"20";
    NSString *cursor = params[@"cursor"];

    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSUInteger limit = [limitStr integerValue];
    if (limit > 100) limit = 100;

    NSError *error = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.feed.like" forDid:did limit:limit cursor:cursor error:&error];

    if (!records) {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to fetch likes", @"likes": @[]}];
        return;
    }

    NSMutableArray *likes = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSDictionary *likeRecord = record[@"value"];
        if (!likeRecord) continue;

        NSDictionary *subject = likeRecord[@"subject"];
        if (!subject) continue;

        NSString *subjectUri = subject[@"uri"] ?: @"";
        NSString *subjectCid = subject[@"cid"] ?: @"";

        NSString *subjectDid = [self didFromURI:subjectUri] ?: @"";
        NSString *subjectHandle = [self resolveDidToHandle:subjectDid];

        NSDictionary *like = @{
            @"uri": record[@"uri"] ?: @"",
            @"cid": record[@"cid"] ?: @"",
            @"actor": @{
                @"did": did,
                @"handle": [self resolveDidToHandle:did] ?: did,
                @"displayName": [self getDisplayNameForDid:did] ?: @"",
                @"avatar": [self getAvatarForDid:did] ?: @""
            },
            @"subject": @{
                @"uri": subjectUri,
                @"cid": subjectCid,
                @"author": @{
                    @"did": subjectDid,
                    @"handle": subjectHandle ?: subjectDid,
                    @"displayName": [self getDisplayNameForDid:subjectDid] ?: @"",
                    @"avatar": [self getAvatarForDid:subjectDid] ?: @""
                }
            },
            @"createdAt": likeRecord[@"createdAt"] ?: record[@"createdAt"] ?: @""
        };
        [likes addObject:like];
    }

    [response setJsonBody:@{
        @"likes": likes,
        @"cursor": records.lastObject[@"uri"] ?: [NSNull null],
        @"count": @(likes.count)
    }];
}

- (void)handleApiFeedReposts:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *limitStr = params[@"limit"] ?: @"20";
    NSString *cursor = params[@"cursor"];

    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSUInteger limit = [limitStr integerValue];
    if (limit > 100) limit = 100;

    NSError *error = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.feed.repost" forDid:did limit:limit cursor:cursor error:&error];

    if (!records) {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to fetch reposts", @"reposts": @[]}];
        return;
    }

    NSMutableArray *reposts = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSDictionary *repostRecord = record[@"value"];
        if (!repostRecord) continue;

        NSDictionary *subject = repostRecord[@"subject"];
        if (!subject) continue;

        NSString *subjectUri = subject[@"uri"] ?: @"";
        NSString *subjectCid = subject[@"cid"] ?: @"";

        NSString *subjectDid = [self didFromURI:subjectUri] ?: @"";
        NSString *subjectHandle = [self resolveDidToHandle:subjectDid];

        NSDictionary *repost = @{
            @"uri": record[@"uri"] ?: @"",
            @"cid": record[@"cid"] ?: @"",
            @"author": @{
                @"did": did,
                @"handle": [self resolveDidToHandle:did] ?: did,
                @"displayName": [self getDisplayNameForDid:did] ?: @"",
                @"avatar": [self getAvatarForDid:did] ?: @""
            },
            @"subject": @{
                @"uri": subjectUri,
                @"cid": subjectCid,
                @"author": @{
                    @"did": subjectDid,
                    @"handle": subjectHandle ?: subjectDid,
                    @"displayName": [self getDisplayNameForDid:subjectDid] ?: @"",
                    @"avatar": [self getAvatarForDid:subjectDid] ?: @""
                }
            },
            @"createdAt": repostRecord[@"createdAt"] ?: record[@"createdAt"] ?: @""
        };
        [reposts addObject:repost];
    }

    [response setJsonBody:@{
        @"reposts": reposts,
        @"cursor": records.lastObject[@"uri"] ?: [NSNull null],
        @"count": @(reposts.count)
    }];
}

- (void)handleApiFollows:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    NSString *direction = params[@"direction"] ?: @"following";
    NSString *limitStr = params[@"limit"] ?: @"50";

    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSUInteger limit = [limitStr integerValue];
    if (limit > 200) limit = 200;

    NSError *error = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.graph.follow" forDid:did limit:limit cursor:nil error:&error];

    if (!records) {
        [response setJsonBody:@{@"error": error.localizedDescription ?: @"Failed to fetch follows", @"actors": @[]}];
        return;
    }

    NSMutableArray *actors = [NSMutableArray array];
    for (NSDictionary *record in records) {
        NSDictionary *followRecord = record[@"value"];
        if (!followRecord) continue;

        NSString *subjectDid = followRecord[@"subject"] ?: @"";
        NSString *subjectHandle = [self resolveDidToHandle:subjectDid];

        NSDictionary *actor = @{
            @"did": subjectDid,
            @"handle": subjectHandle ?: subjectDid,
            @"displayName": [self getDisplayNameForDid:subjectDid] ?: @"",
            @"avatar": [self getAvatarForDid:subjectDid] ?: @"",
            @"createdAt": followRecord[@"createdAt"] ?: record[@"createdAt"] ?: @""
        };
        [actors addObject:actor];
    }

    [response setJsonBody:@{
        @"actors": actors,
        @"direction": direction,
        @"count": @(actors.count)
    }];
}

- (void)handleApiActorProfile:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *did = params[@"did"];
    if (!did) {
        [response setJsonBody:@{@"error": @"Missing did parameter"}];
        return;
    }

    NSError *error = nil;
    NSArray *profileRecords = [self.controller listRecords:@"app.bsky.actor.profile" forDid:did limit:1 cursor:nil error:&error];

    NSString *handle = [self resolveDidToHandle:did];
    NSString *displayName = @"";
    NSString *avatar = @"";
    NSString *banner = @"";
    NSString *bio = @"";
    NSNumber *followersCount = @0;
    NSNumber *followsCount = @0;
    NSNumber *postsCount = @0;

    if (profileRecords.count > 0) {
        NSDictionary *profileRecord = profileRecords.firstObject[@"value"];
        if (profileRecord) {
            displayName = profileRecord[@"displayName"] ?: @"";
            bio = profileRecord[@"description"] ?: @"";
            avatar = profileRecord[@"avatar"] ?: @"";
            banner = profileRecord[@"banner"] ?: @"";
        }
    }

    NSArray *followingRecords = [self.controller listRecords:@"app.bsky.graph.follow" forDid:did limit:1000 cursor:nil error:nil];
    followsCount = @(followingRecords.count);

    NSArray *postRecords = [self.controller listRecords:@"app.bsky.feed.post" forDid:did limit:1000 cursor:nil error:nil];
    postsCount = @(postRecords.count);

    [response setJsonBody:@{
        @"did": did,
        @"handle": handle ?: did,
        @"displayName": displayName,
        @"avatar": avatar,
        @"banner": banner,
        @"description": bio,
        @"followersCount": followersCount,
        @"followsCount": followsCount,
        @"postsCount": postsCount,
        @"createdAt": [self getAccountCreatedAt:did]
    }];
}

- (NSString *)resolveDidToHandle:(NSString *)did {
    return did;
}

- (NSString *)getDisplayNameForDid:(NSString *)did {
    NSError *error = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.actor.profile" forDid:did limit:1 cursor:nil error:&error];
    if (records.count > 0) {
        NSDictionary *profile = records.firstObject[@"value"];
        return profile[@"displayName"];
    }
    return nil;
}

- (NSString *)getAvatarForDid:(NSString *)did {
    NSError *error = nil;
    NSArray *records = [self.controller listRecords:@"app.bsky.actor.profile" forDid:did limit:1 cursor:nil error:&error];
    if (records.count > 0) {
        NSDictionary *profile = records.firstObject[@"value"];
        return profile[@"avatar"];
    }
    return nil;
}

- (NSString *)getAccountCreatedAt:(NSString *)did {
    NSDictionary *account = [self.controller getAccountForDid:did error:nil];
    if (account) {
        NSNumber *createdAt = account[@"createdAt"];
        if (createdAt) {
            return [[NSDate dateWithTimeIntervalSince1970:[createdAt doubleValue]] description];
        }
    }
    return @"";
}

#pragma mark - Data Fetching

- (NSString *)fetchDidDocument:(NSString *)did {
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", self.plcServerURL, did]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10.0; // 10 second timeout
    
#if defined(__APPLE__)
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *result = nil;
    __block NSError *networkError = nil;
    __block NSInteger statusCode = 0;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (res) {
            statusCode = ((NSHTTPURLResponse *)res).statusCode;
        }
        if (err) {
            networkError = err;
        } else if (data) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(sem, timeout);
    
    BOOL isValidResponse = (waitResult == 0) && !networkError && (statusCode == 200) && result && [result hasPrefix:@"{"] && [result hasSuffix:@"}"] && ![result containsString:@"DID not registered"];
    
    if (isValidResponse) {
        [self.cache setDidDocument:did value:result];
        return result;
    }
#else
    // GNUstep: Use NSURLConnection (synchronous)
    __block NSString *result = nil;
    __block NSError *networkError = nil;
    __block NSInteger statusCode = 0;
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLResponse *response = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&response error:&networkError];
        
        if (response && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (data) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        
        dispatch_semaphore_signal(sem);
    });
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC));
    dispatch_semaphore_wait(sem, timeout);
    
    BOOL isValidResponse = !networkError && (statusCode == 200) && result && [result hasPrefix:@"{"] && [result hasSuffix:@"}"] && ![result containsString:@"DID not registered"];
    
    if (isValidResponse) {
        [self.cache setDidDocument:did value:result];
        return result;
    }
    
    long waitResult = 0; // For the checks below
#endif
    
    // Fallback: Check if this is a local account
    NSError *error = nil;
    NSArray *accounts = nil;
    
    // Try via controller first
    if (self.controller) {
        accounts = [self.controller getAllAccountsWithError:&error];
    }
    
    // Fallback to manual DB if controller failed or returned no accounts (and we suspect they exist)
    if (!accounts || error || accounts.count == 0) {
        // Try multiple possible database locations (copied from fetchAccountList)
        NSString *dataDir = self.controller.dataDirectory;
        if (!dataDir) dataDir = @"."; // Prevent crash if dataDir is nil
        
        NSArray *possiblePaths = @[
            [dataDir stringByAppendingPathComponent:@"service/service.db"],
            [@"./data/service/service.db" stringByExpandingTildeInPath],
            [dataDir stringByAppendingPathComponent:@"data/service/service.db"]
        ];
        
        NSString *dbPath = nil;
        for (NSString *path in possiblePaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                dbPath = path;
                break;
            }
        }
        
        if (dbPath) {
            PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
            if ([db openWithError:&error]) {
                accounts = [db getAllAccountsWithError:&error];
                [db close];
            }
        }
    }
    
    if (accounts) {
        for (PDSDatabaseAccount *account in accounts) {
            if ([account.did isEqualToString:did]) {
                // Determine service endpoint
                NSString *serviceEndpoint = [[PDSConfiguration sharedConfiguration] canonicalIssuerWithPortHint:0];
                
                NSDictionary *doc = @{
                    @"@context": @[@"https://www.w3.org/ns/did/v1", @"https://w3id.org/security/multikey/v1"],
                    @"id": did,
                    @"alsoKnownAs": @[[NSString stringWithFormat:@"at://%@", account.handle]],
                    @"service": @[@{
                        @"id": @"#atproto_pds",
                        @"type": @"AtprotoPersonalDataServer",
                        @"serviceEndpoint": serviceEndpoint
                    }],
                    @"verificationMethod": @[]
                };
                
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:doc options:NSJSONWritingPrettyPrinted error:nil];
                if (jsonData) {
                    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    // Cache the generated local DID doc
                    [self.cache setDidDocument:did value:jsonString];
                    return jsonString;
                }
            }
        }
    }

#if defined(__APPLE__)
    if (waitResult != 0) {
        if (networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorTimedOut) {
            PDS_LOG_HTTP_WARN(@"fetchDidDocument timeout for %@", did);
        } else {
            PDS_LOG_HTTP_ERROR(@"fetchDidDocument error for %@: %@", did, networkError.localizedDescription);
        }
        [task cancel];
        return nil;
    }
#else
    if (networkError) {
        if (networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorTimedOut) {
            PDS_LOG_HTTP_WARN(@"fetchDidDocument timeout for %@", did);
        } else {
            PDS_LOG_HTTP_ERROR(@"fetchDidDocument error for %@: %@", did, networkError.localizedDescription);
        }
    }
#endif
    
    // Return the error response from PLC if local resolution failed
    // Exception: "DID not registered" errors to prevent caching as valid document
    if (result && [result containsString:@"DID not registered"]) {
        return nil;
    }
    
    return result;
}

- (NSString *)fetchPlcLog:(NSString *)did {
    // Correct URL format: <server>/<did>/log
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/%@/log", self.plcServerURL, did]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 10.0; // 10 second timeout
    
#if defined(__APPLE__)
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSString *result = nil;
    __block NSError *networkError = nil;
    __block NSInteger statusCode = 0;
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *res, NSError *err) {
        if (res) {
            statusCode = ((NSHTTPURLResponse *)res).statusCode;
        }
        if (err) {
            networkError = err;
        } else if (data) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC));
    long waitResult = dispatch_semaphore_wait(sem, timeout);
    
    BOOL isValidResponse = (waitResult == 0) && !networkError && (statusCode == 200) && result && [result hasPrefix:@"["] && [result hasSuffix:@"]"];
    
    if (isValidResponse) {
        [self.cache setPlcLog:did value:result];
        return result;
    }
#else
    // GNUstep: Use NSURLConnection (synchronous)
    __block NSString *result = nil;
    __block NSError *networkError = nil;
    __block NSInteger statusCode = 0;
    
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSURLResponse *response = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:req returningResponse:&response error:&networkError];
        
        if (response && [response isKindOfClass:[NSHTTPURLResponse class]]) {
            statusCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (data) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        
        dispatch_semaphore_signal(sem);
    });
    
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC));
    dispatch_semaphore_wait(sem, timeout);
    
    BOOL isValidResponse = !networkError && (statusCode == 200) && result && [result hasPrefix:@"["] && [result hasSuffix:@"]"];
    
    if (isValidResponse) {
        [self.cache setPlcLog:did value:result];
        return result;
    }
    
    long waitResult = 0; // For the checks below
#endif
    
    // Fallback: Check if this is a local account and generate a simulated log
    NSError *error = nil;
    NSArray *accounts = nil;
    
    if (self.controller) {
        accounts = [self.controller getAllAccountsWithError:&error];
    }
    
    // Fallback to manual DB if controller failed or returned no accounts
    if (!accounts || error || accounts.count == 0) {
        NSString *dataDir = self.controller.dataDirectory;
        if (!dataDir) dataDir = @".";
        
        NSArray *possiblePaths = @[
            [dataDir stringByAppendingPathComponent:@"service/service.db"],
            [@"./data/service/service.db" stringByExpandingTildeInPath],
            [dataDir stringByAppendingPathComponent:@"data/service/service.db"]
        ];
        
        NSString *dbPath = nil;
        for (NSString *path in possiblePaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                dbPath = path;
                break;
            }
        }
        
        if (dbPath) {
            PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
            if ([db openWithError:&error]) {
                accounts = [db getAllAccountsWithError:&error];
                [db close];
            }
        }
    }
    
    if (accounts) {
        for (PDSDatabaseAccount *account in accounts) {
            if ([account.did isEqualToString:did]) {
                // Generate a simulated PLC log for this local account
                // A minimal 'create' operation
                NSDictionary *op = @{
                    @"sig": @"<simulated_signature>",
                    @"prev": [NSNull null],
                    @"type": @"create",
                    @"handle": account.handle ?: @"unknown",
                    @"service": [[PDSConfiguration sharedConfiguration] canonicalIssuerWithPortHint:0],
                    @"signingKey": @"<simulated_key>",
                    @"recoveryKey": @"<simulated_key>"
                };
                
                NSArray *log = @[op];
                
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:log options:NSJSONWritingPrettyPrinted error:nil];
                if (jsonData) {
                    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    [self.cache setPlcLog:did value:jsonString];
                    return jsonString;
                }
            }
        }
    }
    
#if defined(__APPLE__)
    if (waitResult != 0) {
        if (networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorTimedOut) {
            PDS_LOG_HTTP_WARN(@"fetchPlcLog timeout for %@", did);
        } else {
            PDS_LOG_HTTP_ERROR(@"fetchPlcLog error for %@: %@", did, networkError.localizedDescription);
        }
        [task cancel];
        return nil;
    }
#else
    if (networkError) {
        if (networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorTimedOut) {
            PDS_LOG_HTTP_WARN(@"fetchPlcLog timeout for %@", did);
        } else {
            PDS_LOG_HTTP_ERROR(@"fetchPlcLog error for %@: %@", did, networkError.localizedDescription);
        }
    }
#endif
    
    return nil; // Return nil on failure to allow 404/error handling downstream
}

- (NSString *)fetchAccountList {
    if (!self.controller) {
        return @"{\"accounts\":[],\"error\":\"PDS controller not configured\"}";
    }

    // Try to get accounts using PDSController first (preferred method)
    NSError *error = nil;
    NSArray<PDSDatabaseAccount *> *accounts = nil;
    
    @try {
        accounts = [self.controller getAllAccountsWithError:&error];
    } @catch (NSException *exception) {
        PDS_LOG_ERROR_C(PDSLogComponentExplore, @"Exception getting accounts from controller: %@", exception);
        error = [NSError errorWithDomain:@"ExploreHandler" 
                                   code:500 
                               userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown exception"}];
    }
    
    // If controller succeeded, verify we have accounts or at least a valid empty result
    if (accounts && !error) {
        return [self formatAccountsAsJSON:accounts];
    }

    // If controller failed, try multiple possible database locations as fallback
    PDS_LOG_WARN_C(PDSLogComponentExplore, @"Controller method failed, falling back to direct database access: %@", error.localizedDescription);

    NSString *dataDir = self.controller.dataDirectory;
    NSArray *possiblePaths = @[
        [dataDir stringByAppendingPathComponent:@"service/service.db"],
        [@"./data/service/service.db" stringByExpandingTildeInPath],
        [dataDir stringByAppendingPathComponent:@"data/service/service.db"]
    ];
    
    NSString *dbPath = nil;
    for (NSString *path in possiblePaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            PDS_LOG_DEBUG_C(PDSLogComponentExplore, @"Found database at: %@", path);
            dbPath = path;
            break;
        }
    }
    
    if (!dbPath) {
        PDS_LOG_ERROR_C(PDSLogComponentExplore, @"fetchAccountList: No database found in any of the expected locations");
        return @"{\"accounts\":[],\"error\":\"Database not found\"}";
    }

    PDS_LOG_INFO_C(PDSLogComponentExplore, @"Attempting manual database open at: %@", dbPath);
    PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
    if (![db openWithError:&error]) {
        return [NSString stringWithFormat:@"{\"accounts\":[],\"error\":\"Failed to open database: %@\"}", error.localizedDescription];
    }
    
    accounts = [db getAllAccountsWithError:&error];
    [db close];
    
    if (error) {
        return [NSString stringWithFormat:@"{\"accounts\":[],\"error\":\"%@\"}", error.localizedDescription];
    }
    
    return [self formatAccountsAsJSON:accounts];
}

- (NSString *)formatAccountsAsJSON:(NSArray<PDSDatabaseAccount *> *)accounts {

    // Debug: log the number of accounts found    
    PDS_LOG_INFO_C(PDSLogComponentExplore, @"fetchAccountList: Found %lu accounts", (unsigned long)accounts.count);
    
    NSMutableArray *accountArray = [NSMutableArray array];
    for (PDSDatabaseAccount *account in accounts) {
        [accountArray addObject:@{
            @"did": account.did ?: @"",
            @"handle": account.handle ?: @"",
            @"email": account.email ?: [NSNull null],
            @"createdAt": @(account.createdAt),
            @"updatedAt": @(account.updatedAt)
        }];
    }
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{@"accounts": accountArray}
                                                       options:0
                                                         error:&jsonError];
    if (jsonError) {
        return @"{\"accounts\":[],\"error\":\"Failed to serialize accounts\"}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (PDSDatabase *)openLocalDatabaseWithError:(NSError **)error {
    NSString *dataDir = nil;
    if (self.controller) {
        dataDir = self.controller.dataDirectory;
    }
    if (!dataDir) dataDir = @".";
    
    NSArray *possiblePaths = @[
        [dataDir stringByAppendingPathComponent:@"service/service.db"],
        [@"./data/service/service.db" stringByExpandingTildeInPath],
        [dataDir stringByAppendingPathComponent:@"data/service/service.db"]
    ];
    
    NSString *dbPath = nil;
    for (NSString *path in possiblePaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            dbPath = path;
            break;
        }
    }
    
    if (dbPath) {
        PDSDatabase *db = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:dbPath]];
        if ([db openWithError:error]) {
            return db;
        }
    }
    
    if (error && *error == nil) {
        *error = [NSError errorWithDomain:@"ExploreHandler" code:404 userInfo:@{NSLocalizedDescriptionKey: @"Database not found"}];
    }
    return nil;
}

- (NSString *)fetchCollectionsForDid:(NSString *)did {
    NSError *error = nil;
    NSString *rootCid = nil;
    NSString *repoDid = did;
    
    // Try controller first
    if (self.controller) {
        NSDictionary *repoDesc = [self.controller describeRepo:did error:&error];
        if (repoDesc) {
            rootCid = repoDesc[@"root"];
            repoDid = repoDesc[@"did"];
        }
    }
    
    // Fallback to local DB if controller failed
    if (!rootCid) {
        PDSDatabase *db = [self openLocalDatabaseWithError:&error];
        if (db) {
            PDSDatabaseRepo *repo = [db getRepoForDid:did error:&error];
            if (repo) {
                // Use a placeholder for root CID since we can't easily convert NSData to string here without helpers
                rootCid = @"HEAD"; 
                repoDid = repo.ownerDid;
            }
            [db close];
        }
    }
    
    // Ignore errors if we still want to show the list of collections
    // The previous implementation returned early on error, causing "No collections found"
    
    NSMutableArray *collections = [NSMutableArray array];
    NSArray *knownCollections = @[
        @"app.bsky.actor.profile",
        @"app.bsky.feed.post",
        @"app.bsky.feed.like",
        @"app.bsky.feed.repost",
        @"app.bsky.graph.follow",
        @"app.bsky.graph.block",
        @"app.bsky.graph.list",
        @"app.bsky.graph.listitem",
        @"app.bsky.notification.update",
        @"app.bsky.feed.threadgate",
        @"app.bsky.feed.postgate",
        @"app.bsky.labeler.service",
        @"app.bsky.labeler.subscribed"
    ];
    
    for (NSString *collection in knownCollections) {
        [collections addObject:collection];
    }
    
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@{
        @"collections": collections,
        @"root": rootCid ?: @"",
        @"did": repoDid ?: did ?: @""
    } options:0 error:&jsonError];
    
    if (jsonError) {
        return @"{\"collections\":[],\"error\":\"JSON serialization failed\"}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (NSData *)fetchBlob:(NSString *)cidString mimeType:(NSString **)outMimeType {
    if (!cidString) return nil;
    
    CID *cid = [CID cidFromString:cidString];
    if (!cid) return nil;
    
    NSError *error = nil;
    PDSDatabase *db = [self.controller serviceDatabaseWithError:&error];
    if (!db) {
        PDS_LOG_EXPLORE_ERROR(@"Failed to get service database for blob fetch: %@", error);
        return nil;
    }
    
    PDSDatabaseBlob *blobMetadata = [db getBlobWithCid:cid.bytes error:&error];
    if (!blobMetadata) {
        if (error) PDS_LOG_EXPLORE_ERROR(@"Failed to query blob metadata for %@: %@", cidString, error);
        return nil;
    }
    
    if (outMimeType) *outMimeType = blobMetadata.mimeType;
    
    // Use PDSBlobService to get the actual data
    return [self.controller getBlob:cid.bytes forDid:blobMetadata.did error:&error];
}

- (NSDictionary *)decodeCid:(NSString *)cid {
    if (!cid || cid.length < 2) {
        return @{@"error": @"Invalid CID"};
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"input"] = cid;
    result[@"length"] = @(cid.length);

    unichar firstChar = [cid characterAtIndex:0];
    result[@"multibase"] = [NSString stringWithFormat:@"%C", firstChar];
    result[@"multibaseDescription"] = [self multibaseDescriptionForChar:firstChar];

    // Handle CIDv0 (starts with 'Q')
    if (firstChar == 'Q') {
        result[@"version"] = @(0);
        result[@"codec"] = @"0x70"; // dag-pb is implicit for v0
        result[@"codecName"] = @"dag-pb (implicit)";
        result[@"hashAlgorithm"] = @"0x12"; // sha2-256 is implicit for v0
        result[@"hashAlgorithmName"] = @"SHA-256 (implicit)";
        result[@"cidType"] = @"CIDv0";
        result[@"description"] = @"CIDv0 uses base58btc encoding with implicit dag-pb codec and sha2-256 hash";
        return result;
    }

    // For CIDv1, decode the actual binary structure
    NSString *encoded = [cid substringFromIndex:1];
    result[@"encodedPayload"] = encoded;
    result[@"payloadLength"] = @(encoded.length);

    // Decode based on multibase encoding
    NSData *decodedData = nil;
    if (firstChar == 'b') {
        // Use built-in base32 decoding if available, otherwise fall back to custom
        decodedData = [self base32Decode:encoded];
        if (!decodedData) {
            result[@"error"] = @"Failed to decode base32 payload";
            return result;
        }
    } else if (firstChar == 'z') {
        decodedData = [CID base58btcDecode:encoded];
        if (!decodedData) {
            result[@"error"] = @"Failed to decode base58btc payload";
            return result;
        }
    } else {
        result[@"error"] = [NSString stringWithFormat:@"Unsupported multibase encoding: %C", firstChar];
        return result;
    }

    if (!decodedData || decodedData.length == 0) {
        result[@"error"] = @"Failed to decode multibase payload";
        return result;
    }

    // Parse CIDv1 binary structure
    const uint8_t *bytes = [decodedData bytes];
    NSUInteger length = decodedData.length;
    NSUInteger offset = 0;



    // Version (should be 1 for CIDv1)
    if (offset >= length) {
        result[@"error"] = @"CID too short for version";
        return result;
    }

    uint8_t version = bytes[offset++];
    result[@"version"] = @(version);

    if (version != 1) {
        result[@"error"] = [NSString stringWithFormat:@"Unsupported CID version: %d", version];
        return result;
    }

    // Decode multicodec (varint)
    uint64_t codec = [self decodeVarint:bytes length:length offset:&offset];
    result[@"codec"] = [NSString stringWithFormat:@"0x%llx", codec];
    result[@"codecName"] = [self codecNameForCode:codec];

    // Decode multihash
    if (offset >= length) {
        result[@"error"] = @"Incomplete multihash";
        return result;
    }

    uint64_t hashAlg = [self decodeVarint:bytes length:length offset:&offset];
    result[@"hashAlgorithm"] = [NSString stringWithFormat:@"0x%llx", hashAlg];
    result[@"hashAlgorithmName"] = [self hashNameForCode:hashAlg];

    if (offset >= length) {
        result[@"error"] = @"Incomplete hash size";
        return result;
    }

    uint8_t hashSize = bytes[offset++];
    result[@"hashSize"] = @(hashSize);

    if (offset + hashSize > length) {
        result[@"error"] = @"Incomplete hash digest";
        return result;
    }

    NSMutableString *digest = [NSMutableString string];
    for (NSUInteger i = 0; i < hashSize; i++) {
        [digest appendFormat:@"%02x", bytes[offset + i]];
    }
    result[@"digest"] = digest;
    result[@"cidType"] = @"CIDv1";

    return result;
}

- (uint64_t)decodeVarint:(const uint8_t *)bytes length:(NSUInteger)length offset:(NSUInteger *)offset {
    uint64_t value = 0;
    int shift = 0;
    NSUInteger startOffset = *offset;

    while (*offset < length && shift < 64) {
        uint8_t byte = bytes[*offset];
        (*offset)++;

        // Add the 7 low bits to the value
        value |= ((uint64_t)(byte & 0x7f)) << shift;
        shift += 7;

        // If high bit is not set, this is the last byte
        if (!(byte & 0x80)) {
            break;
        }

        // Prevent infinite loop on malformed data (varints should be at most 9 bytes for uint64)
        if (*offset - startOffset > 9) {
            break;
        }
    }

    return value;
}

- (NSData *)base32Decode:(NSString *)input {
    // Base32 alphabet (RFC 4648 lowercase)
    NSDictionary *alphabetMap = @{
        @"a": @0, @"b": @1, @"c": @2, @"d": @3, @"e": @4, @"f": @5,
        @"g": @6, @"h": @7, @"i": @8, @"j": @9, @"k": @10, @"l": @11,
        @"m": @12, @"n": @13, @"o": @14, @"p": @15, @"q": @16, @"r": @17,
        @"s": @18, @"t": @19, @"u": @20, @"v": @21, @"w": @22, @"x": @23,
        @"y": @24, @"z": @25, @"2": @26, @"3": @27, @"4": @28, @"5": @29,
        @"6": @30, @"7": @31
    };

    NSMutableData *output = [NSMutableData data];
    uint32_t buffer = 0;
    NSUInteger bitsLeft = 0;

    for (NSUInteger i = 0; i < input.length; i++) {
        unichar c = [input characterAtIndex:i];
        if (c == '-' || c == ' ' || c == '\n' || c == '\r' || c == '\t') continue;
        
        NSString *charStr = [[NSString stringWithCharacters:&c length:1] lowercaseString];
        NSNumber *val = alphabetMap[charStr];

        if (!val) return nil; // Invalid character - reject the whole thing

        buffer = (buffer << 5) | [val intValue];
        bitsLeft += 5;

        while (bitsLeft >= 8) {
            bitsLeft -= 8;
            uint8_t byte = (buffer >> bitsLeft) & 0xFF;
            [output appendBytes:&byte length:1];
        }
    }

    return output;
}

- (NSString *)multibaseDescriptionForChar:(unichar)c {
    switch (c) {
        case 'b': return @"base32 (RFC4648 lowercase)";
        case 'B': return @"base32 (RFC4648 uppercase)";
        case 'c': return @"base32hex (RFC4648 lowercase)";
        case 'C': return @"base32hex (RFC4648 uppercase)";
        case 'f': return @"base16 (hex lowercase)";
        case 'F': return @"base16 (hex uppercase)";
        case 'k': return @"base36 (lowercase)";
        case 'K': return @"base36 (uppercase)";
        case 'm': return @"base64 (RFC4648 no padding)";
        case 'M': return @"base64 (RFC4648 with padding)";
        case 'p': return @"base64url (RFC4648 no padding)";
        case 'P': return @"base64url (RFC4648 with padding)";
        case 't': return @"base64url (no padding)";
        case 'T': return @"base64url (with padding)";
        case 'v': return @"base32hex (no padding)";
        case 'V': return @"base32hex (with padding)";
        case 'w': return @"base32hex (no padding)";
        case 'W': return @"base32hex (with padding)";
        case 'x': return @"base16 (no padding)";
        case 'X': return @"base16 (with padding)";
        case 'y': return @"base64 (no padding)";
        case 'Y': return @"base64 (with padding)";
        case 'z': return @"base58btc";
        case 'Z': return @"base58flickr";
        case '0': return @"base2";
        case '1': return @"base8";
        case '2': return @"base10";
        case '9': return @"base36";
        case 'a': return @"base36";
        default: return @"unknown multibase encoding";
    }
}

- (NSString *)codecNameForCode:(uint64_t)code {
    switch (code) {
        case 0x00: return @"identity";
        case 0x01: return @"cidv1";
        case 0x02: return @"cidv2";
        case 0x03: return @"cidv3";
        case 0x04: return @"ip4";
        case 0x06: return @"ip6";
        case 0x0a: return @"ipcidr";
        case 0x21: return @"port";
        case 0x2f: return @"dccp";
        case 0x33: return @"sctp";
        case 0x35: return @"tcp";
        case 0x36: return @"udp";
        case 0x55: return @"raw";
        case 0x56: return @"cbor";
        case 0x70: return @"dag-pb";
        case 0x71: return @"dag-cbor";
        case 0x72: return @"dag-json";
        case 0x78: return @"git-raw";
        case 0x7b: return @"eth-block";
        case 0x7c: return @"eth-block-list";
        case 0x81: return @"eth-tx-trie";
        case 0x82: return @"eth-tx";
        case 0x83: return @"eth-tx-receipt-trie";
        case 0x84: return @"eth-tx-receipt";
        case 0x85: return @"eth-state-trie";
        case 0x86: return @"eth-account-snapshot";
        case 0x87: return @"eth-storage-trie";
        case 0x90: return @"bitcoin-block";
        case 0x91: return @"bitcoin-tx";
        case 0x92: return @"bitcoin-witness-commitment";
        case 0xb0: return @"zcash-block";
        case 0xb1: return @"zcash-tx";
        case 0xc0: return @"decred-block";
        case 0xc1: return @"decred-tx";
        case 0xce: return @"ipld-ns";
        case 0xd0: return @"fil-commitment-unsealed";
        case 0xd1: return @"fil-commitment-sealed";
        case 0xe0: return @"holochain-adr-v0";
        case 0xe1: return @"holochain-adr-v1";
        case 0xe2: return @"holochain-key-v0";
        case 0xe3: return @"holochain-key-v1";
        case 0xe4: return @"holochain-sig-v0";
        case 0xe5: return @"holochain-sig-v1";
        case 0x0129: return @"dag-json";
        case 0x85e: return @"dash-block";
        case 0x85f: return @"dash-tx";
        case 0xb199: return @"swarm-manifest";
        case 0xb19a: return @"swarm-feed";
        case 0xc219: return @"tcp";
        case 0xc21a: return @"udp";
        case 0xc220: return @"ipfs";
        case 0xc221: return @"ipfs-ns";
        case 0xc226: return @"onion";
        case 0xc227: return @"onion3";
        case 0xc228: return @"garlic64";
        case 0xc229: return @"garlic32";
        case 0xc230: return @"p2p-circuit";
        case 0xc400: return @"ipfs";
        case 0xc401: return @"ipfs-ns";
        case 0xc402: return @"swarm";
        case 0xc403: return @"ipfs-ns";
        case 0xc404: return @"zeronet";
        case 0xc405: return @"ipfs-ns";
        case 0xc406: return @"cbor";
        case 0xc500: return @"ipns-ns";
        case 0xc501: return @"swarm-ns";
        case 0xc502: return @"ipns-ns";
        case 0xc503: return @"zeronet-ns";
        case 0xc504: return @"ipns-ns";
        case 0xc600: return @"path";
        case 0xc700: return @"multihash";
        case 0xc701: return @"multiaddr";
        case 0xc702: return @"multibase";
        case 0xc800: return @"dns4";
        case 0xc801: return @"dns6";
        case 0xc802: return @"dnsaddr";
        case 0xc803: return @"dnsaddr";
        case 0xc900: return @"dns";
        case 0xca00: return @"dns4";
        case 0xca01: return @"dns6";
        case 0xca02: return @"dnsaddr";
        case 0xd000: return @"protobuf";
        case 0xd100: return @"cbor";
        case 0xd200: return @"raw";
        case 0xd300: return @"dbl-sha2-256";
        case 0xe200: return @"eth-hash";
        case 0xe201: return @"eth-state-trie";
        case 0xe202: return @"eth-block";
        case 0xe203: return @"eth-block-list";
        case 0xe204: return @"eth-tx-trie";
        case 0xe205: return @"eth-tx";
        case 0xe206: return @"eth-tx-receipt-trie";
        case 0xe207: return @"eth-tx-receipt";
        case 0xe208: return @"eth-account-snapshot";
        case 0xe209: return @"eth-storage-trie";
        case 0xe300: return @"eth-tx-receipt-trie";
        case 0xe301: return @"eth-tx-receipt";
        case 0xe302: return @"eth-state-trie";
        case 0xe303: return @"eth-account-snapshot";
        case 0xe304: return @"eth-storage-trie";
        case 0xf000: return @"bitcoin-block";
        case 0xf001: return @"bitcoin-tx";
        case 0xf002: return @"bitcoin-witness-commitment";
        case 0xf100: return @"zcash-block";
        case 0xf101: return @"zcash-tx";
        case 0xf200: return @"decred-block";
        case 0xf201: return @"decred-tx";
        default: return [NSString stringWithFormat:@"unknown (0x%llx)", code];
    }
}

- (NSString *)hashNameForCode:(uint64_t)code {
    switch (code) {
        case 0x00: return @"identity";
        case 0x11: return @"sha1";
        case 0x12: return @"sha2-256";
        case 0x13: return @"sha2-512";
        case 0x14: return @"sha3-512";
        case 0x15: return @"sha3-384";
        case 0x16: return @"sha3-256";
        case 0x17: return @"sha3-224";
        case 0x18: return @"shake-128";
        case 0x19: return @"shake-256";
        case 0x1a: return @"keccak-224";
        case 0x1b: return @"keccak-256";
        case 0x1c: return @"keccak-384";
        case 0x1d: return @"keccak-512";
        case 0x20: return @"blake3";
        case 0x21: return @"sha3-512";
        case 0x22: return @"sha3-384";
        case 0x23: return @"sha3-256";
        case 0x24: return @"sha3-224";
        case 0x25: return @"shake-128";
        case 0x26: return @"shake-256";
        case 0x27: return @"keccak-224";
        case 0x28: return @"keccak-256";
        case 0x29: return @"keccak-384";
        case 0x2a: return @"keccak-512";
        case 0xb201: return @"blake2b-8";
        case 0xb202: return @"blake2b-16";
        case 0xb203: return @"blake2b-24";
        case 0xb204: return @"blake2b-32";
        case 0xb205: return @"blake2b-40";
        case 0xb206: return @"blake2b-48";
        case 0xb207: return @"blake2b-56";
        case 0xb208: return @"blake2b-64";
        case 0xb209: return @"blake2b-72";
        case 0xb20a: return @"blake2b-80";
        case 0xb20b: return @"blake2b-88";
        case 0xb20c: return @"blake2b-96";
        case 0xb20d: return @"blake2b-104";
        case 0xb20e: return @"blake2b-112";
        case 0xb20f: return @"blake2b-120";
        case 0xb210: return @"blake2b-128";
        case 0xb211: return @"blake2b-136";
        case 0xb212: return @"blake2b-144";
        case 0xb213: return @"blake2b-152";
        case 0xb214: return @"blake2b-160";
        case 0xb215: return @"blake2b-168";
        case 0xb216: return @"blake2b-176";
        case 0xb217: return @"blake2b-184";
        case 0xb218: return @"blake2b-192";
        case 0xb219: return @"blake2b-200";
        case 0xb21a: return @"blake2b-208";
        case 0xb21b: return @"blake2b-216";
        case 0xb21c: return @"blake2b-224";
        case 0xb21d: return @"blake2b-232";
        case 0xb21e: return @"blake2b-240";
        case 0xb21f: return @"blake2b-248";
        case 0xb220: return @"blake2b-256";
        case 0xb221: return @"blake2b-264";
        case 0xb222: return @"blake2b-272";
        case 0xb223: return @"blake2b-280";
        case 0xb224: return @"blake2b-288";
        case 0xb225: return @"blake2b-296";
        case 0xb226: return @"blake2b-304";
        case 0xb227: return @"blake2b-312";
        case 0xb228: return @"blake2b-320";
        case 0xb229: return @"blake2b-328";
        case 0xb22a: return @"blake2b-336";
        case 0xb22b: return @"blake2b-344";
        case 0xb22c: return @"blake2b-352";
        case 0xb22d: return @"blake2b-360";
        case 0xb22e: return @"blake2b-368";
        case 0xb22f: return @"blake2b-376";
        case 0xb230: return @"blake2b-384";
        case 0xb231: return @"blake2b-392";
        case 0xb232: return @"blake2b-400";
        case 0xb233: return @"blake2b-408";
        case 0xb234: return @"blake2b-416";
        case 0xb235: return @"blake2b-424";
        case 0xb236: return @"blake2b-432";
        case 0xb237: return @"blake2b-440";
        case 0xb238: return @"blake2b-448";
        case 0xb239: return @"blake2b-456";
        case 0xb23a: return @"blake2b-464";
        case 0xb23b: return @"blake2b-472";
        case 0xb23c: return @"blake2b-480";
        case 0xb23d: return @"blake2b-488";
        case 0xb23e: return @"blake2b-496";
        case 0xb23f: return @"blake2b-504";
        case 0xb240: return @"blake2b-512";
        case 0xb241: return @"blake2s-8";
        case 0xb242: return @"blake2s-16";
        case 0xb243: return @"blake2s-24";
        case 0xb244: return @"blake2s-32";
        case 0xb245: return @"blake2s-40";
        case 0xb246: return @"blake2s-48";
        case 0xb247: return @"blake2s-56";
        case 0xb248: return @"blake2s-64";
        case 0xb249: return @"blake2s-72";
        case 0xb24a: return @"blake2s-80";
        case 0xb24b: return @"blake2s-88";
        case 0xb24c: return @"blake2s-96";
        case 0xb24d: return @"blake2s-104";
        case 0xb24e: return @"blake2s-112";
        case 0xb24f: return @"blake2s-120";
        case 0xb250: return @"blake2s-128";
        case 0xb251: return @"blake2s-136";
        case 0xb252: return @"blake2s-144";
        case 0xb253: return @"blake2s-152";
        case 0xb254: return @"blake2s-160";
        case 0xb255: return @"blake2s-168";
        case 0xb256: return @"blake2s-176";
        case 0xb257: return @"blake2s-184";
        case 0xb258: return @"blake2s-192";
        case 0xb259: return @"blake2s-200";
        case 0xb25a: return @"blake2s-208";
        case 0xb25b: return @"blake2s-216";
        case 0xb25c: return @"blake2s-224";
        case 0xb25d: return @"blake2s-232";
        case 0xb25e: return @"blake2s-240";
        case 0xb25f: return @"blake2s-248";
        case 0xb260: return @"blake2s-256";
        default: return [NSString stringWithFormat:@"unknown (0x%llx)", code];
    }
}

- (NSString *)resolveHandleToDid:(NSString *)handle {
    return nil;
}

- (NSString *)resolveHandleFromDid:(NSString *)did {
    return did;
}

#pragma mark - OpenAPI Spec Generation

- (NSArray<APIEndpointDescriptor *> *)allEndpointDescriptors {
    NSMutableArray *descriptors = [NSMutableArray array];

    APIParameterDescriptor *didParam = [[APIParameterDescriptor alloc] init];
    didParam.name = @"did";
    didParam.in = @"query";
    didParam.type = @"string";
    didParam.paramDescription = @"The DID of the account or repository";
    didParam.required = NO;

    APIParameterDescriptor *collectionParam = [[APIParameterDescriptor alloc] init];
    collectionParam.name = @"collection";
    collectionParam.in = @"query";
    collectionParam.type = @"string";
    collectionParam.paramDescription = @"The collection namespace (e.g., app.bsky.feed.post)";
    collectionParam.required = NO;

    APIParameterDescriptor *uriParam = [[APIParameterDescriptor alloc] init];
    uriParam.name = @"uri";
    uriParam.in = @"query";
    uriParam.type = @"string";
    uriParam.paramDescription = @"The AT Protocol URI (at://did/collection/rkey)";
    uriParam.required = YES;

    APIParameterDescriptor *limitParam = [[APIParameterDescriptor alloc] init];
    limitParam.name = @"limit";
    limitParam.in = @"query";
    limitParam.type = @"integer";
    limitParam.paramDescription = @"Maximum number of records to return (default 50, max 200)";
    limitParam.required = NO;

    APIResponseDescriptor *accountsArrayResponse = [[APIResponseDescriptor alloc] init];
    accountsArrayResponse.statusCode = @"200";
    accountsArrayResponse.responseDescription = @"Array of account objects";
    accountsArrayResponse.arrayItemRef = @"#/components/schemas/Account";

    APIResponseDescriptor *reposArrayResponse = [[APIResponseDescriptor alloc] init];
    reposArrayResponse.statusCode = @"200";
    reposArrayResponse.responseDescription = @"Array of repository objects";
    reposArrayResponse.arrayItemRef = @"#/components/schemas/Repository";

    APIResponseDescriptor *collectionsArrayResponse = [[APIResponseDescriptor alloc] init];
    collectionsArrayResponse.statusCode = @"200";
    collectionsArrayResponse.responseDescription = @"Array of collection objects with record counts";
    collectionsArrayResponse.arrayItemRef = @"#/components/schemas/Collection";

    APIResponseDescriptor *recordsArrayResponse = [[APIResponseDescriptor alloc] init];
    recordsArrayResponse.statusCode = @"200";
    recordsArrayResponse.responseDescription = @"Array of record objects";
    recordsArrayResponse.arrayItemRef = @"#/components/schemas/Record";

    APIResponseDescriptor *recordResponse = [[APIResponseDescriptor alloc] init];
    recordResponse.statusCode = @"200";
    recordResponse.responseDescription = @"Record details with value";
    recordResponse.schemaRef = @"#/components/schemas/Record";

    APIResponseDescriptor *error400 = [[APIResponseDescriptor alloc] init];
    error400.statusCode = @"400";
    error400.responseDescription = @"Bad request - missing required parameters";

    APIResponseDescriptor *error404 = [[APIResponseDescriptor alloc] init];
    error404.statusCode = @"404";
    error404.responseDescription = @"Resource not found";

    APIResponseDescriptor *errorResponse = [[APIResponseDescriptor alloc] init];
    errorResponse.statusCode = @"500";
    errorResponse.responseDescription = @"Internal server error";
    errorResponse.schemaRef = @"#/components/schemas/Error";

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/accounts"
                                                              method:@"get"
                                                             summary:@"List all accounts"
                                                        endpointName:@"accounts"
                                                        operationId:@"listAccounts"
                                                               tags:@[@"Accounts"]
                                                          parameters:@[]
                                                          responses:@[accountsArrayResponse, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/repositories"
                                                              method:@"get"
                                                             summary:@"List all repositories (PDS instances)"
                                                        endpointName:@"repositories"
                                                        operationId:@"listRepositories"
                                                               tags:@[@"Repositories"]
                                                          parameters:@[]
                                                          responses:@[reposArrayResponse, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/collections"
                                                              method:@"get"
                                                             summary:@"List collections for a repository"
                                                        endpointName:@"collections"
                                                        operationId:@"listCollections"
                                                               tags:@[@"Collections"]
                                                          parameters:@[didParam]
                                                          responses:@[collectionsArrayResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/describe"
                                                              method:@"get"
                                                             summary:@"Describe a repository"
                                                        endpointName:@"describe"
                                                        operationId:@"describeRepository"
                                                               tags:@[@"Repositories"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              [self responseWithStatusCode:@"200" description:@"Repository description with collections and record count"],
                                                              error400, error404, errorResponse
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/account-records"
                                                              method:@"get"
                                                             summary:@"List records for an account"
                                                        endpointName:@"account-records"
                                                        operationId:@"listAccountRecords"
                                                               tags:@[@"Records"]
                                                          parameters:@[didParam, collectionParam, limitParam]
                                                          responses:@[recordsArrayResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/record"
                                                              method:@"get"
                                                             summary:@"Get a single record by URI"
                                                        endpointName:@"record"
                                                        operationId:@"getRecord"
                                                               tags:@[@"Records"]
                                                          parameters:@[uriParam]
                                                          responses:@[recordResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/record-details"
                                                              method:@"get"
                                                             summary:@"Get detailed record information"
                                                        endpointName:@"record-details"
                                                        operationId:@"getRecordDetails"
                                                               tags:@[@"Records"]
                                                          parameters:@[uriParam]
                                                          responses:@[recordResponse, error400, error404, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/account-details"
                                                              method:@"get"
                                                             summary:@"Get account details"
                                                        endpointName:@"account-details"
                                                        operationId:@"getAccountDetails"
                                                               tags:@[@"Accounts"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              [self responseWithStatusCode:@"200" description:@"Account details"],
                                                              error400, error404, errorResponse
                                                          ]]];

    APIParameterDescriptor *valueParam = [[APIParameterDescriptor alloc] init];
    valueParam.name = @"value";
    valueParam.in = @"query";
    valueParam.type = @"string";
    valueParam.paramDescription = @"JSON object as string containing the record value";
    valueParam.required = YES;

    APIParameterDescriptor *createDidParam = [[APIParameterDescriptor alloc] init];
    createDidParam.name = @"did";
    createDidParam.in = @"query";
    createDidParam.type = @"string";
    createDidParam.paramDescription = @"The DID of the repository";
    createDidParam.required = YES;

    APIParameterDescriptor *createCollectionParam = [[APIParameterDescriptor alloc] init];
    createCollectionParam.name = @"collection";
    createCollectionParam.in = @"query";
    createCollectionParam.type = @"string";
    createCollectionParam.paramDescription = @"The collection namespace (e.g., app.bsky.feed.post)";
    createCollectionParam.required = YES;

    APIParameterDescriptor *createRkeyParam = [[APIParameterDescriptor alloc] init];
    createRkeyParam.name = @"rkey";
    createRkeyParam.in = @"query";
    createRkeyParam.type = @"string";
    createRkeyParam.paramDescription = @"The record key (unique within collection). Optional for app.bsky.feed.post; if omitted, a TID rkey is generated.";
    createRkeyParam.required = NO;

    APIResponseDescriptor *createResponse = [[APIResponseDescriptor alloc] init];
    createResponse.statusCode = @"200";
    createResponse.responseDescription = @"Created record with URI, CID, and value";
    createResponse.schemaRef = @"#/components/schemas/CreatedRecord";

    APIResponseDescriptor *resolvedIdentityResponse = [self responseWithStatusCode:@"200" description:@"Resolved identity"];
    APIResponseDescriptor *didDocResponse = [self responseWithStatusCode:@"200" description:@"DID document (JSON)"];
    APIResponseDescriptor *plcLogResponse = [self responseWithStatusCode:@"200" description:@"PLC operation log"];
    APIResponseDescriptor *cidInfoResponse = [self responseWithStatusCode:@"200" description:@"CID information"];
    APIResponseDescriptor *blobResponse = [self responseWithStatusCode:@"200" description:@"Blob data"];

    APIParameterDescriptor *cidParamDecode = [self paramWithName:@"cid" in:@"query" type:@"string" description:@"CID to decode" required:YES];
    APIParameterDescriptor *cidParamInfo = [self paramWithName:@"cid" in:@"query" type:@"string" description:@"CID to look up" required:YES];
    APIParameterDescriptor *blobDidParam = [self paramWithName:@"did" in:@"query" type:@"string" description:@"Repository DID" required:YES];
    APIParameterDescriptor *blobCidParam = [self paramWithName:@"cid" in:@"query" type:@"string" description:@"Blob CID" required:YES];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/create-record"
                                                              method:@"post"
                                                             summary:@"Create a new record"
                                                        endpointName:@"create-record"
                                                        operationId:@"createRecord"
                                                               tags:@[@"Records"]
                                                          parameters:@[createDidParam, createCollectionParam, createRkeyParam, valueParam]
                                                          responses:@[createResponse, error400, errorResponse]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/lookup"
                                                              method:@"get"
                                                             summary:@"Resolve handle to DID or DID to handle"
                                                        endpointName:@"lookup"
                                                        operationId:@"resolveIdentity"
                                                               tags:@[@"Identity"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              resolvedIdentityResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/did"
                                                              method:@"get"
                                                             summary:@"Fetch DID document"
                                                        endpointName:@"did"
                                                        operationId:@"getDidDocument"
                                                               tags:@[@"Identity"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              didDocResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/plc-log"
                                                              method:@"get"
                                                             summary:@"Get PLC operation log"
                                                        endpointName:@"plc-log"
                                                        operationId:@"getPlcLog"
                                                               tags:@[@"Identity"]
                                                          parameters:@[didParam]
                                                          responses:@[
                                                              plcLogResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/cid-decode"
                                                              method:@"get"
                                                             summary:@"Decode and describe a CID"
                                                        endpointName:@"cid-decode"
                                                        operationId:@"decodeCid"
                                                               tags:@[@"Content"]
                                                          parameters:@[cidParamDecode]
                                                          responses:@[
                                                              cidInfoResponse,
                                                              error400
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/cid-info"
                                                              method:@"get"
                                                             summary:@"Get information about a CID"
                                                        endpointName:@"cid-info"
                                                        operationId:@"getCidInfo"
                                                               tags:@[@"Content"]
                                                          parameters:@[cidParamInfo]
                                                          responses:@[
                                                              cidInfoResponse,
                                                              error400, error404
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/blob"
                                                              method:@"get"
                                                             summary:@"Get blob data"
                                                        endpointName:@"blob"
                                                        operationId:@"getBlob"
                                                               tags:@[@"Content"]
                                                          parameters:@[blobDidParam, blobCidParam]
                                                          responses:@[
                                                              blobResponse,
                                                              error400, error404
                                                          ]]];

    APIResponseDescriptor *openapiSpecResponse = [self responseWithStatusCode:@"200" description:@"OpenAPI specification (JSON or YAML)"];
    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/openapi.json"
                                                              method:@"get"
                                                             summary:@"Get OpenAPI specification"
                                                        endpointName:@"openapi.json"
                                                        operationId:@"getOpenAPISpecJSON"
                                                               tags:@[@"Meta"]
                                                          parameters:@[]
                                                          responses:@[
                                                              openapiSpecResponse,
                                                              errorResponse
                                                          ]]];

    [descriptors addObject:[APIEndpointDescriptor descriptorWithPath:@"/api/pds/openapi.yaml"
                                                              method:@"get"
                                                             summary:@"Get OpenAPI specification"
                                                        endpointName:@"openapi.yaml"
                                                        operationId:@"getOpenAPISpecYAML"
                                                               tags:@[@"Meta"]
                                                          parameters:@[]
                                                          responses:@[
                                                              openapiSpecResponse,
                                                              errorResponse
                                                          ]]];

    return [descriptors copy];
}

- (APIResponseDescriptor *)responseWithStatusCode:(NSString *)statusCode description:(NSString *)description {
    APIResponseDescriptor *resp = [[APIResponseDescriptor alloc] init];
    resp.statusCode = statusCode;
    resp.responseDescription = description;
    return resp;
}

- (APIParameterDescriptor *)paramWithName:(NSString *)name in:(NSString *)inLocation type:(NSString *)type description:(NSString *)description required:(BOOL)required {
    APIParameterDescriptor *param = [[APIParameterDescriptor alloc] init];
    param.name = name;
    param.in = inLocation;
    param.type = type;
    param.paramDescription = description;
    param.required = required;
    return param;
}

- (NSDictionary *)generateOpenAPISpec {
    NSMutableDictionary *spec = [NSMutableDictionary dictionary];
    spec[@"openapi"] = @"3.0.0";

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"title"] = @"ATProto PDS Explore API";
    info[@"description"] = @"REST API for exploring AT Protocol PDS data including accounts, repositories, records, and collections. This API provides read-only access to PDS data for development and debugging purposes.";
    info[@"version"] = @"1.0.0";

    NSMutableDictionary *contact = [NSMutableDictionary dictionary];
    contact[@"name"] = @"ATProto PDS Developer Support";
    contact[@"url"] = @"https://github.com/bluesky-social/atproto/blob/main/packages/pds/README.md";
    info[@"contact"] = contact;

    NSMutableDictionary *license = [NSMutableDictionary dictionary];
    license[@"name"] = @"MIT License";
    license[@"url"] = @"https://opensource.org/licenses/MIT";
    info[@"license"] = license;

    spec[@"info"] = info;

    NSMutableDictionary *externalDocs = [NSMutableDictionary dictionary];
    externalDocs[@"description"] = @"ATProto PDS Documentation";
    externalDocs[@"url"] = @"https://atproto.com/docs";
    spec[@"externalDocs"] = externalDocs;

    NSMutableArray *servers = [NSMutableArray array];
    [servers addObject:@{@"url": @"/api/pds", @"description": @"Local development server"}];
    spec[@"servers"] = servers;

    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    NSArray<APIEndpointDescriptor *> *endpoints = [self allEndpointDescriptors];

    for (APIEndpointDescriptor *endpoint in endpoints) {
        NSString *pathKey = endpoint.path;
        NSString *methodKey = [endpoint.method lowercaseString];

        NSMutableDictionary *operation = [[endpoint openAPIDict] mutableCopy];

        NSMutableDictionary *pathItem = paths[pathKey];
        if (!pathItem) {
            pathItem = [NSMutableDictionary dictionary];
            paths[pathKey] = pathItem;
        }
        pathItem[methodKey] = operation;
    }

    spec[@"paths"] = paths;

    NSMutableDictionary *components = [NSMutableDictionary dictionary];
    NSMutableDictionary *schemas = [NSMutableDictionary dictionary];

    schemas[@"Account"] = @{
        @"type": @"object",
        @"description": @"Represents a PDS account with identity information",
        @"properties": @{
            @"did": @{@"type": @"string", @"description": @"Account DID (Decentralized Identifier)", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"handle": @{@"type": @"string", @"description": @"Account handle (e.g., alice.example.com)", @"example": @"alice.example.com"},
            @"email": @{@"type": @"string", @"description": @"Account email address", @"nullable": @YES, @"example": @"alice@example.com"},
            @"createdAt": @{@"type": @"integer", @"description": @"Unix timestamp of account creation", @"example": @(1704752400)},
            @"updatedAt": @{@"type": @"integer", @"description": @"Unix timestamp of last update", @"example": @(1704752400)}
        }
    };

    schemas[@"Repository"] = @{
        @"type": @"object",
        @"description": @"Represents a PDS repository instance",
        @"properties": @{
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"handle": @{@"type": @"string", @"description": @"Repository handle", @"example": @"alice.example.com"},
            @"email": @{@"type": @"string", @"description": @"Contact email", @"nullable": @YES, @"example": @"alice@example.com"},
            @"createdAt": @{@"type": @"integer", @"description": @"Creation timestamp", @"example": @(1704752400)},
            @"updatedAt": @{@"type": @"integer", @"description": @"Last update timestamp", @"example": @(1704752400)}
        }
    };

    schemas[@"Collection"] = @{
        @"type": @"object",
        @"description": @"Represents a collection namespace within a repository with record count",
        @"properties": @{
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"collection": @{@"type": @"string", @"description": @"Collection namespace (e.g., app.bsky.feed.post)", @"example": @"app.bsky.feed.post"},
            @"count": @{@"type": @"integer", @"description": @"Number of records in collection", @"example": @(15)}
        }
    };

    schemas[@"Record"] = @{
        @"type": @"object",
        @"description": @"Represents an AT Protocol record with content and metadata",
        @"properties": @{
            @"uri": @{@"type": @"string", @"description": @"Record URI (at://did/collection/rkey)", @"example": @"at://did:plc:g3x5vnga7kiu3oaookgeozpb/app.bsky.feed.post/3k5d3f4g5h6j7"},
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"collection": @{@"type": @"string", @"description": @"Collection namespace", @"example": @"app.bsky.feed.post"},
            @"rkey": @{@"type": @"string", @"description": @"Record key (unique within collection)", @"example": @"3k5d3f4g5h6j7"},
            @"cid": @{@"type": @"string", @"description": @"Content ID of the record value", @"example": @"bafyreifac123"},
            @"value": @{@"type": @"object", @"description": @"Record content as JSON object"},
            @"createdAt": @{@"type": @"string", @"description": @"ISO 8601 timestamp of record creation", @"example": @"2024-01-08T20:30:00Z"}
        }
    };

    schemas[@"CreatedRecord"] = @{
        @"type": @"object",
        @"description": @"Response from creating a new record",
        @"properties": @{
            @"uri": @{@"type": @"string", @"description": @"Created record URI", @"example": @"at://did:plc:g3x5vnga7kiu3oaookgeozpb/app.bsky.feed.post/3k5d3f4g5h6j7"},
            @"did": @{@"type": @"string", @"description": @"Repository DID", @"example": @"did:plc:g3x5vnga7kiu3oaookgeozpb"},
            @"collection": @{@"type": @"string", @"description": @"Collection namespace", @"example": @"app.bsky.feed.post"},
            @"rkey": @{@"type": @"string", @"description": @"Record key", @"example": @"3k5d3f4g5h6j7"},
            @"cid": @{@"type": @"string", @"description": @"Generated CID", @"example": @"bafyreinewcid"},
            @"value": @{@"type": @"object", @"description": @"Record value that was stored"},
            @"createdAt": @{@"type": @"string", @"description": @"ISO 8601 timestamp", @"example": @"2024-01-08T20:30:00Z"}
        }
    };

    schemas[@"Error"] = @{
        @"type": @"object",
        @"description": @"Standard error response (RFC 7807 Problem Details format)",
        @"properties": @{
            @"type": @{@"type": @"string", @"description": @"Error type identifier", @"example": @"https://atproto.com/errors/bad-request"},
            @"title": @{@"type": @"string", @"description": @"Short human-readable error title", @"example": @"Bad Request"},
            @"status": @{@"type": @"integer", @"description": @"HTTP status code", @"example": @(400)},
            @"detail": @{@"type": @"string", @"description": @"Detailed error description", @"example": @"Missing required parameter: did"},
            @"instance": @{@"type": @"string", @"description": @"URI reference that identifies the specific occurrence"}
        }
    };

    components[@"schemas"] = schemas;
    spec[@"components"] = components;

    return [spec copy];
}

- (NSString *)jsonToYAML:(NSDictionary *)json indent:(NSUInteger)indent {
    NSMutableString *yaml = [NSMutableString string];
    NSString *spaces = [@"" stringByPaddingToLength:indent withString:@" " startingAtIndex:0];

    NSArray *sortedKeys = [[json allKeys] sortedArrayUsingSelector:@selector(compare:)];

    for (NSString *key in sortedKeys) {
        id value = json[key];

        [yaml appendFormat:@"%@", spaces];

        if ([value isKindOfClass:[NSDictionary class]]) {
            [yaml appendFormat:@"%@:\n", key];
            [yaml appendString:[self jsonToYAML:value indent:indent + 2]];
        } else if ([value isKindOfClass:[NSArray class]]) {
            [yaml appendFormat:@"%@:\n", key];
            for (id item in value) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [yaml appendString:[self jsonToYAML:item indent:indent + 2]];
                } else {
                    [yaml appendFormat:@"%@  - %@\n", spaces, item];
                }
            }
        } else if ([value isKindOfClass:[NSString class]]) {
            NSString *strValue = (NSString *)value;
            if ([strValue containsString:@":"] || [strValue containsString:@"{"] || [strValue containsString:@"}"] || [strValue containsString:@"["] || [strValue containsString:@"]"] || [strValue hasPrefix:@"/"] || [strValue hasPrefix:@"#"] || [strValue isEqualToString:@"~"] || [strValue isEqualToString:@"null"] || [strValue isEqualToString:@"true"] || [strValue isEqualToString:@"false"] || strValue.length == 0) {
                [yaml appendFormat:@"%@: \"%@\"\n", key, [strValue stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
            } else {
                [yaml appendFormat:@"%@: %@\n", key, strValue];
            }
        } else if ([value isKindOfClass:[NSNumber class]]) {
            NSNumber *numValue = (NSNumber *)value;
            if (strcmp(numValue.objCType, @encode(BOOL)) == 0 || [numValue isEqual:@YES] || [numValue isEqual:@NO]) {
                [yaml appendFormat:@"%@: %@\n", key, numValue.boolValue ? @"true" : @"false"];
            } else {
                [yaml appendFormat:@"%@: %@\n", key, numValue];
            }
        } else if ([value isKindOfClass:[NSNull class]]) {
            [yaml appendFormat:@"%@: null\n", key];
        } else {
            [yaml appendFormat:@"%@: %@\n", key, value];
        }
    }

    return [yaml copy];
}

- (void)handleApiDocs:(NSDictionary *)params response:(HttpResponse *)response {
    NSString *docsPath = [self staticFilePath:@"docs.html"];
    
    if (!docsPath) {
        [response setJsonBody:@{@"error": @"Assets path not configured"}];
        return;
    }
    
    NSError *error = nil;
    NSString *html = [NSString stringWithContentsOfFile:docsPath encoding:NSUTF8StringEncoding error:&error];
    
    if (error || !html) {
        [response setJsonBody:@{@"error": @"Failed to load docs", @"details": error.localizedDescription ?: @"Unknown error"}];
        return;
    }
    
    response.contentType = @"text/html; charset=utf-8";
    [response setBodyData:[html dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)handleApiOpenapiSpec:(NSDictionary *)params response:(HttpResponse *)response {
    NSDictionary *spec = [self generateOpenAPISpec];
    NSError *jsonError = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:spec options:NSJSONWritingPrettyPrinted error:&jsonError];

    if (jsonError) {
        [response setJsonBody:@{@"error": @"Failed to generate OpenAPI spec", @"details": jsonError.localizedDescription ?: @"Unknown error"}];
        return;
    }

    NSString *yamlString = [self jsonToYAML:spec indent:0];

    NSString *format = params[@"format"];
    if ([format.lowercaseString isEqualToString:@"json"]) {
        response.contentType = @"application/json";
        [response setBodyData:jsonData];
    } else {
        response.contentType = @"application/yaml";
        [response setBodyData:[yamlString dataUsingEncoding:NSUTF8StringEncoding]];
    }
}

@end
