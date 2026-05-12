// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Debug/GZLogger.h"
#import "Compat/Foundation/NSDataCompat.h"

@interface OAuthDemoHandler ()
@property (nonatomic, copy) NSString *dataDirectory;
@end

@implementation OAuthDemoHandler

+ (instancetype)sharedHandler {
    static OAuthDemoHandler *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[OAuthDemoHandler alloc] init];
    });
    return instance;
}

- (void)setDataDirectory:(NSString *)dataDirectory {
    _dataDirectory = [dataDirectory copy];
}

- (void)setController:(PDSController *)controller {
    _dataDirectory = [controller.dataDirectory copy];
}

- (BOOL)canHandleRequest:(HttpRequest *)request {
    return [request.path hasPrefix:@"/oauth-demo"];
}

- (NSString *)assetsPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *assetsPath = nil;

    assetsPath = [[NSBundle mainBundle] pathForResource:@"OAuthDemo/Assets" ofType:@""];
    
    if (!assetsPath) {
        NSString *executablePath = [[NSBundle mainBundle] executablePath] ?: [[NSProcessInfo processInfo] arguments][0];
        NSString *executableDir = [executablePath stringByDeletingLastPathComponent];
        NSString *projectRoot = [[[executableDir stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        NSString *projectAssets = [projectRoot stringByAppendingPathComponent:@"Garazyk/Sources/App/OAuthDemo/Assets"];
        if ([fm fileExistsAtPath:projectAssets]) {
            assetsPath = projectAssets;
        }
    }

    if (!assetsPath && self.dataDirectory) {
        NSString *dataDir = self.dataDirectory;
        NSString *projectAssets = [[fm currentDirectoryPath] stringByAppendingPathComponent:@"Garazyk/Sources/App/OAuthDemo/Assets"];
        if ([fm fileExistsAtPath:projectAssets]) {
            assetsPath = projectAssets;
        }
    }

    return assetsPath;
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
    NSString *path = request.path;
    NSString *relativePath = nil;
    if ([path isEqualToString:@"/oauth-demo"] ||
        [path isEqualToString:@"/oauth-demo/"] ||
        [path isEqualToString:@"/oauth-demo/callback"]) {
        relativePath = @"index.html";
    } else if ([path hasPrefix:@"/oauth-demo/"]) {
        relativePath = [path substringFromIndex:[@"/oauth-demo/" length]];
    }

    if (!relativePath || relativePath.length == 0 ||
        [relativePath hasPrefix:@"/"] || [relativePath containsString:@".."]) {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"Invalid path", @"path": path ?: @""}];
        return;
    }
    
    NSString *assetsDir = [self assetsPath];
    if (!assetsDir) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"OAuth Demo assets not found"}];
        return;
    }

    NSString *filePath = [assetsDir stringByAppendingPathComponent:relativePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        response.statusCode = 404;
        [response setJsonBody:@{
            @"error": @"File not found",
            @"path": path ?: @"",
            @"relativePath": relativePath ?: @"",
            @"checked": filePath ?: @""
        }];
        return;
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&error];
    if (error || !data) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"Failed to read file", @"details": error.localizedDescription}];
        return;
    }

    NSString *ext = [relativePath pathExtension];
    if ([ext isEqualToString:@"html"]) response.contentType = @"text/html; charset=utf-8";
    else if ([ext isEqualToString:@"js"]) response.contentType = @"application/javascript; charset=utf-8";
    else if ([ext isEqualToString:@"css"]) response.contentType = @"text/css; charset=utf-8";
    else if ([ext isEqualToString:@"woff2"]) response.contentType = @"font/woff2";
    else if ([ext isEqualToString:@"woff"]) response.contentType = @"font/woff";
    else if ([ext isEqualToString:@"svg"]) response.contentType = @"image/svg+xml";
    else response.contentType = @"application/octet-stream";

    [response setBodyData:data];
}

@end
