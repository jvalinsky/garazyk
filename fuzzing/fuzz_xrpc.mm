//
//  fuzz_xrpc.mm
//  Fuzzing harness for XRPC handler
//

#import <Foundation/Foundation.h>
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size == 0 || size > 100000) {
        return 0;
    }

    @autoreleasepool {
        NSData *inputData = [NSData dataWithBytes:data length:size];

        HttpRequest *request = [HttpRequest requestWithData:inputData];

        HttpMethod method = request.method;
        NSString *methodString = request.methodString;
        NSString *path = request.path;
        NSString *queryString = request.queryString;
        NSDictionary *headers = request.headers;
        NSData *body = request.body;
        NSDictionary *jsonBody = request.jsonBody;

        (void)method;
        (void)methodString;
        (void)queryString;
        (void)jsonBody;

        if (method == HttpMethodUnknown && path.length == 0 && headers.count == 0) {
            return 0;
        }

        HttpResponse *response = [[HttpResponse alloc] init];
        response.statusCode = HttpStatusOK;
        response.body = body;

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
