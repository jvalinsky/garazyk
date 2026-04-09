#import "App/CappuccinoUI/CappuccinoUIHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Compat/Foundation/NSDataCompat.h"

@interface CappuccinoUIHandler ()
@property(nonatomic, copy, nullable) NSString *dataDirectory;
@end

@implementation CappuccinoUIHandler

+ (instancetype)sharedHandler {
  static CappuccinoUIHandler *instance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[CappuccinoUIHandler alloc] init];
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
  return [request.path hasPrefix:@"/ui"];
}

- (nullable NSString *)assetsPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];

  NSString *bundlePath =
      [[NSBundle mainBundle] pathForResource:@"CappuccinoUI/dist/CappuccinoUI"
                                      ofType:@""];
  if (bundlePath.length > 0) {
    [candidates addObject:bundlePath];
  }

  NSString *bundleForClassPath =
      [[NSBundle bundleForClass:[self class]]
          pathForResource:@"CappuccinoUI/dist/CappuccinoUI"
                   ofType:@""];
  if (bundleForClassPath.length > 0) {
    [candidates addObject:bundleForClassPath];
  }

  NSString *executablePath = [[NSBundle mainBundle] executablePath];
  if (executablePath.length == 0 &&
      [NSProcessInfo processInfo].arguments.count > 0) {
    executablePath = [NSProcessInfo processInfo].arguments[0];
  }
  if (executablePath.length > 0) {
    NSString *executableDir = [executablePath stringByDeletingLastPathComponent];
    NSString *projectRoot =
        [[[executableDir stringByDeletingLastPathComponent]
            stringByDeletingLastPathComponent]
            stringByDeletingLastPathComponent];
    [candidates
        addObject:[projectRoot stringByAppendingPathComponent:
                              @"ATProtoPDS/Sources/App/CappuccinoUI/dist/"
                              @"CappuccinoUI"]];
    [candidates
        addObject:[projectRoot stringByAppendingPathComponent:
                              @"ATProtoPDS/Sources/App/CappuccinoUI/Build/"
                              @"Release/CappuccinoUI"]];
    [candidates
        addObject:[projectRoot stringByAppendingPathComponent:
                              @"ATProtoPDS/Sources/App/CappuccinoUI/Build/"
                              @"Debug/CappuccinoUI"]];
    [candidates
        addObject:[projectRoot stringByAppendingPathComponent:
                              @"ATProtoPDS/Sources/App/CappuccinoUI"]];
  }

  NSString *cwd = [fm currentDirectoryPath];
  [candidates
      addObject:[cwd stringByAppendingPathComponent:
                         @"ATProtoPDS/Sources/App/CappuccinoUI/dist/"
                         @"CappuccinoUI"]];
  [candidates
      addObject:[cwd stringByAppendingPathComponent:
                         @"ATProtoPDS/Sources/App/CappuccinoUI/Build/Release/"
                         @"CappuccinoUI"]];
  [candidates
      addObject:[cwd stringByAppendingPathComponent:
                         @"ATProtoPDS/Sources/App/CappuccinoUI/Build/Debug/"
                         @"CappuccinoUI"]];
  // Source fallback keeps /ui reachable in dev/test when dist is not staged.
  [candidates addObject:[cwd stringByAppendingPathComponent:
                                 @"ATProtoPDS/Sources/App/CappuccinoUI"]];

  if (self.dataDirectory.length > 0) {
    NSString *relativeToDataDist =
        [[self.dataDirectory stringByAppendingPathComponent:
                                 @"../ATProtoPDS/Sources/App/CappuccinoUI/"
                                 @"dist/CappuccinoUI"] stringByStandardizingPath];
    [candidates addObject:relativeToDataDist];
    NSString *relativeToDataSource =
        [[self.dataDirectory stringByAppendingPathComponent:
                                 @"../ATProtoPDS/Sources/App/CappuccinoUI"]
            stringByStandardizingPath];
    [candidates addObject:relativeToDataSource];
  }

  // Well-known system paths for packaged / Docker deployments.
  [candidates addObject:@"/usr/share/atprotopds/assets/CappuccinoUI"];
  [candidates addObject:@"/usr/local/share/atprotopds/assets/CappuccinoUI"];

  // Explicit override via environment variable.
  NSString *envPath = [[[NSProcessInfo processInfo] environment]
      objectForKey:@"PDS_CAPPUCCINO_UI_PATH"];
  if (envPath.length > 0) {
    [candidates insertObject:envPath atIndex:0];
  }

  for (NSString *candidate in candidates) {
    NSString *normalized = [candidate stringByStandardizingPath];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:normalized isDirectory:&isDir] && isDir) {
      return normalized;
    }
  }

  return nil;
}

