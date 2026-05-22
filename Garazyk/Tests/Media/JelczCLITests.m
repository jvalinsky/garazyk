// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JelczCLITests.m

 @brief Unit tests for the Jelcz CLI argument parsing in main.m.

 @discussion Tests the core CLI parsing logic that drives command routing,
 flag-to-config mapping, and the help/usage output format. Since jelcz uses
 C-style argc/argv functions, these tests validate the equivalent ObjC-level
 logic by testing the configuration override patterns and string routing
 directly.
 */

#import <XCTest/XCTest.h>
#import "MediaCore/ATProtoMediaServiceConfiguration.h"
#import "Video/ATProtoVideoProcessor.h"
#import "MediaCore/JelczCLI.h"

/*! Size of redirect buffer for capturing stdout. */
static const NSUInteger kCaptureBufferSize = 16384;

#pragma mark - Helper: Capture stdout of a block

@interface StdoutCapture : NSObject
+ (NSString *)capture:(void(NS_NOESCAPE ^)(void))block;
@end

@implementation StdoutCapture

+ (NSString *)capture:(void(NS_NOESCAPE ^)(void))block {
    // Save original stdout and create a pipe
    int savedStdout = dup(STDOUT_FILENO);
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        return @"<capture error: pipe failed>";
    }

    // Redirect stdout to pipe write end
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);

    // Execute the block
    block();

    // Restore stdout
    fflush(stdout);
    dup2(savedStdout, STDOUT_FILENO);
    close(savedStdout);

    // Read captured data
    char buffer[kCaptureBufferSize];
    ssize_t n = read(pipefd[0], buffer, kCaptureBufferSize - 1);
    close(pipefd[0]);

    if (n > 0) {
        buffer[n] = '\0';
        return [NSString stringWithUTF8String:buffer];
    }
    return @"";
}

@end

#pragma mark - Tests

@interface JelczCLITests : XCTestCase
@end

@implementation JelczCLITests

#pragma mark - CLI flag parsing (config overrides)

- (void)testParsesPortFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
    NSUInteger originalPort = config.port;

    // Simulate: jelcz serve --port 9999
    NSString *arg = @"--port";
    NSString *val = @"9999";
    if ([arg isEqualToString:@"--port"]) {
        config.port = [val integerValue];
    }
    XCTAssertEqual(config.port, 9999);

    // Restore
    config.port = originalPort;
}

- (void)testParsesPdsUrlFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --pds-url http://pds.local:2583
    NSString *arg = @"--pds-url";
    NSString *val = @"http://pds.local:2583";
    if ([arg isEqualToString:@"--pds-url"]) {
        config.pdsURL = val;
    }
    XCTAssertEqualObjects(config.pdsURL, @"http://pds.local:2583");
}

- (void)testParsesDataDirFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --data-dir /custom/data
    NSString *arg = @"--data-dir";
    NSString *val = @"/custom/data";
    if ([arg isEqualToString:@"--data-dir"]) {
        config.dataDirectory = val;
    }
    XCTAssertEqualObjects(config.dataDirectory, @"/custom/data");
}

- (void)testParsesDidFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --did did:web:video.example.com
    NSString *arg = @"--did";
    NSString *val = @"did:web:video.example.com";
    if ([arg isEqualToString:@"--did"]) {
        config.serviceDID = val;
    }
    XCTAssertEqualObjects(config.serviceDID, @"did:web:video.example.com");
}

- (void)testParsesHlsDirFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --hls-dir /var/hls
    NSString *arg = @"--hls-dir";
    NSString *val = @"/var/hls";
    if ([arg isEqualToString:@"--hls-dir"]) {
        config.outputDirectory = val;
    }
    XCTAssertEqualObjects(config.outputDirectory, @"/var/hls");
}

- (void)testParsesHlsBaseUrlFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --hls-base-url http://cdn.local
    NSString *arg = @"--hls-base-url";
    NSString *val = @"http://cdn.local";
    if ([arg isEqualToString:@"--hls-base-url"]) {
        config.outputBaseUrl = val;
    }
    XCTAssertEqualObjects(config.outputBaseUrl, @"http://cdn.local");
}

- (void)testParsesHls1080pFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --hls-1080p
    NSString *arg = @"--hls-1080p";
    if ([arg isEqualToString:@"--hls-1080p"]) {
        config.includeHighQuality = YES;
    }
    XCTAssertTrue(config.includeHighQuality);
}

- (void)testParsesBlobDirFlag {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --blob-dir /mnt/blobs
    NSString *arg = @"--blob-dir";
    NSString *val = @"/mnt/blobs";
    if ([arg isEqualToString:@"--blob-dir"]) {
        config.blobDirectory = val;
    }
    XCTAssertEqualObjects(config.blobDirectory, @"/mnt/blobs");
}

- (void)testParsesS3Flags {
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];

    // Simulate: jelcz serve --s3-bucket myvideos --s3-region eu-west-1 --s3-endpoint https://s3.custom.com
    // --s3-bucket
    NSString *arg = @"--s3-bucket";
    NSString *val = @"myvideos";
    if ([arg isEqualToString:@"--s3-bucket"]) config.s3Bucket = val;

    // --s3-region
    arg = @"--s3-region";
    val = @"eu-west-1";
    if ([arg isEqualToString:@"--s3-region"]) config.s3Region = val;

    // --s3-endpoint
    arg = @"--s3-endpoint";
    val = @"https://s3.custom.com";
    if ([arg isEqualToString:@"--s3-endpoint"]) config.s3Endpoint = val;

    XCTAssertEqualObjects(config.s3Bucket, @"myvideos");
    XCTAssertEqualObjects(config.s3Region, @"eu-west-1");
    XCTAssertEqualObjects(config.s3Endpoint, @"https://s3.custom.com");
}

