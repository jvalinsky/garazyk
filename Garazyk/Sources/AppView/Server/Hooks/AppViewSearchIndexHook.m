/*!
 @file AppViewSearchIndexHook.m

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import "AppView/Server/Hooks/AppViewSearchIndexHook.h"
#import "Debug/PDSLogger.h"

@interface AppViewSearchIndexHook ()

@property (nonatomic, copy) NSString *searchEndpoint;

@end

@implementation AppViewSearchIndexHook

- (instancetype)initWithSearchEndpoint:(NSString *)searchEndpoint {
    self = [super init];
    if (self) {
        _searchEndpoint = [searchEndpoint copy];
    }
    return self;
}

- (NSString *)hookIdentifier {
    return @"search-index";
}

- (nullable NSArray<NSString *> *)collections {
    // Index all collections
    return nil;
}

- (void)didIndexRecord:(NSDictionary *)record
                   uri:(NSString *)uri
                    did:(NSString *)did
            collection:(NSString *)collection {
    // Extract searchable text from the record
    NSString *text = [self extractSearchableText:record];
    if (text.length == 0) return;

    // Build the search document
    NSDictionary *doc = @{
        @"uri": uri,
        @"did": did,
        @"collection": collection,
        @"text": text,
        @"indexed_at": [NSDate date].description
    };

    // POST to the search endpoint
    [self postToSearchEndpoint:doc];
}

- (void)didDeleteRecordWithURI:(NSString *)uri
                           did:(NSString *)did
                    collection:(NSString *)collection {
    // Send a delete request to the search endpoint
    NSDictionary *doc = @{
        @"uri": uri,
        @"action": @"delete"
    };

    [self postToSearchEndpoint:doc];
}

#pragma mark - Private

- (NSString *)extractSearchableText:(NSDictionary *)record {
    NSMutableString *text = [NSMutableString string];

    // Extract text from common fields
    NSArray *textFields = @[@"text", @"displayName", @"name",
                            @"description", @"subject", @"title"];
    for (NSString *field in textFields) {
        id value = record[field];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            if (text.length > 0) [text appendString:@" "];
            [text appendString:value];
        }
    }

    return [text copy];
}

- (void)postToSearchEndpoint:(NSDictionary *)doc {
    if (self.searchEndpoint.length == 0) return;

    NSURL *url = [NSURL URLWithString:self.searchEndpoint];
    if (!url) return;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSData *body = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
    if (body) {
        request.HTTPBody = body;
    }

    // Use NSURLSession for fire-and-forget async POST
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            PDS_LOG_DEBUG(@"[SearchIndexHook] POST to %@ failed: %@",
                          self.searchEndpoint, error.localizedDescription);
        }
    }];
    [task resume];
}

@end
