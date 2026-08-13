// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Repository/ATProtoWebTileMothership.h"
#import "Repository/ATProtoWebTile+CAR.h"

NSString * const ATProtoWebTileMothershipErrorDomain = @"com.atproto.webtile.mothership";

static NSError *MothershipError(ATProtoWebTileMothershipErrorCode code, NSString *message) {
    return [NSError errorWithDomain:ATProtoWebTileMothershipErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *MothershipNormalizeBaseURL(NSString *pdsBaseURL) {
    NSString *base = [pdsBaseURL stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([base hasSuffix:@"/"]) {
        base = [base substringToIndex:base.length - 1];
    }
    return base;
}

@interface ATProtoWebTileMothership ()
@property (nonatomic, strong, readwrite) ATProtoWebTile *tile;
@end

@implementation ATProtoWebTileMothership

- (instancetype)initWithTile:(ATProtoWebTile *)tile {
    NSParameterAssert(tile);
    self = [super init];
    if (self) {
        _tile = tile;
    }
    return self;
}

- (NSDictionary *)resolvePath:(NSString *)path {
    NSError *error = nil;
    NSDictionary *response = [self.tile responseForPath:path ?: @"/" error:&error];
    if (response) {
        return response;
    }
    return @{
        @"status": @500,
        @"headers": @{@"content-type": @"text/plain; charset=utf-8"},
        @"body": [(error.localizedDescription ?: @"resolve-path failed")
                  dataUsingEncoding:NSUTF8StringEncoding],
    };
}

- (NSDictionary *)handleRequest:(NSDictionary *)request {
    if (![request isKindOfClass:[NSDictionary class]]) {
        return @{@"error": @"invalid request"};
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    id requestId = request[@"requestId"];
    if (requestId) {
        out[@"requestId"] = requestId;
    }
    NSString *type = request[@"type"];
    if (![type isKindOfClass:[NSString class]] || type.length == 0) {
        out[@"error"] = @"missing type";
        return out;
    }
    if ([type isEqualToString:@"resolve-path"]) {
        NSString *path = request[@"path"];
        if (![path isKindOfClass:[NSString class]] || path.length == 0) {
            path = @"/";
        }
        out[@"response"] = [self resolvePath:path];
        return out;
    }
    out[@"error"] = [NSString stringWithFormat:@"unknown type: %@", type];
    return out;
}

+ (nullable ATProtoWebTile *)tileWithGetBlobFromPDSBaseURL:(NSString *)pdsBaseURL
                                                      did:(NSString *)did
                                                      cid:(NSString *)cidString
                                               httpClient:(id<ATProtoWebTileHTTPClient>)httpClient
                                                    error:(NSError **)error {
    if (![httpClient conformsToProtocol:@protocol(ATProtoWebTileHTTPClient)] ||
        did.length == 0 || cidString.length == 0) {
        if (error) {
            *error = MothershipError(ATProtoWebTileMothershipErrorInvalidArgument,
                                     @"getBlob requires httpClient, did, and cid");
        }
        return nil;
    }
    NSString *base = MothershipNormalizeBaseURL(pdsBaseURL);
    if (base.length == 0) {
        if (error) {
            *error = MothershipError(ATProtoWebTileMothershipErrorInvalidArgument,
                                     @"pdsBaseURL required");
        }
        return nil;
    }
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];
    NSString *qDid = [did stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: did;
    NSString *qCid = [cidString stringByAddingPercentEncodingWithAllowedCharacters:allowed]
                         ?: cidString;
    NSString *urlString =
        [NSString stringWithFormat:@"%@/xrpc/com.atproto.sync.getBlob?did=%@&cid=%@",
         base, qDid, qCid];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) {
            *error = MothershipError(ATProtoWebTileMothershipErrorInvalidArgument,
                                     @"bad getBlob URL");
        }
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"GET";
    req.timeoutInterval = 60.0;
    NSHTTPURLResponse *resp = nil;
    NSError *reqErr = nil;
    NSData *body = [httpClient sendSynchronousRequest:req options:nil response:&resp error:&reqErr];
    if (!body || resp.statusCode != 200) {
        if (error) {
            *error = reqErr ?: MothershipError(ATProtoWebTileMothershipErrorFetchFailed,
                                               @"sync.getBlob failed");
        }
        return nil;
    }
    return [ATProtoWebTile tileWithCARData:body strict:YES error:error];
}

@end
