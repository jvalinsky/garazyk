// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <XCTest/XCTest.h>

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

@interface GarazykUICommandResult : NSObject
@property(nonatomic, assign) int exitStatus;
@property(nonatomic, copy) NSString *standardOutput;
@property(nonatomic, copy) NSString *standardError;
@end

@implementation GarazykUICommandResult
@end

static NSString *GZUIStringFromFileDescriptor(int descriptor) {
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[4096];

    for (;;) {
        ssize_t count = read(descriptor, buffer, sizeof(buffer));
        if (count > 0) {
            [data appendBytes:buffer length:(NSUInteger)count];
            continue;
        }
        if (count < 0 && errno == EINTR) {
            continue;
        }
        break;
    }

    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return string ?: @"";
}

@interface GarazykUICommandTests : XCTestCase
@end

@implementation GarazykUICommandTests

- (NSString *)garazykUIExecutablePath {
    NSString *testExecutable = NSProcessInfo.processInfo.arguments.firstObject;
    if (![testExecutable hasPrefix:@"/"]) {
        testExecutable = [NSFileManager.defaultManager.currentDirectoryPath
            stringByAppendingPathComponent:testExecutable];
    }
    NSString *testsDirectory = [testExecutable stringByDeletingLastPathComponent];
    NSString *buildDirectory = [testsDirectory stringByDeletingLastPathComponent];
    return [[buildDirectory stringByAppendingPathComponent:@"bin"]
        stringByAppendingPathComponent:@"garazyk-ui"];
}

- (nullable GarazykUICommandResult *)runGarazykUIWithArguments:(NSArray<NSString *> *)arguments {
    NSString *executable = [self garazykUIExecutablePath];
    XCTAssertTrue([NSFileManager.defaultManager isExecutableFileAtPath:executable],
                  @"Expected AllTests dependency to build %@", executable);
    if (![NSFileManager.defaultManager isExecutableFileAtPath:executable]) {
        return nil;
    }

    int stdoutPipe[2];
    int stderrPipe[2];
    int stdoutPipeResult = pipe(stdoutPipe);
    int stderrPipeResult = pipe(stderrPipe);
    XCTAssertEqual(stdoutPipeResult, 0);
    XCTAssertEqual(stderrPipeResult, 0);
    if (stdoutPipeResult != 0 || stderrPipeResult != 0) {
        if (stdoutPipeResult == 0) {
            close(stdoutPipe[0]);
            close(stdoutPipe[1]);
        }
        if (stderrPipeResult == 0) {
            close(stderrPipe[0]);
            close(stderrPipe[1]);
        }
        return nil;
    }

    char **childArguments = calloc(arguments.count + 2, sizeof(char *));
    XCTAssertNotEqual(childArguments, NULL);
    if (!childArguments) {
        close(stdoutPipe[0]);
        close(stdoutPipe[1]);
        close(stderrPipe[0]);
        close(stderrPipe[1]);
        return nil;
    }

    childArguments[0] = (char *)executable.fileSystemRepresentation;
    for (NSUInteger index = 0; index < arguments.count; index++) {
        childArguments[index + 1] = (char *)arguments[index].fileSystemRepresentation;
    }

    pid_t child = fork();
    XCTAssertGreaterThanOrEqual(child, 0);
    if (child == 0) {
        dup2(stdoutPipe[1], STDOUT_FILENO);
        dup2(stderrPipe[1], STDERR_FILENO);
        close(stdoutPipe[0]);
        close(stdoutPipe[1]);
        close(stderrPipe[0]);
        close(stderrPipe[1]);
        execv(childArguments[0], childArguments);
        _exit(127);
    }

    free(childArguments);
    close(stdoutPipe[1]);
    close(stderrPipe[1]);
    if (child < 0) {
        close(stdoutPipe[0]);
        close(stderrPipe[0]);
        return nil;
    }

    int waitStatus = 0;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    BOOL timedOut = NO;
    for (;;) {
        pid_t waitResult = waitpid(child, &waitStatus, WNOHANG);
        if (waitResult == child) {
            break;
        }
        if (waitResult < 0) {
            if (errno == EINTR) {
                continue;
            }
            XCTFail(@"waitpid failed: %s", strerror(errno));
            break;
        }
        if ([deadline timeIntervalSinceNow] <= 0) {
            timedOut = YES;
            kill(child, SIGTERM);
            while (waitpid(child, &waitStatus, 0) < 0 && errno == EINTR) {
            }
            break;
        }
        usleep(10 * 1000);
    }

    NSString *standardOutput = GZUIStringFromFileDescriptor(stdoutPipe[0]);
    NSString *standardError = GZUIStringFromFileDescriptor(stderrPipe[0]);
    close(stdoutPipe[0]);
    close(stderrPipe[0]);

    if (timedOut) {
        XCTFail(@"garazyk-ui did not exit within the bounded process-test timeout");
        return nil;
    }
    XCTAssertTrue(WIFEXITED(waitStatus), @"garazyk-ui terminated unexpectedly: %@", standardError);
    if (!WIFEXITED(waitStatus)) {
        return nil;
    }

    GarazykUICommandResult *result = [[GarazykUICommandResult alloc] init];
    result.exitStatus = WEXITSTATUS(waitStatus);
    result.standardOutput = standardOutput;
    result.standardError = standardError;
    return result;
}

