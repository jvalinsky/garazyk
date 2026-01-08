//
//  fuzz_http.mm
//  Fuzzing harness for HTTP request parsing
//

#import <Foundation/Foundation.h>
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/HttpServer.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 100000) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];

        NSString *rawRequest = [[NSString alloc] initWithData:inputData
                                                      encoding:NSUTF8StringEncoding];
        if (!rawRequest) {
            rawRequest = [[NSString alloc] initWithData:inputData
                                               encoding:NSISOLatin1StringEncoding];
        }

        if (rawRequest) {
            HttpRequest *request = [HttpRequest requestWithData:inputData];

            HttpMethod method = request.method;
            NSString *methodString = request.methodString;
            NSString *path = request.path;
            NSString *version = request.version;
            NSDictionary *headers = request.headers;
            NSData *body = request.body;
            NSDictionary *queryParams = request.queryParams;

            (void)method;
            (void)methodString;
            (void)queryParams;

            if (path) {
                NSRange queryRange = [path rangeOfString:@"?"];
                if (queryRange.location != NSNotFound) {
                    NSString *query = [path substringFromIndex:queryRange.location + 1];
                    (void)query;
                }
            }

            NSString *contentLength = [headers objectForKey:@"Content-Length"];
            (void)contentLength;

            HttpResponse *response = [[HttpResponse alloc] init];
            response.statusCode = HttpStatusOK;
            response.statusMessage = @"OK";
            response.contentType = @"application/json";
            NSData *responseData = [response serialize];
            (void)responseData;
        }

        NSString *partialRequest = [[NSString alloc] initWithBytes:data
                                                            length:MIN(size, 50)
                                                          encoding:NSUTF8StringEncoding];
        if (partialRequest) {
            HttpRequest *partial = [HttpRequest requestWithData:[partialRequest dataUsingEncoding:NSUTF8StringEncoding]];
            (void)partial;
        }

        return 0;
    }
}

#ifndef LIBFUZZER
int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <input_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "Cannot open file: %s\n", argv[1]);
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long fileSize = ftell(f);
    fseek(f, 0, SEEK_SET);

    uint8_t *data = (uint8_t *)malloc(fileSize);
    size_t readSize = fread(data, 1, fileSize, f);
    fclose(f);

    int result = LLVMFuzzerTestOneInput(data, readSize);
    free(data);

    return result;
}
#endif
