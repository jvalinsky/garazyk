# ATProto Scope Requirement Implementation Plan

## Objective

Implement ATProto scope requirement and handling in OAuth2 server, including validation, transitional scopes, permission mapping, and error handling.

## Architecture

Extend the existing OAuth2 implementation to validate that all scopes include 'atproto' prefix, implement transitional scope mapping for backwards compatibility, add scope permission validation, and enhance error handling for scope-related issues.

## Technology Stack

Objective-C, OAuth2 protocol, ATProto specifications

---

## Prerequisites

### Current State Analysis
- OAuth2 server accepts any scope string
- Scopes are stored in Session and returned in token responses  
- No validation for 'atproto' prefix requirement
- No scope permission mapping or transitional support

### ATProto Scope Requirements
- All scopes must include 'atproto' prefix
- Support transitional scopes for backwards compatibility
- Implement scope permission validation
- Proper error handling for invalid/missing scopes

---

### Task 1: Define ATProto Scope Constants and Validation

**Files:** Modify `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.h`, Modify `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m`

#### Step 1: Add Transitional Scope Constants
In OAuth2.h, add constants for transitional scopes:

```objc
// Add after existing scope constants
extern NSString * const OAuth2ScopeTransitionIdentify;
extern NSString * const OAuth2ScopeTransitionSignIn;
extern NSString * const OAuth2ScopeTransitionRepoWrite;
extern NSString * const OAuth2ScopeTransitionRepoRead;
extern NSString * const OAuth2ScopeTransitionProfile;
```

#### Step 2: Implement Scope Validation Function
In OAuth2.m, add scope validation method:

```objc
- (BOOL)validateScopes:(NSString *)scopeString error:(NSError **)error {
    if (!scopeString || [scopeString length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidScope
                                     userInfo:@{NSLocalizedDescriptionKey: @"Scope parameter is required"}];
        }
        return NO;
    }
    
    NSArray<NSString *> *scopes = [scopeString componentsSeparatedByString:@" "];
    for (NSString *scope in scopes) {
        if (![scope hasPrefix:@"atproto:"]) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidScope
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid scope '%@': all scopes must have 'atproto:' prefix", scope]}];
            }
            return NO;
        }
    }
    return YES;
}
```

#### Step 3: Implement Transitional Scope Mapping
Add transitional scope mapping method:

```objc
- (NSString *)mapTransitionalScopes:(NSString *)scopeString {
    if (!scopeString) return OAuth2ScopeIdentify;
    
    NSArray<NSString *> *scopes = [scopeString componentsSeparatedByString:@" "];
    NSMutableArray<NSString *> *mappedScopes = [NSMutableArray array];
    
    for (NSString *scope in scopes) {
        NSString *mappedScope = scope;
        
        // Map transitional scopes to canonical atproto scopes
        if ([scope isEqualToString:OAuth2ScopeTransitionIdentify]) {
            mappedScope = OAuth2ScopeIdentify;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionSignIn]) {
            mappedScope = OAuth2ScopeSignIn;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionRepoWrite]) {
            mappedScope = OAuth2ScopeRepoWrite;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionRepoRead]) {
            mappedScope = OAuth2ScopeRepoRead;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionProfile]) {
            mappedScope = OAuth2ScopeAtprotoProfile;
        }
        
        [mappedScopes addObject:mappedScope];
    }
    
    return [mappedScopes componentsJoinedByString:@" "];
}
```

#### Step 4: Commit Changes
```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.h oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: add ATProto scope constants and validation methods"
```

**Step 2: Implement scope validation function**

In OAuth2.m, add scope validation method:

```objective-c
- (BOOL)validateScopes:(NSString *)scopeString error:(NSError **)error {
    if (!scopeString || [scopeString length] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidScope
                                     userInfo:@{NSLocalizedDescriptionKey: @"Scope parameter is required"}];
        }
        return NO;
    }
    
    NSArray<NSString *> *scopes = [scopeString componentsSeparatedByString:@" "];
    for (NSString *scope in scopes) {
        if (![scope hasPrefix:@"atproto:"]) {
            if (error) {
                *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                             code:OAuth2ErrorInvalidScope
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid scope '%@': all scopes must have 'atproto:' prefix", scope]}];
            }
            return NO;
        }
    }
    return YES;
}
```

**Step 3: Implement transitional scope mapping**

Add transitional scope mapping method:

