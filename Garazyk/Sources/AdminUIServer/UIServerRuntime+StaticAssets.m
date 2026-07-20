// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AdminUIServer/UIServerRuntime.h"

#import "AdminUIServer/UIAuthManager.h"
#import "AdminUIServer/UIBackendClient.h"
#import "AdminUIServer/UIServiceConfig.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/Generated/GZXrpcNSID.h"
#import "Auth/CryptoUtils.h"
#import "Debug/GZLogger.h"
#import "AdminUIServer/UIServerRuntime+Private.h"

@implementation UIServerRuntime (StaticAssets)

#pragma mark - Static Asset Serving

- (void)serveStaticAssetForPath:(NSString *)path response:(HttpResponse *)response {
    // Sanitize: only serve files from the assets directory, no path traversal
    NSString *filename = path;
    // Strip leading slashes
    while (filename.length > 0 && [filename hasPrefix:@"/"]) {
        filename = [filename substringFromIndex:1];
    }
    if (filename.length == 0) {
        response.statusCode = 403;
        [response setBodyString:@"Forbidden"];
        return;
    }

    NSString *assetsDir = self.configuration.assetsDirectory;
    if (!assetsDir) {
        // Fallback: try bundle path
        assetsDir = [[NSBundle mainBundle] resourcePath];
    }

    NSString *filePath = [assetsDir stringByAppendingPathComponent:filename];

    // Verify the resolved path is still within the assets directory
    NSString *resolvedPath = filePath.stringByStandardizingPath;
    NSString *resolvedBase = assetsDir.stringByStandardizingPath;
    if (![resolvedPath hasPrefix:resolvedBase]) {
        response.statusCode = 403;
        [response setBodyString:@"Forbidden"];
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:filePath isDirectory:&isDir] || isDir) {
        response.statusCode = 404;
        [response setBodyString:@"Not Found"];
        return;
    }

    // Validate file size before loading into memory (10MB limit)
    NSError *attrError = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:&attrError];
    if (!attrs || attrs.fileSize > 10 * 1024 * 1024) {
        response.statusCode = 413;
        [response setBodyString:@"File Too Large"];
        return;
    }

    NSData *data = [NSData dataWithContentsOfFile:filePath];
    if (!data) {
        response.statusCode = 500;
        [response setBodyString:@"Internal Server Error"];
        return;
    }

    // Determine content type from extension
    NSString *extension = filePath.pathExtension.lowercaseString ?: @"";
    NSDictionary<NSString *, NSString *> *mimeTypes = @{
        @"css": @"text/css; charset=utf-8",
        @"js": @"application/javascript; charset=utf-8",
        @"png": @"image/png",
        @"jpg": @"image/jpeg",
        @"jpeg": @"image/jpeg",
        @"gif": @"image/gif",
        @"svg": @"image/svg+xml",
        @"ico": @"image/x-icon",
        @"woff": @"font/woff",
        @"woff2": @"font/woff2",
    };
    NSString *contentType = mimeTypes[extension] ?: @"application/octet-stream";

    response.statusCode = 200;
    response.contentType = contentType;
    [response setHeader:@"public, max-age=3600" forKey:@"Cache-Control"];
    [response setBodyData:data];
}


@end
