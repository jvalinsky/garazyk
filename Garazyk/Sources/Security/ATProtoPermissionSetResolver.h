// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class ATProtoServiceConfiguration;

NS_ASSUME_NONNULL_BEGIN

extern NSErrorDomain const ATProtoPermissionSetResolverErrorDomain;

/** Expands OAuth `include:` scopes into the concrete permissions in their
 * authenticated Lexicon permission-set documents. */
@interface ATProtoPermissionSetResolver : NSObject

+ (nullable NSString *)effectiveScopeForScope:(NSString *)scope
                                configuration:(ATProtoServiceConfiguration *)configuration
                                        error:(NSError **)error;

/** Testable schema-only variant. Each key is a permission-set NSID and each
 * value is its resolved Lexicon document. */
+ (nullable NSString *)effectiveScopeForScope:(NSString *)scope
                         permissionSetSchemas:(NSDictionary<NSString *, NSDictionary *> *)schemas
                                        error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
