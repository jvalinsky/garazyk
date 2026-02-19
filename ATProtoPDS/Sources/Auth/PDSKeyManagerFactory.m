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
#else
#import "PDSOpenSSLSessionKeyManager.h"
#endif

@implementation PDSKeyManagerFactory

+ (id<PDSKeyManager>)createKeyManagerWithDatabase:(PDSDatabase *)database {
#if defined(__APPLE__) && !defined(GNUSTEP)
    return [[PDSAppleKeyManager alloc] initWithDatabase:database serviceIdentifier:@"com.atproto.pds.keys"];
#else
    return [[PDSOpenSSLSessionKeyManager alloc] initWithDatabase:database];
#endif
}

@end
