// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Auth/OAuth2Handler+Assets.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation OAuth2Handler (Assets)

- (NSString *)escapeHtml:(NSString *)input {
  if (!input)
    return @"";
  NSString *escaped = input;
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
  escaped =
      [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
  return escaped;
}

- (NSString *)assetsPath {
  if (self.dataDirectory) {
    NSString *path =
        [self.dataDirectory stringByAppendingPathComponent:@"Auth/Assets"];
    GZ_LOG_AUTH_DEBUG(@"Checking for assets in dataDirectory: %@", path);
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      return path;
    }
  }

  // Check standard install path (Docker/packaged deployments)
  NSString *installPath = @"/usr/share/atprotopds/assets/Auth";
  if ([[NSFileManager defaultManager] fileExistsAtPath:installPath]) {
    return installPath;
  }

  // Fallback to project structure if running from source (handling cwd=build/)
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray *candidates = @[
    [cwd stringByAppendingPathComponent:@"Garazyk/Sources/Auth/Assets"],
    [[cwd stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Garazyk/Sources/Auth/Assets"],
    [[[cwd stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"Garazyk/Sources/Auth/Assets"]
  ];

  for (NSString *candidate in candidates) {
    GZ_LOG_AUTH_DEBUG(@"Checking for assets in candidate path: %@", candidate);
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
      return candidate;
    }
  }

  GZ_LOG_AUTH_ERROR(
      @"No assets path found for OAuth2Handler (dataDirectory: %@, cwd: %@)",
      self.dataDirectory, cwd);
  return nil;
}

- (NSString *)sharedCSSPath {
  if (self.dataDirectory) {
    NSString *path =
        [self.dataDirectory stringByAppendingPathComponent:
            @"Shared/DesignSystem/css"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
      return path;
    }
  }

  // Check standard install path (Docker/packaged deployments)
  NSString *installPath = @"/usr/share/atprotopds/assets/css";
  if ([[NSFileManager defaultManager] fileExistsAtPath:installPath]) {
    return installPath;
  }

  // Fallback to project structure (development from build/ or project root)
  NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
  NSArray *candidates = @[
    [cwd stringByAppendingPathComponent:
        @"Garazyk/Sources/Shared/DesignSystem/css"],
    [[cwd stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:
            @"Garazyk/Sources/Shared/DesignSystem/css"],
  ];

  for (NSString *candidate in candidates) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
      return candidate;
    }
  }

  GZ_LOG_AUTH_ERROR(
      @"No shared CSS path found for OAuth2Handler (dataDirectory: %@, cwd: %@)",
      self.dataDirectory, cwd);
  return nil;
}

- (void)handleCSSRequest:(HttpRequest *)request
                response:(HttpResponse *)response {
  NSString *cssDir = [self sharedCSSPath];
  if (!cssDir) {
    response.statusCode = 404;
    [response setBodyString:@"Not Found"];
    return;
  }

  NSString *filename = request.path.lastPathComponent;
  if (![filename hasSuffix:@".css"]) {
    response.statusCode = 403;
    [response setBodyString:@"Forbidden"];
    return;
  }

  // Prevent path traversal
  if ([filename containsString:@".."]) {
    response.statusCode = 403;
    [response setBodyString:@"Forbidden"];
    return;
  }

  NSString *filePath = [cssDir stringByAppendingPathComponent:filename];
  NSString *resolvedPath = filePath.stringByStandardizingPath;
  NSString *resolvedBase = cssDir.stringByStandardizingPath;
  if (![resolvedPath hasPrefix:resolvedBase]) {
    response.statusCode = 403;
    [response setBodyString:@"Forbidden"];
    return;
  }

  NSError *readError = nil;
  NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&readError];
  if (!data) {
    response.statusCode = 404;
    [response setBodyString:@"Not Found"];
    return;
  }

  response.statusCode = 200;
  response.contentType = @"text/css; charset=utf-8";
  [response setBodyData:data];
}

@end
