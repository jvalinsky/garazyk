#import "App/CappuccinoUI/CappuccinoUIHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
#import "Compat/Foundation/NSDataCompat.h"

@interface CappuccinoUIHandler ()
@property(nonatomic, copy, nullable) NSString *dataDirectory;
@property(nonatomic, copy) NSString *serviceProfile;
@end

@implementation CappuccinoUIHandler

- (instancetype)init {
  self = [super init];
  if (self) {
    _serviceProfile = @"full";
  }
  return self;
}

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

- (NSString *)normalizedServiceProfile:(NSString *)serviceProfile {
  NSString *normalized = [[serviceProfile ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([normalized isEqualToString:@"pds"] || [normalized isEqualToString:@"relay"] ||
      [normalized isEqualToString:@"plc"] || [normalized isEqualToString:@"appview"] ||
      [normalized isEqualToString:@"full"]) {
    return normalized;
  }
  return @"full";
}

- (void)setServiceProfile:(NSString *)serviceProfile {
  _serviceProfile = [[self normalizedServiceProfile:serviceProfile] copy];
}

- (void)setController:(PDSController *)controller {
  _dataDirectory = [controller.dataDirectory copy];
}

- (BOOL)canHandleRequest:(HttpRequest *)request {
  return [request.path hasPrefix:@"/ui"];
}

- (NSDictionary<NSString *, NSString *> *)endpointBasesForProfile:(NSString *)profile {
  NSMutableDictionary<NSString *, NSString *> *bases = [NSMutableDictionary dictionary];
  if ([profile isEqualToString:@"pds"] || [profile isEqualToString:@"full"]) {
    bases[@"explore"] = @"/api/pds";
    bases[@"admin"] = @"/admin";
    bases[@"mst"] = @"/api/mst";
    bases[@"xrpc"] = @"/xrpc";
    bases[@"oauth"] = @"/oauth";
    bases[@"oauthDemo"] = @"/oauth-demo";
  }
  if ([profile isEqualToString:@"relay"] || [profile isEqualToString:@"full"]) {
    bases[@"relay"] = @"/api/relay";
  }
  if ([profile isEqualToString:@"plc"] || [profile isEqualToString:@"full"]) {
    bases[@"plc"] = @"";  // PLC endpoints are at root.
  }
  if ([profile isEqualToString:@"appview"] || [profile isEqualToString:@"full"]) {
    bases[@"appview"] = @"";  // AppView admin endpoints are rooted at /admin.
  }
  return [bases copy];
}

- (NSArray<NSString *> *)availableServicesForProfile:(NSString *)profile {
  if ([profile isEqualToString:@"full"]) {
    return @[ @"pds", @"relay", @"plc", @"appview" ];
  }
  return @[ profile ];
}

- (NSDictionary *)profilePayload {
  NSString *profile = [self normalizedServiceProfile:self.serviceProfile];
  return @{
    @"serviceProfile" : profile,
    @"availableServices" : [self availableServicesForProfile:profile],
    @"endpointBases" : [self endpointBasesForProfile:profile],
    @"uiEntrypoint" : @"/ui"
  };
}

- (void)addUniquePath:(NSString *)path toArray:(NSMutableArray<NSString *> *)array {
  if (path.length == 0) {
    return;
  }
  NSString *normalized = [path stringByStandardizingPath];
  if (normalized.length == 0) {
    return;
  }
  if (![array containsObject:normalized]) {
    [array addObject:normalized];
  }
}

- (void)appendAncestorChainForPath:(NSString *)path
                          maxDepth:(NSUInteger)maxDepth
                            toRoots:(NSMutableArray<NSString *> *)roots {
  NSString *current = [path stringByStandardizingPath];
  NSUInteger depth = 0;
  while (current.length > 0 && depth < maxDepth) {
    [self addUniquePath:current toArray:roots];
    NSString *parent = [current stringByDeletingLastPathComponent];
    if (parent.length == 0 || [parent isEqualToString:current]) {
      break;
    }
    current = parent;
    depth += 1;
  }
}

- (nullable NSString *)assetsPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableArray<NSString *> *candidates = [NSMutableArray array];
  NSMutableArray<NSString *> *roots = [NSMutableArray array];

  // Explicit override via environment variable.
  NSString *envPath = [[[NSProcessInfo processInfo] environment]
      objectForKey:@"PDS_CAPPUCCINO_UI_PATH"];
  [self addUniquePath:envPath toArray:candidates];

  NSString *bundlePath =
      [[NSBundle mainBundle] pathForResource:@"CappuccinoUI/dist/CappuccinoUI"
                                      ofType:@""];
  [self addUniquePath:bundlePath toArray:candidates];

  NSString *bundleForClassPath =
      [[NSBundle bundleForClass:[self class]]
          pathForResource:@"CappuccinoUI/dist/CappuccinoUI"
                   ofType:@""];
  [self addUniquePath:bundleForClassPath toArray:candidates];

  NSString *executablePath = [[NSBundle mainBundle] executablePath];
  if (executablePath.length == 0 &&
      [NSProcessInfo processInfo].arguments.count > 0) {
    executablePath = [NSProcessInfo processInfo].arguments[0];
  }
  if (executablePath.length > 0) {
    NSString *executableDir = [executablePath stringByDeletingLastPathComponent];
    [self appendAncestorChainForPath:executableDir maxDepth:12 toRoots:roots];
  }

  NSString *cwd = [fm currentDirectoryPath];
  [self appendAncestorChainForPath:cwd maxDepth:8 toRoots:roots];

  if (self.dataDirectory.length > 0) {
    [self appendAncestorChainForPath:self.dataDirectory maxDepth:6 toRoots:roots];
  }

  NSArray<NSString *> *relativeSearchSuffixes = @[
    @"Garazyk/Sources/App/CappuccinoUI/dist/CappuccinoUI",
    @"Sources/App/CappuccinoUI/dist/CappuccinoUI",
    @"Garazyk/Sources/App/CappuccinoUI/Build/Release/CappuccinoUI",
    @"Sources/App/CappuccinoUI/Build/Release/CappuccinoUI",
    @"Garazyk/Sources/App/CappuccinoUI/Build/Debug/CappuccinoUI",
    @"Sources/App/CappuccinoUI/Build/Debug/CappuccinoUI",
    @"Garazyk/Sources/App/CappuccinoUI",
    @"Sources/App/CappuccinoUI"
  ];

  for (NSString *root in roots) {
    for (NSString *suffix in relativeSearchSuffixes) {
      [self addUniquePath:[root stringByAppendingPathComponent:suffix]
                  toArray:candidates];
    }
  }

  if (self.dataDirectory.length > 0) {
    NSString *relativeToDataDistGarazyk = [[self.dataDirectory
        stringByAppendingPathComponent:
            @"../Garazyk/Sources/App/CappuccinoUI/dist/CappuccinoUI"]
        stringByStandardizingPath];
    [self addUniquePath:relativeToDataDistGarazyk toArray:candidates];

    NSString *relativeToDataSourceGarazyk = [[self.dataDirectory
        stringByAppendingPathComponent:@"../Garazyk/Sources/App/CappuccinoUI"]
        stringByStandardizingPath];
    [self addUniquePath:relativeToDataSourceGarazyk toArray:candidates];
  }

  // Well-known system paths for packaged / Docker deployments.
  [self addUniquePath:@"/usr/share/atprotopds/assets/CappuccinoUI"
              toArray:candidates];
  [self addUniquePath:@"/usr/local/share/atprotopds/assets/CappuccinoUI"
              toArray:candidates];

  for (NSString *candidate in candidates) {
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:candidate isDirectory:&isDir] && isDir) {
      return candidate;
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
  return @"application/octet-stream";
}

- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response {
  NSString *path = request.path ?: @"";
  if ([path isEqualToString:@"/ui/profile"] ||
      [path isEqualToString:@"/ui/profile/"]) {
    response.statusCode = HttpStatusOK;
    [response setHeader:@"no-store, no-cache, must-revalidate"
                 forKey:@"Cache-Control"];
    [response setHeader:@"no-cache" forKey:@"Pragma"];
    [response setHeader:@"0" forKey:@"Expires"];
    [response setJsonBody:[self profilePayload]];
    return;
  }

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
    if ([relativePath hasSuffix:@".js.map"]) {
      response.statusCode = HttpStatusOK;
      [response setHeader:@"no-store, no-cache, must-revalidate"
                   forKey:@"Cache-Control"];
      [response setHeader:@"no-cache" forKey:@"Pragma"];
      [response setHeader:@"0" forKey:@"Expires"];
      [response setJsonBody:@{
        @"version" : @3,
        @"file" : [relativePath lastPathComponent] ?: @"bundle.js",
        @"sources" : @[],
        @"names" : @[],
        @"mappings" : @""
      }];
      return;
    }

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
  [response setHeader:@"no-store, no-cache, must-revalidate"
               forKey:@"Cache-Control"];
  [response setHeader:@"no-cache" forKey:@"Pragma"];
  [response setHeader:@"0" forKey:@"Expires"];
  // Objective-J runtime compiles/executes modules dynamically and requires
  // `unsafe-eval`. Restrict this relaxation to UI assets only.
  [response setHeader:@"default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;"
               forKey:@"Content-Security-Policy"];
  [response setBodyData:data];

  PDS_LOG_DEBUG(@"CappuccinoUIHandler served %@ from %@", path, filePath);
}

@end
