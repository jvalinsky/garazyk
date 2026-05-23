#!/bin/bash
# SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
# SPDX-License-Identifier: Unlicense OR CC0-1.0
#
# scaffold-service.sh — Generate boilerplate for a new AT Protocol service binary.
#
# Usage: scaffold-service.sh <service-name> <class-prefix> <default-port>
# Example: scaffold-service.sh labeler PDSLabeler 2591
#
# Creates:
#   Garazyk/Binaries/<name>/main.m
#   Garazyk/Sources/<Module>/<Prefix>Runtime.h
#   Garazyk/Sources/<Module>/<Prefix>Runtime.m
#   Garazyk/Sources/Network/<Name>XrpcRoutePack.h
#   Garazyk/Sources/Network/<Name>XrpcRoutePack.m
#
# Does NOT modify existing files (CMakeLists.txt, project.yml, Docker, etc.)
# — those must be updated manually per the skill checklist.

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <service-name> <class-prefix> <default-port>"
    echo "Example: $0 labeler PDSLabeler 2591"
    exit 1
fi

SERVICE_NAME="$1"
CLASS_PREFIX="$2"
DEFAULT_PORT="$3"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# Derive module name from class prefix (strip "PDS" prefix if present)
MODULE_NAME="${CLASS_PREFIX#PDS}"

