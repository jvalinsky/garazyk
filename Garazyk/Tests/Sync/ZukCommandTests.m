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

@interface ZukCommandResult : NSObject
@property(nonatomic, assign) int exitStatus;
@property(nonatomic, copy) NSString *standardOutput;
@property(nonatomic, copy) NSString *standardError;
@end

@implementation ZukCommandResult
@end

static NSString *ZukStringFromFileDescriptor(int descriptor) {
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

@interface ZukCommandTests : XCTestCase
@end

@implementation ZukCommandTests

- (NSString *)zukExecutablePath {
    NSString *testExecutable = NSProcessInfo.processInfo.arguments.firstObject;
    if (![testExecutable hasPrefix:@"/"]) {
        testExecutable = [NSFileManager.defaultManager.currentDirectoryPath
            stringByAppendingPathComponent:testExecutable];
    }
    NSString *testsDirectory = [testExecutable stringByDeletingLastPathComponent];
    NSString *buildDirectory = [testsDirectory stringByDeletingLastPathComponent];
    return [[buildDirectory stringByAppendingPathComponent:@"bin"]
        stringByAppendingPathComponent:@"zuk"];
}

- (nullable ZukCommandResult *)runZukWithArguments:(NSArray<NSString *> *)arguments {
    NSString *executable = [self zukExecutablePath];
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

    NSString *standardOutput = ZukStringFromFileDescriptor(stdoutPipe[0]);
    NSString *standardError = ZukStringFromFileDescriptor(stderrPipe[0]);
    close(stdoutPipe[0]);
    close(stderrPipe[0]);

    if (timedOut) {
        XCTFail(@"zuk did not exit within the bounded process-test timeout");
        return nil;
    }
    XCTAssertTrue(WIFEXITED(waitStatus), @"zuk terminated unexpectedly: %@", standardError);
    if (!WIFEXITED(waitStatus)) {
        return nil;
    }

    ZukCommandResult *result = [[ZukCommandResult alloc] init];
    result.exitStatus = WEXITSTATUS(waitStatus);
    result.standardOutput = standardOutput;
    result.standardError = standardError;
    return result;
}

- (void)assertUsageOutput:(NSString *)output {
    XCTAssertTrue([output containsString:@"Usage: zuk <command> [options]\n\n"]);
    XCTAssertTrue([output containsString:@"Zuk - AT Protocol Relay Server\n\n"]);
    XCTAssertTrue([output containsString:@"Commands:\n"]);
    XCTAssertTrue([output containsString:@"  serve        Start relay server\n"]);
}

- (void)testNoArgumentsPrintsUsageAndReturnsTwo {
    ZukCommandResult *result = [self runZukWithArguments:@[]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 2);
    [self assertUsageOutput:result.standardOutput];
    XCTAssertTrue([result.standardError containsString:@"Error: Missing command\n\n"]);
}

- (void)testHelpCommandPrintsUsageAndReturnsZero {
    ZukCommandResult *result = [self runZukWithArguments:@[@"help"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 0);
    [self assertUsageOutput:result.standardOutput];
}

- (void)testVersionCommandPrintsVersionAndReturnsZero {
    ZukCommandResult *result = [self runZukWithArguments:@[@"version"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 0);
    XCTAssertTrue([result.standardOutput containsString:@"zuk (AT Protocol Relay) 1.0.0\n"]);
}

- (void)testUnknownCommandPrintsErrorAndReturnsTwo {
    ZukCommandResult *result = [self runZukWithArguments:@[@"unknown-cmd"]];
    XCTAssertNotNil(result);
    if (!result) return;

    XCTAssertEqual(result.exitStatus, 2);
    XCTAssertTrue([result.standardError containsString:@"Error: Unknown command: unknown-cmd\n\n"]);
}

@end