```objective-c
- (NSString *)mapTransitionalScopes:(NSString *)scopeString {
    if (!scopeString) return OAuth2ScopeIdentify;
    
    NSArray<NSString *> *scopes = [scopeString componentsSeparatedByString:@" "];
    NSMutableArray<NSString *> *mappedScopes = [NSMutableArray array];
    
    for (NSString *scope in scopes) {
        NSString *mappedScope = scope;
        
        // Map transitional scopes to canonical atproto scopes
        if ([scope isEqualToString:OAuth2ScopeTransitionIdentify]) {
            mappedScope = OAuth2ScopeIdentify;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionSignIn]) {
            mappedScope = OAuth2ScopeSignIn;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionRepoWrite]) {
            mappedScope = OAuth2ScopeRepoWrite;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionRepoRead]) {
            mappedScope = OAuth2ScopeRepoRead;
        } else if ([scope isEqualToString:OAuth2ScopeTransitionProfile]) {
            mappedScope = OAuth2ScopeAtprotoProfile;
        }
        
        [mappedScopes addObject:mappedScope];
    }
    
    return [mappedScopes componentsJoinedByString:@" "];
}
```

**Step 4: Commit changes**

```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.h oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: add ATProto scope constants and validation methods"
```

---

### Task 2: Integrate Scope Validation in Authorization Request

**Files:** Modify `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m:236-273`

#### Step 1: Add Scope Validation to Authorization Request Handler
In `handleAuthorizationRequest:completion:`, add scope validation after basic parameter validation:

```objc
- (void)handleAuthorizationRequest:(OAuth2AuthorizationRequest *)request
                         completion:(OAuth2AuthorizationCompletion)completion {
    // ... existing validation code ...
    
    if (![request.responseType isEqualToString:@"code"]) {
        // ... existing error handling ...
    }
    
    // NEW: Validate scope parameter
    if (request.scope) {
        NSError *scopeError = nil;
        if (![self validateScopes:request.scope error:&scopeError]) {
            completion(nil, nil, scopeError);
            return;
        }
        
        // Apply transitional scope mapping
        request.scope = [self mapTransitionalScopes:request.scope];
    }
    
    // ... rest of existing method ...
}
```

#### Step 2: Commit Changes
```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: integrate scope validation in authorization request handler"
```

**Step 2: Commit changes**

```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: integrate scope validation in authorization request handler"
```

---

### Task 3: Integrate Scope Validation in Token Request

**Files:** Modify `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m:291-342`

#### Step 1: Add Scope Validation to Authorization Code Grant
In `processAuthorizationCodeGrant:completion:`, add scope validation:

```objc
- (void)processAuthorizationCodeGrant:(OAuth2TokenRequest *)request
                           completion:(OAuth2TokenCompletion)completion {
    // ... existing code validation ...
    
    // NEW: Validate scope if provided in token request
    NSString *finalScope = codeData[@"scope"] ?: OAuth2ScopeIdentify;
    if (request.scope) {
        NSError *scopeError = nil;
        if (![self validateScopes:request.scope error:&scopeError]) {
            completion(nil, scopeError);
            return;
        }
        
        // Check if requested scope is subset of authorized scope
        if (![self isScopeSubset:request.scope ofScope:finalScope]) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidScope
                                             userInfo:@{NSLocalizedDescriptionKey: @"Requested scope exceeds authorized scope"}];
            completion(nil, error);
            return;
        }
        
        finalScope = [self mapTransitionalScopes:request.scope];
    }
    
    // ... rest of existing method, use finalScope instead of scope ...
}
```

#### Step 2: Implement Scope Subset Validation Helper
Add scope subset validation method:

```objc
- (BOOL)isScopeSubset:(NSString *)requestedScope ofScope:(NSString *)authorizedScope {
    NSSet<NSString *> *requested = [NSSet setWithArray:[requestedScope componentsSeparatedByString:@" "]];
    NSSet<NSString *> *authorized = [NSSet setWithArray:[authorizedScope componentsSeparatedByString:@" "]];
    return [requested isSubsetOfSet:authorized];
}
```

#### Step 3: Update Refresh Token Grant to Handle Scopes
In `processRefreshTokenGrant:completion:`, update scope handling:

