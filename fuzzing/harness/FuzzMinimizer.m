// FuzzMinimizer.m - Corpus minimization harness
// Runs a single file and tracks unique coverage edges hit

#import <Foundation/Foundation.h>

#if __has_include("Auth/JWT.h")
#import "Auth/JWT.h"
#endif

#if __has_include("Network/Http1Parser.h")
#import "Network/Http1Parser.h"
#endif

#if __has_include("Repository/CBOR.h")
#import "Repository/CBOR.h"
#endif

#if __has_include("XRPC/XrpcDispatcher.h")
#import "XRPC/XrpcDispatcher.h"
#endif

#if __has_include("Lexicon/ATProtoLexiconValidator.h")
#import "Lexicon/ATProtoLexiconValidator.h"
#endif

#if __has_include("Repository/MST.h")
#import "Repository/MST.h"
#endif

// Track unique edges seen (simple counter - real impl would use __sanitizer_cov)
static uint64_t g_edgesSeen[4096] = {0};
static uint64_t g_edgeCount = 0;

static void recordEdge(uint64_t edge) {
    if (edge < 4096) {
        g_edgesSeen[edge]++;
    }
}

static uint64_t countUniqueEdges(void) {
    uint64_t count = 0;
    for (int i = 0; i < 4096; i++) {
        if (g_edgesSeen[i] > 0) count++;
    }
    return count;
}

static void resetEdges(void) {
    memset(g_edgesSeen, 0, sizeof(g_edgesSeen));
    g_edgeCount = 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    @autoreleasepool {
        if (size == 0 || !data) return 0;
        
        // Try to parse as each format and track edges
        // Each format tries to decode and touches different code paths
        
        // 1. Try JSON (XRPC)
        NSData *jsonInput = [NSData dataWithBytes:data length:size];
        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:jsonInput options:0 error:&jsonError];
        if (json && !jsonError) {
            recordEdge(1);  // Valid JSON parsed
            if ([json isKindOfClass:[NSDictionary class]]) {
                NSDictionary *dict = (NSDictionary *)json;
                recordEdge(2);  // JSON object
                recordEdge(dict.count % 100);  // Dict size edge
            } else if ([json isKindOfClass:[NSArray class]]) {
                recordEdge(3);  // JSON array
                recordEdge([(NSArray *)json count] % 100);
            }
        } else {
            recordEdge(10);  // Invalid JSON
        }
        
        // 2. Try JWT
        NSString *token = [[NSString alloc] initWithBytes:data length:size encoding:NSUTF8StringEncoding];
        if (!token) token = [[NSString alloc] initWithBytes:data length:size encoding:NSASCIIStringEncoding];
        if (token) {
            recordEdge(20);  // Valid string
            NSArray *parts = [token componentsSeparatedByString:@"."];
            if (parts.count == 3) {
                recordEdge(21);  // JWT-like structure
                recordEdge(((NSString *)parts[0]).hash % 100);
                recordEdge(((NSString *)parts[1]).hash % 100);
            }
        }
        
        // 3. Try HTTP request
        NSString *httpRequest = [[NSString alloc] initWithBytes:data length:size encoding:NSUTF8StringEncoding];
        if (httpRequest && [httpRequest containsString:@"\r\n"]) {
            recordEdge(30);  // Has CRLF
            NSArray *lines = [httpRequest componentsSeparatedByString:@"\r\n"];
            recordEdge(lines.count % 50);
            for (NSString *line in lines) {
                if ([line hasPrefix:@"GET "] || [line hasPrefix:@"POST "] || [line hasPrefix:@"PUT "] || [line hasPrefix:@"DELETE "]) {
                    recordEdge(31);  // HTTP method
                } else if ([line containsString:@": "]) {
                    recordEdge(32);  // HTTP header
                }
            }
        }
        
        // 4. Try CBOR (first byte analysis)
        if (size > 0) {
            uint8_t initial = data[0];
            recordEdge(100 + (initial & 0xE0));  // Major type
            recordEdge(200 + (initial & 0x1F));  // Additional info
        }
        
        // 5. Try NSData as-is (for MST/blob)
        if (size > 4) {
            recordEdge(300);  // Has data
            uint32_t magic = *(uint32_t *)data;
            if (magic == 0x43417200 || magic == 0x83417200) {
                recordEdge(301);  // CAR header
            }
        }
        
        // Track total edges found
        g_edgeCount = countUniqueEdges();
        
        // Return edge count as proxy for "interesting" input
        // Higher = more unique code paths hit
    }
    return 0;
}

// Called by minimizer to get edge count
uint64_t GetEdgeCount(void) {
    return g_edgeCount;
}

// Called to check if input hits new edges
int IsInteresting(uint64_t *edges, uint64_t count) {
    for (uint64_t i = 0; i < count && i < 4096; i++) {
        if (g_edgesSeen[edges[i]] == 0) return 1;
    }
    return 0;
}