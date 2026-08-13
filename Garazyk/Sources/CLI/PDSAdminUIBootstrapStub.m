// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file PDSAdminUIBootstrapStub.m
 @abstract Weak no-op stubs for PDSAdminUIStartHost.

 @discussion The real implementation lives in PDSAdminUIBootstrap.m and is
 linked only into the kaszlak binary (which also links ATProtoAdminUI).
 Runtime and AllTests keep these weak symbols so ServeCommand can call the
 hooks without a Runtime→AdminUI module edge. A strong definition from the
 bootstrap object overrides these when kaszlak is linked.
 */

#import "CLI/PDSAdminUIBootstrap.h"

NS_ASSUME_NONNULL_BEGIN

__attribute__((weak)) NSString * _Nullable PDSAdminUIResolvePassword(void) {
    return nil;
}

__attribute__((weak)) GZAdminUIHost * _Nullable PDSAdminUIStartHost(
    NSUInteger protocolPort,
    id<GZAdminUIPDSOverviewSnapshot> _Nullable overviewSnapshot,
    NSError * _Nullable * _Nullable error) {
    (void)protocolPort;
    (void)overviewSnapshot;
    (void)error;
    return nil;
}

NS_ASSUME_NONNULL_END
