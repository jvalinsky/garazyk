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

- (void)testLatencyHistogramExport {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];
    [metrics observeRequestLatency:0.003 method:@"GET" endpoint:@"/xrpc/com.atproto.repo.getRecord" status:200];
    [metrics observeRequestLatency:0.150 method:@"GET" endpoint:@"/xrpc/com.atproto.repo.getRecord" status:200];
    [metrics observeRequestLatency:2.000 method:@"POST" endpoint:@"/xrpc/com.atproto.repo.createRecord" status:200];

    NSString *output = [metrics exportPrometheus];

    XCTAssertTrue([output containsString:@"# TYPE pds_http_request_duration_seconds histogram"],
                  @"Missing histogram TYPE line");
    XCTAssertTrue([output containsString:@"pds_http_request_duration_seconds_bucket{method=\"get\",endpoint=\"com.atproto.repo.getRecord\",status=\"200\",le=\"0.005\"}"],
                  @"Missing 5ms bucket line");
    XCTAssertTrue([output containsString:@"pds_http_request_duration_seconds_bucket{method=\"get\",endpoint=\"com.atproto.repo.getRecord\",status=\"200\",le=\"+Inf\"} 2"],
                  @"+Inf bucket should equal total count");
    XCTAssertTrue([output containsString:@"pds_http_request_duration_seconds_sum{method=\"get\",endpoint=\"com.atproto.repo.getRecord\",status=\"200\"}"],
                  @"Missing sum line");
    XCTAssertTrue([output containsString:@"pds_http_request_duration_seconds_count{method=\"get\",endpoint=\"com.atproto.repo.getRecord\",status=\"200\"} 2"],
                  @"Count should be 2");

    XCTAssertTrue([output containsString:@"pds_http_request_duration_seconds_bucket{method=\"post\",endpoint=\"com.atproto.repo.createRecord\",status=\"200\",le=\"+Inf\"} 1"],
                  @"POST +Inf bucket should be 1");
}

- (void)testProcessMetricsExport {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];
    XCTAssertGreaterThan(metrics.serverStartTime, 0, @"serverStartTime should be set");

    NSString *output = [metrics exportPrometheus];
    XCTAssertTrue([output containsString:@"process_start_time_seconds"],
                  @"Missing process_start_time_seconds");
    XCTAssertTrue([output containsString:@"process_uptime_seconds"],
                  @"Missing process_uptime_seconds");
    XCTAssertTrue([output containsString:@"process_resident_memory_bytes"],
                  @"Missing process_resident_memory_bytes");
}

- (void)testConcurrentIncrementsAreValid {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];
    NSInteger iterations = 1000;
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    for (NSInteger i = 0; i < iterations; i++) {
        dispatch_group_async(group, queue, ^{
            [metrics incrementHttpRequestsForMethod:@"GET" endpoint:@"/test" status:200];
        });
    }

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    NSString *output = [metrics exportPrometheus];
    NSString *expected = [NSString stringWithFormat:@"pds_http_requests_total{method=\"get\"} %ld", (long)iterations];
    XCTAssertTrue([output containsString:expected],
                  @"Expected %ld increments, got output: %@", (long)iterations, output);
}

- (void)testSubsystemMetricsExport {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];

    // Firehose metrics
    [metrics setFirehoseSubscribers:5];
    [metrics incrementFirehoseEvent:@"commit"];
    [metrics incrementFirehoseEvent:@"commit"];
    [metrics incrementFirehoseEvent:@"identity"];
    [metrics setFirehoseSeq:42];

    // Rate limit metrics
    [metrics incrementRateLimitRejection:@"ip"];
    [metrics incrementRateLimitRejection:@"ip"];
    [metrics incrementRateLimitRejection:@"did"];

    // Repo commits
    [metrics incrementRepoCommits];
    [metrics incrementRepoCommits];
    [metrics incrementRepoCommits];

    NSString *output = [metrics exportPrometheus];

    XCTAssertTrue([output containsString:@"pds_firehose_subscribers 5"],
                  @"Missing firehose_subscribers");
    XCTAssertTrue([output containsString:@"pds_firehose_seq 42"],
                  @"Missing firehose_seq");
    XCTAssertTrue([output containsString:@"pds_firehose_events_total{kind=\"commit\"} 2"],
                  @"Missing commit events");
    XCTAssertTrue([output containsString:@"pds_firehose_events_total{kind=\"identity\"} 1"],
                  @"Missing identity events");
    XCTAssertTrue([output containsString:@"pds_rate_limit_rejections_total{type=\"ip\"} 2"],
                  @"Missing IP rejections");
    XCTAssertTrue([output containsString:@"pds_rate_limit_rejections_total{type=\"did\"} 1"],
                  @"Missing DID rejections");
    XCTAssertTrue([output containsString:@"pds_repo_commits_total 3"],
                  @"Missing repo_commits_total");
}

- (void)testAuthMetricsExport {
    PDSMetrics *metrics = [[PDSMetrics alloc] init];

    // Auth failures
    [metrics incrementAuthFailure:@"invalid_token"];
    [metrics incrementAuthFailure:@"invalid_token"];
    [metrics incrementAuthFailure:@"invalid_signature"];
    [metrics incrementAuthFailure:@"account_suspended"];

    // OAuth grants
    [metrics incrementOAuthTokenGrant:@"authorization_code"];
    [metrics incrementOAuthTokenGrant:@"authorization_code"];
    [metrics incrementOAuthTokenGrant:@"refresh_token"];

    // Active sessions
    [metrics setActiveAuthSessions:7];

    NSString *output = [metrics exportPrometheus];

    XCTAssertTrue([output containsString:@"pds_auth_failures_total{reason=\"invalid_token\"} 2"],
                  @"Missing invalid_token failures");
    XCTAssertTrue([output containsString:@"pds_auth_failures_total{reason=\"invalid_signature\"} 1"],
                  @"Missing invalid_signature failures");
    XCTAssertTrue([output containsString:@"pds_auth_failures_total{reason=\"account_suspended\"} 1"],
                  @"Missing account_suspended failures");
    XCTAssertTrue([output containsString:@"pds_oauth_token_grants_total{grant_type=\"authorization_code\"} 2"],
                  @"Missing authorization_code grants");
    XCTAssertTrue([output containsString:@"pds_oauth_token_grants_total{grant_type=\"refresh_token\"} 1"],
                  @"Missing refresh_token grants");
    XCTAssertTrue([output containsString:@"pds_auth_sessions_active 7"],
                  @"Missing active sessions");
}

@end

NS_ASSUME_NONNULL_END
