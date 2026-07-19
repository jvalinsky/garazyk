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

@interface GermCommandResult : NSObject
@property(nonatomic, assign) int exitStatus;
@property(nonatomic, copy) NSString *standardOutput;
@property(nonatomic, copy) NSString *standardError;
@end

@implementation GermCommandResult
@end

static NSString *GermStringFromFileDescriptor(int descriptor) {
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

@interface GermCommandTests : XCTestCase
@end

@implementation GermCommandTests

- (NSString *)germExecutablePath {
    NSString *testExecutable = NSProcessInfo.processInfo.arguments.firstObject;
    if (![testExecutable hasPrefix:@"/"]) {
        testExecutable = [NSFileManager.defaultManager.currentDirectoryPath
            stringByAppendingPathComponent:testExecutable];
    }
    NSString *testsDirectory = [testExecutable stringByDeletingLastPathComponent];
    NSString *buildDirectory = [testsDirectory stringByDeletingLastPathComponent];
    return [[buildDirectory stringByAppendingPathComponent:@"bin"]
        stringByAppendingPathComponent:@"germ"];
}

- (nullable GermCommandResult *)runGermWithArguments:(NSArray<NSString *> *)arguments {
    NSString *executable = [self germExecutablePath];
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
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.5];
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

    NSString *standardOutput = GermStringFromFileDescriptor(stdoutPipe[0]);
    NSString *standardError = GermStringFromFileDescriptor(stderrPipe[0]);
    close(stdoutPipe[0]);
    close(stderrPipe[0]);

    if (timedOut) {
        XCTFail(@"germ did not exit within the bounded process-test timeout");
        return nil;
    }
    XCTAssertTrue(WIFEXITED(waitStatus), @"germ terminated unexpectedly: %@", standardError);
    if (!WIFEXITED(waitStatus)) {
        return nil;
    }

    GermCommandResult *result = [[GermCommandResult alloc] init];
    result.exitStatus = WEXITSTATUS(waitStatus);
    result.standardOutput = standardOutput;
    result.standardError = standardError;
    return result;
}

- (void)assertUsageOutput:(NSString *)output {
    XCTAssertTrue([output containsString:@"Usage: germ serve [options]\n\n"]);
    XCTAssertTrue([output containsString:@"Germ - Standalone AT Protocol E2EE Mailbox Service\n\n"]);
    XCTAssertTrue([output containsString:@"  --port <number>       HTTP API port (default: 8082)\n"]);
    XCTAssertTrue([output containsString:@"  --data-dir <path>     Data directory for database\n"]);
    XCTAssertTrue([output containsString:@"  -v, --verbose         Enable debug logging\n"]);
    XCTAssertTrue([output containsString:@"  -h, --help            Show this help\n\n"]);
}

- (void)testNoArgumentsPrintsUsageAndReturnsTwo {
    GermCommandResult *result = [self runGermWithArguments:@[]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 2);
    [self assertUsageOutput:result.standardOutput];
}

- (void)testHelpPrintsUsageAndReturnsZero {
    NSArray<NSString *> *helpFlags = @[@"help", @"-h", @"--help"];
    for (NSString *flag in helpFlags) {
        GermCommandResult *result = [self runGermWithArguments:@[flag]];
        XCTAssertNotNil(result, @"Failed for flag %@", flag);
        if (!result) continue;

        XCTAssertEqual(result.exitStatus, 0, @"Failed exit status for flag %@", flag);
        [self assertUsageOutput:result.standardOutput];
    }
}

- (void)testUnknownCommandPrintsErrorAndReturnsTwo {
    GermCommandResult *result = [self runGermWithArguments:@[@"unknown-command"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 2);
    XCTAssertTrue([result.standardError containsString:@"Unknown command: unknown-command\n"]);
}

- (void)testServeBindFailureReturnsOne {
    int listenSocket = socket(AF_INET, SOCK_STREAM, 0);
    XCTAssertGreaterThanOrEqual(listenSocket, 0);
    if (listenSocket < 0) {
        return;
    }

    int reuse = 1;
    setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(19879);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    int bindResult = bind(listenSocket, (struct sockaddr *)&address, sizeof(address));
    XCTAssertEqual(bindResult, 0);
    if (bindResult != 0) {
        close(listenSocket);
        return;
    }

    int listenResult = listen(listenSocket, 4);
    XCTAssertEqual(listenResult, 0);
    if (listenResult != 0) {
        close(listenSocket);
        return;
    }

    GermCommandResult *result = [self runGermWithArguments:@[@"serve", @"--port", @"19879"]];
    close(listenSocket);

    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 1);
}

@end
