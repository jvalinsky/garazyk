#import "Video/VideoRemoteBlobUploader.h"
#import "Debug/PDSLogger.h"

@implementation VideoRemoteBlobUploader

- (instancetype)initWithPDSURL:(NSString *)pdsURL {
    self = [super init];
    if (self) {
        _pdsURL = [pdsURL copy];
    }
    return self;
}

- (nullable NSDictionary *)uploadBlob:(NSData *)blobData
                             mimeType:(NSString *)mimeType
                          serviceAuth:(nullable NSString *)token
                                error:(NSError **)error {
    NSString *url = [NSString stringWithFormat:@"%@/xrpc/com.atproto.repo.uploadBlob", _pdsURL];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = blobData;
    [request setValue:mimeType forHTTPHeaderField:@"Content-Type"];

    if (token) {
        [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    }

    __block NSDictionary *result = nil;
    __block NSError *blockError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
        if (err) {
            blockError = err;
            dispatch_semaphore_signal(sema);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode != 200) {
            blockError = [NSError errorWithDomain:@"com.atproto.video.uploader"
                                             code:httpResponse.statusCode
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"PDS returned HTTP %ld", (long)httpResponse.statusCode]}];
            dispatch_semaphore_signal(sema);
            return;
        }

        if (data) {
            NSError *jsonError = nil;
            result = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                blockError = jsonError;
            }
        }

        dispatch_semaphore_signal(sema);
    }] resume];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    if (error && blockError) {
        *error = blockError;
    }

    return result;
}

@end