# Capitalize first letter of module name for directory
MODULE_DIR="$(echo "${MODULE_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${MODULE_NAME:1}"

# Route pack name: capitalize first letter of service name
ROUTE_PACK_NAME="$(echo "${SERVICE_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${SERVICE_NAME:1}"

BINARY_DIR="${REPO_ROOT}/Garazyk/Binaries/${SERVICE_NAME}"
SOURCES_DIR="${REPO_ROOT}/Garazyk/Sources/${MODULE_DIR}"
NETWORK_DIR="${REPO_ROOT}/Garazyk/Sources/Network"

echo "Service:       ${SERVICE_NAME}"
echo "Class prefix:  ${CLASS_PREFIX}"
echo "Default port:  ${DEFAULT_PORT}"
echo "Module dir:    ${MODULE_DIR}"
echo "Route pack:    ${ROUTE_PACK_NAME}XrpcRoutePack"
echo ""

# ── Create directories ──────────────────────────────────────────────────────

mkdir -p "${BINARY_DIR}"
mkdir -p "${SOURCES_DIR}"

# ── main.m ──────────────────────────────────────────────────────────────────

cat > "${BINARY_DIR}/main.m" <<MAIN_EOF
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file main.m

 @brief Entry point for the ${SERVICE_NAME} server.

 @discussion A standalone AT Protocol service.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "${MODULE_DIR}/${CLASS_PREFIX}Runtime.h"
#import "Network/HttpServer.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/${ROUTE_PACK_NAME}XrpcRoutePack.h"
#if defined(GNUSTEP)
#import <curl/curl.h>
#endif
#import "Debug/GZLogger.h"
#import "Compat/PDSTypes.h"
#import "Compat/PlatformShims/CrashReporting/GZCrashReporter.h"
#import "Compat/PlatformShims/SignalHandling/GZSignalManager.h"

static const char *executable_name = "${SERVICE_NAME}";

void print_usage(void) {
    printf("Usage: %s <command> [options]\\n\\n", executable_name);
    printf("${SERVICE_NAME} - AT Protocol Service\\n\\n");
    printf("Commands:\\n");
    printf("  serve        Start server\\n");
    printf("  status       Show service status\\n");
    printf("  version      Show version\\n");
    printf("  help         Show this help\\n\\n");
    printf("Options:\\n");
    printf("  --port <number>       HTTP port (default: ${DEFAULT_PORT})\\n");
    printf("  --data-dir <path>     Data directory\\n");
    printf("  --config <path>       Configuration file path\\n");
    printf("  -v, --verbose         Enable debug logging\\n");
    printf("  -h, --help            Show this help\\n\\n");
}

void print_version(void) {
    printf("${SERVICE_NAME} (AT Protocol Service) 1.0.0\\n");
}

static int fail_with_usage(NSString *message) {
    if (message.length > 0) {
        fprintf(stderr, "Error: %s\\n\\n", [message UTF8String]);
    }
    print_usage();
    return 2;
}

int main(int argc, const char * argv[]) {
    [[GZSignalManager sharedManager] installIgnoredSignals];
    [GZCrashReporter installCrashHandlersWithExecutableName:"${SERVICE_NAME}"];
#if defined(GNUSTEP)
    curl_global_init(CURL_GLOBAL_ALL);
#endif
    @autoreleasepool {
        if (argc < 2) {
            return fail_with_usage(@"Missing command");
        }

        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command hasPrefix:@"-"]) {
            return fail_with_usage(@"Flags must follow the command name");
        }

        NSMutableArray<NSString *> *args = [NSMutableArray array];
        for (int i = 2; i < argc; i++) {
            [args addObject:[NSString stringWithUTF8String:argv[i]]];
        }

        if ([command isEqualToString:@"help"]) {
            print_usage();
            return 0;
        }
        if ([command isEqualToString:@"version"]) {
            print_version();
            return 0;
        }
        if ([args containsObject:@"--help"] || [args containsObject:@"-h"]) {
            print_usage();
            return 0;
        }

        NSUInteger port = ${DEFAULT_PORT};
        NSString *dataDir = nil;
        NSString *configPath = nil;
        BOOL verbose = NO;

        for (NSUInteger i = 0; i < args.count; i++) {
            NSString *arg = args[i];
            if ([arg isEqualToString:@"--port"] || [arg isEqualToString:@"-p"]) {
                if (i + 1 >= args.count) {
                    return fail_with_usage(@"Missing value for --port");
                }
                port = (NSUInteger)[args[++i] integerValue];
            } else if ([arg isEqualToString:@"--data-dir"]) {
                if (i + 1 >= args.count) {
                    return fail_with_usage(@"Missing value for --data-dir");
                }
                dataDir = args[++i];
            } else if ([arg isEqualToString:@"--config"] || [arg isEqualToString:@"-c"]) {
                if (i + 1 >= args.count) {
                    return fail_with_usage(@"Missing value for --config");
                }
                configPath = args[++i];
            } else if ([arg isEqualToString:@"--verbose"] || [arg isEqualToString:@"-v"]) {
                verbose = YES;
                [[GZLogger sharedLogger] setLogLevel:GZLogLevelDebug];
            } else if ([arg hasPrefix:@"-"]) {
                return fail_with_usage([NSString stringWithFormat:@"Unknown option: %@", arg]);
            } else {
                return fail_with_usage([NSString stringWithFormat:@"Unexpected argument: %@", arg]);
            }
        }

        if (![command isEqualToString:@"serve"] && ![command isEqualToString:@"status"]) {
            return fail_with_usage([NSString stringWithFormat:@"Unknown command: %@", command]);
        }

        if ([command isEqualToString:@"status"]) {
            NSURL *healthURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://localhost:%lu/_health", (unsigned long)port]];
            NSData *data = [NSData dataWithContentsOfURL:healthURL];
            if (!data) {
                printf("${SERVICE_NAME} status: NOT RUNNING (port %lu)\\n", (unsigned long)port);
                return 1;
            }
            printf("${SERVICE_NAME} status: RUNNING (port %lu)\\n", (unsigned long)port);
            return 0;
        }

        // Default data directory
        if (!dataDir) {
            dataDir = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)
                       firstObject];
            dataDir = [dataDir stringByAppendingPathComponent:@"${SERVICE_NAME}"];
        }

        // Ensure data directory exists
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:dataDir]) {
            NSError *dirError = nil;
            [fm createDirectoryAtPath:dataDir
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&dirError];
            if (dirError) {
                GZ_LOG_CORE_ERROR(@"Failed to create data directory: %@", dirError.localizedDescription);
                return 1;
            }
        }

        // Initialize runtime
        ${CLASS_PREFIX}Runtime *runtime = [[${CLASS_PREFIX}Runtime alloc] initWithDataDirectory:dataDir];

        // Create HTTP server
        HttpServer *server = [HttpServer serverWithPort:port];

        // Health endpoint
        [server addRoute:@"GET"
                    path:@"/_health"
                 handler:^(HttpRequest *request, HttpResponse *response) {
            response.statusCode = 200;
            response.contentType = @"application/json";
            [response setBodyString:@"{\"status\":\"ok\"}"];
        }];

        // Register XRPC routes
        ${ROUTE_PACK_NAME}XrpcRoutePack *routePack = [[${ROUTE_PACK_NAME}XrpcRoutePack alloc] initWithRuntime:runtime];
        [routePack registerRoutesWithServer:server];

        // Start runtime
        NSError *runtimeError = nil;
        if (![runtime startWithError:&runtimeError]) {
            GZ_LOG_CORE_ERROR(@"Failed to start runtime: %@", runtimeError.localizedDescription ?: @"unknown error");
            return 1;
        }

        // Start server
        NSError *startError = nil;
        if (![server startWithError:&startError]) {
            GZ_LOG_CORE_ERROR(@"Failed to start server: %@", startError.localizedDescription ?: @"unknown error");
            return 1;
        }

        printf("${SERVICE_NAME} server started on port %lu\\n", (unsigned long)port);
        printf("Data directory: %s\\n", [dataDir UTF8String]);
        printf("\\nPress Ctrl+C to stop.\\n");

        // Run the run loop
        [[NSRunLoop currentRunLoop] run];

        // Cleanup
        [runtime stop];
        [server stop];
    }
    return 0;
}
MAIN_EOF

