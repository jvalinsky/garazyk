//
//  PDSKeyManagerFactory.h
//  ATProtoPDS
//
//  Created by Jack Valinsky on 2/18/26.
//  Copyright (c) 2026 Jack Valinsky. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PDSKeyManagerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface PDSKeyManagerFactory : NSObject

+ (id<PDSKeyManager>)createKeyManagerWithDatabase:(PDSDatabase *)database;

@end

NS_ASSUME_NONNULL_END