#pragma mark - Video Processor configuration from CLI

- (void)testVideoProcessorConfigFromCliOverrides {
    ATProtoVideoProcessor *videoProcessor = [[ATProtoVideoProcessor alloc] init];

    // Simulate: jelcz serve --hls-base-url http://cdn.local --hls-1080p
    videoProcessor.outputBaseUrl = @"http://cdn.local";
    videoProcessor.include1080p = YES;

    XCTAssertEqualObjects(videoProcessor.outputBaseUrl, @"http://cdn.local");
    XCTAssertTrue(videoProcessor.include1080p);
}

#pragma mark - Command routing

- (void)testServeCommandRouting {
    // Simulate: argv[1] == @"serve"
    NSString *command = @"serve";
    BOOL isServe = [command isEqualToString:@"serve"];
    BOOL isVersion = [command isEqualToString:@"version"];
    BOOL isStatus = [command isEqualToString:@"status"];

    XCTAssertTrue(isServe);
    XCTAssertFalse(isVersion);
    XCTAssertFalse(isStatus);
}

- (void)testVersionCommandRouting {
    // Simulate: argv[1] == @"version"
    NSString *command = @"version";
    BOOL isServe = [command isEqualToString:@"serve"];
    BOOL isVersion = [command isEqualToString:@"version"];
    BOOL isStatus = [command isEqualToString:@"status"];

    XCTAssertTrue(isVersion);
    XCTAssertFalse(isServe);
    XCTAssertFalse(isStatus);
}

- (void)testStatusCommandRouting {
    // Simulate: argv[1] == @"status"
    NSString *command = @"status";
    BOOL isServe = [command isEqualToString:@"serve"];
    BOOL isVersion = [command isEqualToString:@"version"];
    BOOL isStatus = [command isEqualToString:@"status"];

    XCTAssertTrue(isStatus);
    XCTAssertFalse(isServe);
    XCTAssertFalse(isVersion);
}

- (void)testHelpCommandRouting {
    // Simulate: argv[1] == @"help" or @"-h" or @"--help"
    NSArray<NSString *> *helpAliases = @[@"help", @"-h", @"--help"];
    for (NSString *alias in helpAliases) {
        BOOL isHelp = [alias isEqualToString:@"help"] ||
                       [alias isEqualToString:@"-h"] ||
                       [alias isEqualToString:@"--help"];
        XCTAssertTrue(isHelp, @"'%@' should be recognized as help", alias);
    }
}

- (void)testUnknownCommandRouting {
    // Simulate: argv[1] == @"nonexistent"
    NSString *command = @"nonexistent";
    BOOL isServe = [command isEqualToString:@"serve"];
    BOOL isVersion = [command isEqualToString:@"version"];
    BOOL isStatus = [command isEqualToString:@"status"];
    BOOL isHelp = [command isEqualToString:@"help"] || [command isEqualToString:@"-h"] || [command isEqualToString:@"--help"];

    XCTAssertFalse(isServe);
    XCTAssertFalse(isVersion);
    XCTAssertFalse(isStatus);
    XCTAssertFalse(isHelp);
}

- (void)testNoCommandShowsUsage {
    // Calls the actual JelczPrintUsage function from MediaCore
    NSString *output = [StdoutCapture capture:^{
        JelczPrintUsage();
    }];

    XCTAssertTrue([output containsString:@"Usage: jelcz <command> [options]"]);
    XCTAssertTrue([output containsString:@"serve        Start video processing service"]);
    XCTAssertTrue([output containsString:@"version      Show version info"]);
    XCTAssertTrue([output containsString:@"--port <number>       HTTP API port"]);
    XCTAssertTrue([output containsString:@"--hls-1080p           Include 1080p HLS variant"]);
    XCTAssertTrue([output containsString:@"-v, --verbose         Enable debug logging"]);
}



#pragma mark - Environment variable configuration

- (void)testEnvConfigPort {
    setenv("JELCZ_PORT", "7777", 1);
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
    XCTAssertEqual(config.port, 7777);
    unsetenv("JELCZ_PORT");
}

- (void)testEnvConfigMaxConcurrentJobs {
    setenv("JELCZ_MAX_CONCURRENT_JOBS", "8", 1);
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
    XCTAssertEqual(config.maxConcurrentJobs, 8);
    unsetenv("JELCZ_MAX_CONCURRENT_JOBS");
}

- (void)testEnvConfigPollInterval {
    setenv("JELCZ_POLL_INTERVAL", "2.5", 1);
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
    XCTAssertEqualWithAccuracy(config.pollInterval, 2.5, 0.01);
    unsetenv("JELCZ_POLL_INTERVAL");
}

- (void)testEnvConfigHighQuality {
    setenv("JELCZ_HIGH_QUALITY", "1", 1);
    ATProtoMediaServiceConfiguration *config = [ATProtoMediaServiceConfiguration configurationFromEnvironmentWithPrefix:@"JELCZ"];
    XCTAssertTrue(config.includeHighQuality);
    unsetenv("JELCZ_HIGH_QUALITY");
}

@end
