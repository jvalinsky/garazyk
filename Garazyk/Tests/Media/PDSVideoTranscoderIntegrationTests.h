// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface VideoIntegrationTestBase : XCTestCase
@property (nonatomic, strong, nullable) NSURL *testVideoURL;
@end

NS_ASSUME_NONNULL_END
