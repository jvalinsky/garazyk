// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
//
//  PDSKeyManagerFactory.m
//  ATProtoPDS
//
//  Created by Jack Valinsky on 2/18/26.
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import "PDSKeyManagerFactory.h"

#if defined(__APPLE__) && !defined(GNUSTEP)
#import "PDSAppleKeyManager.h"
#import "App/ATProtoServiceConfiguration.h"
#if defined(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
#import "PDSOpenSSLSessionKeyManager.h"
#endif
#else
#import "PDSOpenSSLSessionKeyManager.h"
#endif

@implementation PDSKeyManagerFactory

+ (id<PDSKeyManager>)createKeyManagerWithDatabase:(PDSDatabase *)database {
#if defined(__APPLE__) && !defined(GNUSTEP)
    if (![ATProtoServiceConfiguration sharedConfiguration].useKeychain) {
#if defined(PDS_OPENSSL_SESSION_KEY_MANAGER_AVAILABLE)
        return [[PDSOpenSSLSessionKeyManager alloc] initWithDatabase:database];
#else
        return [[PDSAppleKeyManager alloc] initWithDatabase:database serviceIdentifier:@"com.atproto.pds.keys"];
#endif
    }
    return [[PDSAppleKeyManager alloc] initWithDatabase:database serviceIdentifier:@"com.atproto.pds.keys"];
#else
    return [[PDSOpenSSLSessionKeyManager alloc] initWithDatabase:database];
#endif
}

@end
