#import "App/OAuthDemo/OAuthDemoHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "App/PDSController.h"
#import "Debug/PDSLogger.h"
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
    if ([path isEqualToString:@"/oauth-demo"] || [path isEqualToString:@"/oauth-demo/"] || [path isEqualToString:@"/oauth-demo/callback"]) {
        path = @"/oauth-demo/index.html";
    }

    NSString *fileName = [path lastPathComponent];
    NSString *ext = [fileName pathExtension];
    
    NSString *assetsDir = [self assetsPath];
    if (!assetsDir) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"OAuth Demo assets not found"}];
        return;
    }

    NSString *filePath = [assetsDir stringByAppendingPathComponent:fileName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        response.statusCode = 404;
        [response setJsonBody:@{@"error": @"File not found", @"path": path, @"checked": filePath}];
        return;
    }

    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:&error];
    if (error || !data) {
        response.statusCode = 500;
        [response setJsonBody:@{@"error": @"Failed to read file", @"details": error.localizedDescription}];
        return;
    }

    if ([ext isEqualToString:@"html"]) response.contentType = @"text/html; charset=utf-8";
    else if ([ext isEqualToString:@"js"]) response.contentType = @"application/javascript; charset=utf-8";
    else if ([ext isEqualToString:@"css"]) response.contentType = @"text/css; charset=utf-8";
    else response.contentType = @"application/octet-stream";

    [response setBodyData:data];
}

@end
