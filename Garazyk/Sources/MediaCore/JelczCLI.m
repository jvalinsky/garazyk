// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file JelczCLI.m

 @brief Implementation of shared jelcz CLI utility functions.
 */

#import "JelczCLI.h"
#import <stdio.h>

void JelczPrintUsage(void) {
    printf("Usage: jelcz <command> [options]\n\n");
    printf("Jelcz - Standalone AT Protocol Video Processing Service\n\n");
    printf("Commands:\n");
    printf("  serve        Start video processing service\n");
    printf("  status       Query service status\n");
    printf("  version      Show version info\n");
    printf("  help         Show this help\n\n");
    printf("Options:\n");
    printf("  --port <number>       HTTP API port (default: 2586)\n");
    printf("  --pds-url <url>       PDS URL for blob upload (default: http://localhost:2583)\n");
    printf("  --data-dir <path>     Data directory for database\n");
    printf("  --blob-dir <path>     Blob storage directory\n");
    printf("  --did <did>           Service DID for Service Auth\n");
    printf("  --s3-bucket <name>    S3 bucket for blob storage\n");
    printf("  --s3-region <region>  S3 region (default: us-east-1)\n");
    printf("  --s3-endpoint <url>   S3-compatible endpoint URL\n");
    printf("  --hls-dir <path>      HLS output directory\n");
    printf("  --hls-base-url <url>  Base URL for HLS playlist URLs\n");
    printf("  --hls-1080p           Include 1080p HLS variant\n");
    printf("  -v, --verbose         Enable debug logging\n");
    printf("  -h, --help            Show this help\n\n");
}