- (NSString *)contentTypeForPath:(NSString *)path {
  NSString *ext = [[path pathExtension] lowercaseString];
  if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"]) {
    return @"text/html; charset=utf-8";
  }
  if ([ext isEqualToString:@"js"]) {
    return @"application/javascript; charset=utf-8";
  }
  if ([ext isEqualToString:@"css"]) {
    return @"text/css; charset=utf-8";
  }
  if ([ext isEqualToString:@"json"] || [ext isEqualToString:@"map"]) {
    return @"application/json; charset=utf-8";
  }
  if ([ext isEqualToString:@"svg"]) {
    return @"image/svg+xml";
  }
  if ([ext isEqualToString:@"png"]) {
    return @"image/png";
  }
  if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
    return @"image/jpeg";
  }
  if ([ext isEqualToString:@"gif"]) {
    return @"image/gif";
  }
  if ([ext isEqualToString:@"ico"]) {
    return @"image/x-icon";
  }
  if ([ext isEqualToString:@"woff"]) {
    return @"font/woff";
  }
  if ([ext isEqualToString:@"woff2"]) {
    return @"font/woff2";
  }
  if ([ext isEqualToString:@"ttf"]) {
    return @"font/ttf";
  }
  if ([ext isEqualToString:@"otf"]) {
    return @"font/otf";
  }
  if ([ext isEqualToString:@"txt"]) {
    return @"text/plain; charset=utf-8";
  }
  if ([ext isEqualToString:@"sj"] || [ext isEqualToString:@"j"]) {
    return @"application/javascript; charset=utf-8";
  }
  if ([ext isEqualToString:@"json"]) {
    return @"application/json; charset=utf-8";
  }
  return @"application/octet-stream";
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
  NSString *path = request.path ?: @"";
  NSString *relativePath = nil;

  if ([path isEqualToString:@"/ui"] || [path isEqualToString:@"/ui/"]) {
    relativePath = @"index.html";
  } else if ([path hasPrefix:@"/ui/"]) {
    relativePath = [path substringFromIndex:4];
  } else if ([path isEqualToString:@"/"]) {
    relativePath = @"index.html";
  } else if ([path hasPrefix:@"/"]) {
    relativePath = [path substringFromIndex:1];
  }

  if (relativePath.length == 0) {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{@"error" : @"Not Found", @"path" : path ?: @""}];
    return;
  }

  if ([relativePath hasPrefix:@"/"]) {
    relativePath = [relativePath substringFromIndex:1];
  }

  if ([relativePath containsString:@".."]) {
    response.statusCode = HttpStatusForbidden;
    [response setJsonBody:@{@"error" : @"Forbidden"}];
    return;
  }

  NSString *assetsDir = [self assetsPath];
  if (!assetsDir) {
    response.statusCode = HttpStatusInternalServerError;
    [response setJsonBody:@{@"error" : @"Cappuccino UI assets not found"}];
    return;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *filePath = [assetsDir stringByAppendingPathComponent:relativePath];
  BOOL isDirectory = NO;
  if ([fm fileExistsAtPath:filePath isDirectory:&isDirectory] && isDirectory) {
    filePath = [filePath stringByAppendingPathComponent:@"index.html"];
  }

  if (![fm fileExistsAtPath:filePath]) {
    // Route-like paths without extensions should resolve to shell.
    if ([relativePath pathExtension].length == 0) {
      NSString *indexPath = [assetsDir stringByAppendingPathComponent:@"index.html"];
      if ([fm fileExistsAtPath:indexPath]) {
        filePath = indexPath;
      }
    }
  }

  if (![fm fileExistsAtPath:filePath]) {
    response.statusCode = HttpStatusNotFound;
    [response setJsonBody:@{
      @"error" : @"File not found",
      @"path" : path ?: @"",
      @"checked" : filePath ?: @""
    }];
    return;
  }

  NSError *error = nil;
  NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&error];
  if (error || !data) {
    response.statusCode = HttpStatusInternalServerError;
    [response setJsonBody:@{
      @"error" : @"Failed to read file",
      @"details" : error.localizedDescription ?: @"Unknown error"
    }];
    return;
  }

  response.statusCode = HttpStatusOK;
  response.contentType = [self contentTypeForPath:filePath];
  // Objective-J runtime compiles/executes modules dynamically and requires
  // `unsafe-eval`. Restrict this relaxation to UI assets only.
  [response setHeader:@"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;"
               forKey:@"Content-Security-Policy"];
  [response setBodyData:data];

  PDS_LOG_DEBUG(@"CappuccinoUIHandler served %@ from %@", path, filePath);
}

@end