echo "Created: ${BINARY_DIR}/main.m"

# ── Runtime header ──────────────────────────────────────────────────────────

cat > "${SOURCES_DIR}/${CLASS_PREFIX}Runtime.h" <<RUNTIME_H_EOF
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ${CLASS_PREFIX}Runtime.h

 @brief Runtime for the ${SERVICE_NAME} service.

 @discussion Owns the service lifecycle, database connections, and handler objects.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ${CLASS_PREFIX}Runtime : NSObject

/*! @brief Data directory for persistent storage. */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/*!
 @brief Initialize with a data directory.

 @param dataDirectory Path for persistent storage.
 */
- (instancetype)initWithDataDirectory:(NSString *)dataDirectory NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/*!
 @brief Start the service runtime.

 @param error Error output parameter.
 @return YES if startup succeeded, NO otherwise.
 */
- (BOOL)startWithError:(NSError **)error;

/*! @brief Stop the service runtime. */
- (void)stop;

@end

NS_ASSUME_NONNULL_END
RUNTIME_H_EOF

echo "Created: ${SOURCES_DIR}/${CLASS_PREFIX}Runtime.h"

# ── Runtime implementation ──────────────────────────────────────────────────

cat > "${SOURCES_DIR}/${CLASS_PREFIX}Runtime.m" <<RUNTIME_M_EOF
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "${CLASS_PREFIX}Runtime.h"
#import "Debug/GZLogger.h"

@implementation ${CLASS_PREFIX}Runtime

- (instancetype)initWithDataDirectory:(NSString *)dataDirectory {
    self = [super init];
    if (self) {
        _dataDirectory = [dataDirectory copy];
    }
    return self;
}

- (BOOL)startWithError:(NSError **)error {
    GZ_LOG_CORE_INFO(@"${CLASS_PREFIX}Runtime starting with data dir: %@", self.dataDirectory);
    // TODO: Initialize database, handlers, and other dependencies
    return YES;
}

- (void)stop {
    GZ_LOG_CORE_INFO(@"${CLASS_PREFIX}Runtime stopping");
    // TODO: Clean up resources
}

