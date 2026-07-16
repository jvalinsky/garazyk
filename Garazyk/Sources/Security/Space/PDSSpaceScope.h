// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

@class PDSSpaceURI;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceScopeErrorDomain;

typedef NS_ENUM(NSInteger, PDSSpaceScopeError) {
  PDSSpaceScopeErrorInvalidSyntax = 1,
  PDSSpaceScopeErrorInvalidValue,
};

extern NSString *const PDSSpaceActionReadSelf;
extern NSString *const PDSSpaceActionRead;
extern NSString *const PDSSpaceActionCreate;
extern NSString *const PDSSpaceActionUpdate;
extern NSString *const PDSSpaceActionDelete;

/** Parsed `space:` OAuth permission with proposal 0016 matching semantics. */
@interface PDSSpaceScope : NSObject

@property(nonatomic, readonly, copy) NSString *spaceType;
@property(nonatomic, readonly, copy) NSString *authority;
@property(nonatomic, readonly, copy) NSString *skey;
@property(nonatomic, readonly, copy) NSArray<NSString *> *collections;
@property(nonatomic, readonly, copy) NSArray<NSString *> *actions;
@property(nonatomic, readonly, copy) NSArray<NSString *> *manageOperations;

+ (nullable instancetype)scopeWithString:(NSString *)scope error:(NSError **)error;

/** Returns a copy in which `authority=self` is bound to an OAuth subject DID. */
- (nullable instancetype)scopeByResolvingSelfAuthorityForDID:(NSString *)did;

/** Tests a record or read target. `read_self` remains a caller-own-repo check. */
- (BOOL)matchesSpace:(PDSSpaceURI *)space
              action:(NSString *)action
          collection:(nullable NSString *)collection;

/** Tests an implementation-defined space-management capability. */
- (BOOL)matchesSpace:(PDSSpaceURI *)space manageOperation:(NSString *)manageOperation;

@end

NS_ASSUME_NONNULL_END