```objc
- (void)processRefreshTokenGrant:(OAuth2TokenRequest *)request
                       completion:(OAuth2TokenCompletion)completion {
    // ... existing validation ...
    
    NSString *newScope = request.scope ?: existingSession.scope;
    if (request.scope) {
        NSError *scopeError = nil;
        if (![self validateScopes:request.scope error:&scopeError]) {
            completion(nil, scopeError);
            return;
        }
        
        // Check if requested scope is subset of original authorized scope
        if (![self isScopeSubset:request.scope ofScope:existingSession.scope]) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidScope
                                             userInfo:@{NSLocalizedDescriptionKey: @"Requested scope exceeds originally authorized scope"}];
            completion(nil, error);
            return;
        }
        
        newScope = [self mapTransitionalScopes:request.scope];
    }
    
    // ... rest of existing method, use newScope ...
}
```

#### Step 4: Commit Changes
```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: integrate scope validation and mapping in token request handlers"
```

**Step 2: Implement scope subset validation helper**

Add scope subset validation method:

```objective-c
- (BOOL)isScopeSubset:(NSString *)requestedScope ofScope:(NSString *)authorizedScope {
    NSSet<NSString *> *requested = [NSSet setWithArray:[requestedScope componentsSeparatedByString:@" "]];
    NSSet<NSString *> *authorized = [NSSet setWithArray:[authorizedScope componentsSeparatedByString:@" "]];
    return [requested isSubsetOfSet:authorized];
}
```

**Step 3: Update refresh token grant to handle scopes**

In `processRefreshTokenGrant:completion:`, update scope handling:

```objective-c
- (void)processRefreshTokenGrant:(OAuth2TokenRequest *)request
                       completion:(OAuth2TokenCompletion)completion {
    // ... existing validation ...
    
    NSString *newScope = request.scope ?: existingSession.scope;
    if (request.scope) {
        NSError *scopeError = nil;
        if (![self validateScopes:request.scope error:&scopeError]) {
            completion(nil, scopeError);
            return;
        }
        
        // Check if requested scope is subset of original authorized scope
        if (![self isScopeSubset:request.scope ofScope:existingSession.scope]) {
            NSError *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                                 code:OAuth2ErrorInvalidScope
                                             userInfo:@{NSLocalizedDescriptionKey: @"Requested scope exceeds originally authorized scope"}];
            completion(nil, error);
            return;
        }
        
        newScope = [self mapTransitionalScopes:request.scope];
    }
    
    // ... rest of existing method, use newScope ...
}
```

**Step 4: Commit changes**

```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: integrate scope validation and mapping in token request handlers"
```

---

### Task 4: Implement Scope Permission Mapping

**Files:**
- Modify: `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.h`
- Modify: `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m`

**Step 1: Define permission mapping constants**

In OAuth2.h, add permission mapping structure:

```objective-c
typedef NS_ENUM(NSInteger, ATProtoPermission) {
    ATProtoPermissionReadPublic = 1 << 0,
    ATProtoPermissionReadPrivate = 1 << 1,
    ATProtoPermissionWritePublic = 1 << 2,
    ATProtoPermissionWritePrivate = 1 << 3,
    ATProtoPermissionIdentity = 1 << 4,
    ATProtoPermissionProfile = 1 << 5,
    ATProtoPermissionSignIn = 1 << 6
};
```

**Step 2: Implement scope to permission mapping**

In OAuth2.m, add permission mapping method:

```objective-c
- (ATProtoPermission)permissionsForScope:(NSString *)scopeString {
    ATProtoPermission permissions = 0;
    NSArray<NSString *> *scopes = [scopeString componentsSeparatedByString:@" "];
    
    for (NSString *scope in scopes) {
        if ([scope isEqualToString:OAuth2ScopeIdentify]) {
            permissions |= ATProtoPermissionIdentity;
        } else if ([scope isEqualToString:OAuth2ScopeSignIn]) {
            permissions |= (ATProtoPermissionIdentity | ATProtoPermissionSignIn);
        } else if ([scope isEqualToString:OAuth2ScopeRepoRead]) {
            permissions |= ATProtoPermissionReadPublic;
        } else if ([scope isEqualToString:OAuth2ScopeRepoWrite]) {
            permissions |= (ATProtoPermissionReadPublic | ATProtoPermissionWritePublic);
        } else if ([scope isEqualToString:OAuth2ScopeAtprotoProfile]) {
            permissions |= (ATProtoPermissionReadPrivate | ATProtoPermissionProfile);
        }
    }
    
    return permissions;
}
```

**Step 3: Add permission validation method**

Add permission validation method:

```objective-c
- (BOOL)validatePermissions:(ATProtoPermission)requiredPermissions 
               forScope:(NSString *)scopeString 
                  error:(NSError **)error {
    ATProtoPermission grantedPermissions = [self permissionsForScope:scopeString];
    
    if ((grantedPermissions & requiredPermissions) != requiredPermissions) {
        if (error) {
            *error = [NSError errorWithDomain:OAuth2ErrorDomain
                                         code:OAuth2ErrorInvalidScope
                                     userInfo:@{NSLocalizedDescriptionKey: @"Insufficient permissions for requested operation"}];
        }
        return NO;
    }
    
    return YES;
}
```

**Step 4: Commit changes**

```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.h oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2.m
git commit -m "feat: implement ATProto scope permission mapping and validation"
```

---

### Task 5: Update Session to Include Permissions

**Files:**
- Modify: `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/Session.h`
- Modify: `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/Session.m`

**Step 1: Add permissions property to Session**

In Session.h, add permissions property:

```objective-c
@property (nonatomic, assign, readonly) ATProtoPermission permissions;
```

**Step 2: Update Session initialization to calculate permissions**

In Session.m, update initWithDID:handle:scope: to calculate permissions:

```objective-c
- (instancetype)initWithDID:(NSString *)did
                      handle:(NSString *)handle
                       scope:(NSString *)scope {
    self = [super init];
    if (self) {
        // ... existing initialization ...
        
        // NEW: Calculate permissions from scope
        _permissions = [self calculatePermissionsForScope:scope];
    }
    return self;
}
```

**Step 3: Add permission calculation method**

Add permission calculation method to Session:

```objective-c
- (ATProtoPermission)calculatePermissionsForScope:(NSString *)scope {
    // Import OAuth2 constants or create local mapping
    ATProtoPermission permissions = 0;
    NSArray<NSString *> *scopes = [scope componentsSeparatedByString:@" "];
    
    for (NSString *scopeItem in scopes) {
        if ([scopeItem isEqualToString:@"atproto:identify"]) {
            permissions |= ATProtoPermissionIdentity;
        } else if ([scopeItem isEqualToString:@"atproto:signin"]) {
            permissions |= (ATProtoPermissionIdentity | ATProtoPermissionSignIn);
        } else if ([scopeItem isEqualToString:@"atproto:repo_read"]) {
            permissions |= ATProtoPermissionReadPublic;
        } else if ([scopeItem isEqualToString:@"atproto:repo_write"]) {
            permissions |= (ATProtoPermissionReadPublic | ATProtoPermissionWritePublic);
        } else if ([scopeItem isEqualToString:@"atproto:profile"]) {
            permissions |= (ATProtoPermissionReadPrivate | ATProtoPermissionProfile);
        }
    }
    
    return permissions;
}
```

**Step 4: Commit changes**

```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/Session.h oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/Session.m
git commit -m "feat: add permission calculation to Session class"
```

---

### Task 6: Add Comprehensive Tests

**Files:**
- Create: `oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2ScopeTests.m`
- Modify: `oauth-atproto-scope/Makefile` (to include new test file)

**Step 1: Create OAuth2 scope tests**

Create  test file for scope validation:

```objective-c
#import <XCTest/XCTest.h>
#import "OAuth2.h"
#import "Session.h"

@interface OAuth2ScopeTests : XCTestCase
@property (nonatomic, strong) OAuth2Server *server;
@end

@implementation OAuth2ScopeTests

- (void)setUp {
    self.server = [[OAuth2Server alloc] init];
}

- (void)testValidAtprotoScopes {
    NSError *error = nil;
    BOOL valid = [self.server validateScopes:@"atproto:identify" error:&error];
    XCTAssertTrue(valid, @"atproto:identify should be valid");
    XCTAssertNil(error, @"No error should be returned for valid scope");
}

- (void)testInvalidNonAtprotoScopes {
    NSError *error = nil;
    BOOL valid = [self.server validateScopes:@"invalid:scope" error:&error];
    XCTAssertFalse(valid, @"invalid:scope should be invalid");
    XCTAssertNotNil(error, @"Error should be returned for invalid scope");
    XCTAssertEqual(error.code, OAuth2ErrorInvalidScope, @"Error code should be InvalidScope");
}

- (void)testMultipleValidScopes {
    NSError *error = nil;
    BOOL valid = [self.server validateScopes:@"atproto:identify atproto:repo_read" error:&error];
    XCTAssertTrue(valid, @"Multiple valid scopes should pass");
    XCTAssertNil(error, @"No error for multiple valid scopes");
}

- (void)testMixedValidInvalidScopes {
    NSError *error = nil;
    BOOL valid = [self.server validateScopes:@"atproto:identify invalid:scope" error:&error];
    XCTAssertFalse(valid, @"Mixed scopes with invalid should fail");
    XCTAssertNotNil(error, @"Error should be returned for mixed scopes");
}

- (void)testEmptyScope {
    NSError *error = nil;
    BOOL valid = [self.server validateScopes:@"" error:&error];
    XCTAssertFalse(valid, @"Empty scope should be invalid");
    XCTAssertNotNil(error, @"Error should be returned for empty scope");
}

- (void)testTransitionalScopeMapping {
    NSString *mapped = [self.server mapTransitionalScopes:@"identify"];
    XCTAssertEqualObjects(mapped, @"atproto:identify", @"Transitional scope should map to atproto:identify");
    
    mapped = [self.server mapTransitionalScopes:@"identify signin"];
    XCTAssertEqualObjects(mapped, @"atproto:identify atproto:signin", @"Multiple transitional scopes should map correctly");
}

- (void)testPermissionMapping {
    ATProtoPermission perms = [self.server permissionsForScope:@"atproto:identify"];
    XCTAssertTrue(perms & ATProtoPermissionIdentity, @"atproto:identify should grant identity permission");
    
    perms = [self.server permissionsForScope:@"atproto:repo_write"];
    XCTAssertTrue(perms & ATProtoPermissionReadPublic, @"atproto:repo_write should grant read permission");
    XCTAssertTrue(perms & ATProtoPermissionWritePublic, @"atproto:repo_write should grant write permission");
}

- (void)testScopeSubsetValidation {
    BOOL isSubset = [self.server isScopeSubset:@"atproto:identify" ofScope:@"atproto:identify atproto:repo_read"];
    XCTAssertTrue(isSubset, @"Subset scope should validate");
    
    isSubset = [self.server isScopeSubset:@"atproto:repo_write" ofScope:@"atproto:identify"];
    XCTAssertFalse(isSubset, @"Non-subset scope should fail");
}

@end
```

**Step 2: Update Makefile to include tests**

Add test file to Makefile compilation.

**Step 3: Commit changes**

```bash
git add oauth-atproto-scope/ATProtoPDS/ATProtoPDS/Auth/OAuth2ScopeTests.m oauth-atproto-scope/Makefile
git commit -m "feat: add  tests for ATProto scope validation and mapping"
```

---

### Task 7: Update Documentation

**Files:**
- Create: `oauth-atproto-scope/docs/ATPROTO_SCOPE_HANDLING.md`

**Step 1: Create scope handling documentation**

Document the scope requirements and implementation:

```markdown
# ATProto Scope Handling

## Overview

The ATProto OAuth2 implementation requires all scopes to include the 'atproto:' prefix and provides backwards compatibility through transitional scope mapping.

## Scope Requirements

- All scopes must be prefixed with 'atproto:'
- Example: `atproto:identify`, `atproto:repo_read`, `atproto:profile`

## Transitional Scopes

For backwards compatibility, the following transitional scopes are supported and automatically mapped:

- `identify` → `atproto:identify`
- `signin` → `atproto:signin`
- `repo_read` → `atproto:repo_read`
- `repo_write` → `atproto:repo_write`
- `profile` → `atproto:profile`

## Permission Mapping

Scopes map to the following permissions:

- `atproto:identify`: Identity access
- `atproto:signin`: Identity + sign-in access
- `atproto:repo_read`: Public repository read access
- `atproto:repo_write`: Public repository read + write access
- `atproto:profile`: Private profile read access

## Error Handling

- `OAuth2ErrorInvalidScope`: Returned when scope doesn't include 'atproto:' prefix
- `OAuth2ErrorInvalidScope`: Returned when requested scope exceeds authorized scope
- `OAuth2ErrorInvalidScope`: Returned when insufficient permissions for operation
```

**Step 2: Commit changes**

```bash
git add oauth-atproto-scope/docs/ATPROTO_SCOPE_HANDLING.md
git commit -m "docs: add ATProto scope handling documentation"
```

---

### Task 8: Integration Testing

**Files:**
- Modify: `oauth-atproto-scope/test_endpoints.sh`

**Step 1: Add scope validation tests to integration script**

Add tests for scope validation in the integration test script.

**Step 2: Run integration tests**

Execute the updated test script to verify end-to-end functionality.

**Step 3: Commit changes**

```bash
git add oauth-atproto-scope/test_endpoints.sh
git commit -m "test: add scope validation to integration tests"
```