@end
RUNTIME_M_EOF

echo "Created: ${SOURCES_DIR}/${CLASS_PREFIX}Runtime.m"

# ── Route pack header ──────────────────────────────────────────────────────

cat > "${NETWORK_DIR}/${ROUTE_PACK_NAME}XrpcRoutePack.h" <<ROUTE_H_EOF
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ${ROUTE_PACK_NAME}XrpcRoutePack.h

 @brief Registers XRPC routes for the ${SERVICE_NAME} service.
 */

#import <Foundation/Foundation.h>

@class HttpServer;
@class ${CLASS_PREFIX}Runtime;

NS_ASSUME_NONNULL_BEGIN

@interface ${ROUTE_PACK_NAME}XrpcRoutePack : NSObject

- (instancetype)initWithRuntime:(${CLASS_PREFIX}Runtime *)runtime NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)registerRoutesWithServer:(HttpServer *)server;

@end

NS_ASSUME_NONNULL_END
ROUTE_H_EOF

echo "Created: ${NETWORK_DIR}/${ROUTE_PACK_NAME}XrpcRoutePack.h"

# ── Route pack implementation ──────────────────────────────────────────────

cat > "${NETWORK_DIR}/${ROUTE_PACK_NAME}XrpcRoutePack.m" <<ROUTE_M_EOF
// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "${ROUTE_PACK_NAME}XrpcRoutePack.h"
#import "${MODULE_DIR}/${CLASS_PREFIX}Runtime.h"
#import "Network/HttpServer.h"
#import "Network/XrpcHandler.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Debug/GZLogger.h"

@implementation ${ROUTE_PACK_NAME}XrpcRoutePack

- (instancetype)initWithRuntime:(${CLASS_PREFIX}Runtime *)runtime {
    self = [super init];
    if (self) {
        _runtime = runtime;
    }
    return self;
}

- (void)registerRoutesWithServer:(HttpServer *)server {
    XrpcDispatcher *dispatcher = [XrpcDispatcher sharedDispatcher];

    // TODO: Register XRPC methods
    // [dispatcher registerMethod:@"com.atproto.<domain>.<method>"
    //                    handler:^(HttpRequest *request, HttpResponse *response) {
    //     // Handle the request
    // }];

    // TODO: Register HTTP routes (non-XRPC)
    // [server addRoute:@"GET"
    //             path:@"/api/${SERVICE_NAME}/status"
    //          handler:^(HttpRequest *request, HttpResponse *response) {
    //     response.statusCode = 200;
    //     response.contentType = @"application/json";
    //     [response setBodyString:@"{\"status\":\"ok\"}"];
    // }];
}

@end
ROUTE_M_EOF

echo "Created: ${NETWORK_DIR}/${ROUTE_PACK_NAME}XrpcRoutePack.m"

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "Scaffolding complete. Files created:"
echo "  ${BINARY_DIR}/main.m"
echo "  ${SOURCES_DIR}/${CLASS_PREFIX}Runtime.h"
echo "  ${SOURCES_DIR}/${CLASS_PREFIX}Runtime.m"
echo "  ${NETWORK_DIR}/${ROUTE_PACK_NAME}XrpcRoutePack.h"
echo "  ${NETWORK_DIR}/${ROUTE_PACK_NAME}XrpcRoutePack.m"
echo ""
echo "Next steps (see designing-atproto-service skill):"
echo "  1. Update CMakeLists.txt — add_executable + link libs"
echo "  2. Update project.yml — XcodeGen tool target"
echo "  3. Update docker/Dockerfile.gnustep — build target + COPY"
echo "  4. Update scripts/stage-docker-binaries.sh — BINARIES array"
echo "  5. Update docker/local-network/Dockerfile.local — COPY"
echo "  6. Add XRPC method handlers to the route pack"
echo "  7. Add database migrations (if needed)"
echo "  8. Write tests and register in test_main.m"