- (void)assertUsageOutput:(NSString *)output {
    XCTAssertTrue([output hasPrefix:@"Usage: garazyk-ui <command> [options]\n\n"]);
    XCTAssertTrue([output containsString:@"  serve       Start the UI service\n"]);
    XCTAssertTrue([output containsString:@"  --host <addr>       Override GARAZYK_UI_HOST\n"]);
    XCTAssertTrue([output containsString:@"  -v, --verbose       Enable debug logging\n"]);
}

- (void)testNoArgumentsPrintsUsageAndReturnsTwo {
    GarazykUICommandResult *result = [self runGarazykUIWithArguments:@[]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 2);
    XCTAssertEqualObjects(result.standardError, @"");
    [self assertUsageOutput:result.standardOutput];
}

- (void)testHelpPrintsUsageAndReturnsZero {
    GarazykUICommandResult *result = [self runGarazykUIWithArguments:@[@"help"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 0);
    XCTAssertEqualObjects(result.standardError, @"");
    [self assertUsageOutput:result.standardOutput];
}

- (void)testVersionPrintsVersionAndReturnsZero {
    GarazykUICommandResult *result = [self runGarazykUIWithArguments:@[@"version"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 0);
    XCTAssertEqualObjects(result.standardOutput, @"garazyk-ui 1.0.0\n");
    XCTAssertEqualObjects(result.standardError, @"");
}

- (void)testUnknownCommandPrintsErrorAndReturnsTwo {
    GarazykUICommandResult *result = [self runGarazykUIWithArguments:@[@"unknown-command"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 2);
    XCTAssertEqualObjects(result.standardError, @"Error: Unknown command: unknown-command\n\n");
    [self assertUsageOutput:result.standardOutput];
}

- (void)testServeOptionErrorsPrintUsageAndReturnTwo {
    NSArray<NSDictionary<NSString *, id> *> *cases = @[
        @{@"arguments": @[@"serve", @"--host"], @"error": @"Missing value for --host"},
        @{@"arguments": @[@"serve", @"--port"], @"error": @"Missing value for --port"},
        @{@"arguments": @[@"serve", @"--port", @"0"], @"error": @"Port must be a positive integer"},
        @{@"arguments": @[@"serve", @"--unknown"], @"error": @"Unknown option: --unknown"},
        @{@"arguments": @[@"serve", @"unexpected"], @"error": @"Unexpected argument: unexpected"},
    ];

    for (NSDictionary<NSString *, id> *testCase in cases) {
        GarazykUICommandResult *result = [self runGarazykUIWithArguments:testCase[@"arguments"]];
        XCTAssertNotNil(result);
        if (!result) continue;

        XCTAssertEqual(result.exitStatus, 2);
        NSString *expectedError =
            [NSString stringWithFormat:@"Error: %@\n\n", testCase[@"error"]];
        XCTAssertEqualObjects(result.standardError, expectedError);
        [self assertUsageOutput:result.standardOutput];
    }
}

- (void)testServeOptionsReachDeterministicBindFailure {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    XCTAssertGreaterThanOrEqual(listener, 0);
    if (listener < 0) return;

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    int bindResult = bind(listener, (struct sockaddr *)&address, sizeof(address));
    XCTAssertEqual(bindResult, 0);
    if (bindResult != 0) {
        close(listener);
        return;
    }
    int listenResult = listen(listener, 1);
    XCTAssertEqual(listenResult, 0);
    if (listenResult != 0) {
        close(listener);
        return;
    }

    socklen_t addressLength = sizeof(address);
    int nameResult = getsockname(listener, (struct sockaddr *)&address, &addressLength);
    XCTAssertEqual(nameResult, 0);
    if (nameResult != 0) {
        close(listener);
        return;
    }
    if (address.sin_port == 0) {
        close(listener);
        XCTFail(@"Expected the operating system to assign an ephemeral port");
        return;
    }

    NSString *port = [NSString stringWithFormat:@"%u", ntohs(address.sin_port)];
    GarazykUICommandResult *result = [self runGarazykUIWithArguments:@[
        @"serve", @"--host", @"127.0.0.1", @"--port", port, @"--verbose"
    ]];
    close(listener);

    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 1);
    XCTAssertTrue([result.standardError containsString:@"Failed to start UI service:"]);
    XCTAssertFalse([result.standardOutput containsString:@"garazyk-ui listening on"]);
    XCTAssertFalse([result.standardOutput containsString:@"Press Ctrl+C to stop."]);
}

- (void)testServeTerminatesSilentlyOnSIGTERM {
    int reservation = socket(AF_INET, SOCK_STREAM, 0);
    XCTAssertGreaterThanOrEqual(reservation, 0);
    if (reservation < 0) return;

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    int bindResult = bind(reservation, (struct sockaddr *)&address, sizeof(address));
    XCTAssertEqual(bindResult, 0);
    if (bindResult != 0) {
        close(reservation);
        return;
    }
    socklen_t addressLength = sizeof(address);
    int nameResult = getsockname(reservation, (struct sockaddr *)&address, &addressLength);
    XCTAssertEqual(nameResult, 0);
    if (nameResult != 0) {
        close(reservation);
        return;
    }
    NSString *port = [NSString stringWithFormat:@"%u", ntohs(address.sin_port)];
    close(reservation);

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self garazykUIExecutablePath]];
    task.arguments = @[@"serve", @"--host", @"127.0.0.1", @"--port", port];
    NSPipe *standardOutput = [NSPipe pipe];
    NSPipe *standardError = [NSPipe pipe];
    task.standardOutput = standardOutput;
    task.standardError = standardError;

    NSError *launchError = nil;
    XCTAssertTrue([task launchAndReturnError:&launchError], @"%@", launchError);
    if (!task.isRunning) return;

    usleep(250 * 1000);
    XCTAssertTrue(task.isRunning, @"garazyk-ui exited before it could receive SIGTERM");
    if (task.isRunning) {
        [task terminate];
    }
    [task waitUntilExit];

    NSString *output = [[NSString alloc] initWithData:
        [standardOutput.fileHandleForReading readDataToEndOfFile]
                                            encoding:NSUTF8StringEncoding] ?: @"";
    NSString *error = [[NSString alloc] initWithData:
        [standardError.fileHandleForReading readDataToEndOfFile]
                                           encoding:NSUTF8StringEncoding] ?: @"";
    XCTAssertEqual(task.terminationReason, NSTaskTerminationReasonExit);
    XCTAssertEqual(task.terminationStatus, 0);
    XCTAssertTrue([output containsString:@"garazyk-ui listening on"]);
    XCTAssertFalse([output containsString:@"Received SIGTERM"]);
    XCTAssertEqualObjects(error, @"");
}

@end
