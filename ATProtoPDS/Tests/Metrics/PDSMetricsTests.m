#import <XCTest/XCTest.h>
#import "Metrics/PDSMetrics.h"

NS_ASSUME_NONNULL_BEGIN

@interface PDSMetricsTests : XCTestCase
@end

@implementation PDSMetricsTests

- (void)testPrometheusExportIncludesCounters {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];
    [metrics incrementHttpRequestsForMethod:@"GET" endpoint:@"/xrpc/com.atproto.repo.getRecord" status:200];
    [metrics incrementRepositoryCount];
    [metrics incrementBlobCount];
    [metrics addBlobBytes:42];
    [metrics setDatabaseSize:1024];
    [metrics setActiveConnections:3];

    NSString *output = [metrics exportPrometheus];
    XCTAssertTrue([output containsString:@"pds_http_requests_total{method=\"get\"}"]);
    XCTAssertTrue([output containsString:@"pds_http_requests_by_endpoint{endpoint=\"com.atproto.repo.getRecord\"}"]);
    XCTAssertTrue([output containsString:@"pds_http_responses_total{status=\"200\"}"]);
    XCTAssertTrue([output containsString:@"pds_repository_count 1"]);
    XCTAssertTrue([output containsString:@"pds_blob_count 1"]);
    XCTAssertTrue([output containsString:@"pds_blob_storage_bytes 42"]);
    XCTAssertTrue([output containsString:@"pds_database_size_bytes 1024"]);
    XCTAssertTrue([output containsString:@"pds_active_connections 3"]);
}

@end

NS_ASSUME_NONNULL_END
