// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoPermissionScope.h

 @abstract Structured parser and matcher for AT Protocol OAuth permission
 scope strings per the Permissions specification.

 @discussion Parses all six resource-type scopes (repo, rpc, blob, account,
 identity, include) and evaluates them against request context.  Designed to
 sit alongside PDSSpaceScope (which handles the Garazyk-specific space:
 extension) without replacing it.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ATProtoPermissionScopeErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoPermissionScopeError) {
  ATProtoPermissionScopeErrorInvalidSyntax = 1,
  ATProtoPermissionScopeErrorInvalidValue,
};

typedef NS_ENUM(NSInteger, ATProtoPermissionScopeResourceType) {
  ATProtoPermissionScopeResourceRepo,
  ATProtoPermissionScopeResourceRPC,
  ATProtoPermissionScopeResourceBlob,
  ATProtoPermissionScopeResourceAccount,
  ATProtoPermissionScopeResourceIdentity,
  ATProtoPermissionScopeResourceInclude,
};

/*!
 @class ATProtoPermissionScope

 @abstract Parsed AT Protocol OAuth permission scope with matching semantics.
 */
@interface ATProtoPermissionScope : NSObject

@property (nonatomic, readonly) ATProtoPermissionScopeResourceType resourceType;
@property (nonatomic, readonly, copy) NSString *resourceTypeString;

/* repo: collections (NSIDs or @"*"), actions (create/update/delete or nil = all) */
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *collections;
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *actions;

/* rpc: lxm (NSIDs or @"*"), aud (DID service ref or @"*") */
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *lxm;
@property (nonatomic, readonly, copy, nullable) NSString *aud;

/* blob: accept (MIME types or globs) */
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *accept;

/* account: attr (email/repo), action (read/manage) */
@property (nonatomic, readonly, copy, nullable) NSString *attr;
@property (nonatomic, readonly, copy, nullable) NSString *accountAction;

/* identity: attr (*, handle, or other) */
@property (nonatomic, readonly, copy, nullable) NSString *identityAttr;

/* include: permission set NSID, aud (optional) */
@property (nonatomic, readonly, copy, nullable) NSString *permissionSetNSID;

+ (nullable instancetype)scopeWithString:(NSString *)scope error:(NSError **)error;

/** Evaluate a repo scope against a request. */
- (BOOL)matchesCollection:(nullable NSString *)collection action:(nullable NSString *)action;

/** Evaluate an rpc scope against a method NSID and audience. */
- (BOOL)matchesMethod:(NSString *)methodNSID aud:(nullable NSString *)audience;

/** Evaluate a blob scope against a MIME type. */
- (BOOL)matchesBlobAccept:(NSString *)mimeType;

/** Evaluate an account scope. */
- (BOOL)matchesAccountAttr:(NSString *)attribute action:(nullable NSString *)action;

/** Evaluate an identity scope. */
- (BOOL)matchesIdentityAttr:(NSString *)attribute;

@end

NS_ASSUME_NONNULL_END
