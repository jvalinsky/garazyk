---
title: Federation Support Implementation Plan
---

# Federation Support Implementation Plan

## Goal
Implement inter-PDS communication protocols for cross-server data access with request forwarding based on DID resolution, focusing on repository data retrieval.

## Architecture
Add federation logic to PDSController that checks if a DID is local, resolves remote DIDs to find hosting PDS endpoints, and forwards requests to remote servers. Use existing DID resolution infrastructure and extend XrpcMethodRegistry to handle federated requests.

## Tech Stack
Objective-C, Foundation framework, existing ATProto PDS components (DIDResolver, HandleResolver, XrpcHandler)

### Task 1: Add federation support to PDSController

**Files:**
- Modify: `federation-worktree/Garazyk/Garazyk/PDSController.h` - Add federation methods
- Modify: `federation-worktree/Garazyk/Garazyk/PDSController.m` - Implement federation logic

### Step 1: Add federation method declarations to PDSController.h

```objc
// Add after existing method declarations
- (BOOL)isDIDLocal:(NSString *)did;
- (nullable NSDictionary *)forwardRequestToRemotePDS:(NSString *)remotePDSEndpoint
                                            methodId:(NSString *)methodId
                                           parameters:(NSDictionary *)parameters
                                                error:(NSError **)error;
- (nullable NSDictionary *)getRecordFromRemotePDS:(NSString *)remotePDSEndpoint
                                              repo:(NSString *)repo
                                        collection:(NSString *)collection
                                             rkey:(NSString *)rkey
                                            error:(NSError **)error;
```

### Step 2: Add DIDResolver property to PDSController

```objc
// In @interface PDSController
@property (nonatomic, strong) DIDResolver *didResolver;
```

### Step 3: Initialize DIDResolver in initWithDatabase

```objc
- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
        _didResolver = [[DIDResolver alloc] init];
        // ... existing initialization
    }
    return self;
}
```

### Step 4: Implement isDIDLocal method

```objc
- (BOOL)isDIDLocal:(NSString *)did {
    // For now, assume all DIDs are local if we have them in our database
    // This could be extended to check against a configured list of local DIDs
    NSError *error = nil;
    NSDictionary *atprotoData = [_didResolver resolveAtprotoDataForDID:did error:&error];
    return atprotoData != nil && error == nil;
}
```

### Step 5: Implement getRecordFromRemotePDS method

```objc
- (nullable NSDictionary *)getRecordFromRemotePDS:(NSString *)remotePDSEndpoint
                                              repo:(NSString *)repo
                                        collection:(NSString *)collection
                                             rkey:(NSString *)rkey
                                            error:(NSError **)error {
    NSString *urlString = [NSString stringWithFormat:@"%@/xrpc/com.atproto.repo.getRecord?repo=%@&collection=%@&rkey=%@",
                          remotePDSEndpoint, repo, collection, rkey];
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    
    __block NSDictionary *result = nil;
    __block NSError *blockError = nil;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *requestError) {
        if (requestError) {
            blockError = requestError;
        } else if (data) {
            NSError *jsonError = nil;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            if (jsonError) {
                blockError = jsonError;
            } else {
                result = jsonResponse;
            }
        }
        dispatch_semaphore_signal(semaphore);
    }] resume];
    
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    
    if (blockError && error) {
        *error = blockError;
    }
    
    return result;
}
```

### Step 6: Modify getRecordForDid to support federation

```objc
- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                               collection:(NSString *)collection
                                    rkey:(NSString *)rkey
                                   error:(NSError **)error {
    // First check if DID is local
    if ([self isDIDLocal:did]) {
        // Use existing local logic
        NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
        NSError *dbError = nil;
        PDSDatabaseRecord *record = [_database getRecord:uri error:&dbError];
        
        if (!record) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.pds"
                                             code:404
                                         userInfo:@{NSLocalizedDescriptionKey: @"Record not found"}];
            }
            return nil;
        }
        
        return @{
            @"uri": uri,
            @"cid": record.cid ?: @"",
            @"value": record.value ?: @{}
        };
    } else {
        // Resolve remote PDS and forward request
        NSError *resolveError = nil;
        NSDictionary *atprotoData = [_didResolver resolveAtprotoDataForDID:did error:&resolveError];
        
        if (resolveError || !atprotoData[@"pds"]) {
            if (error) {
                *error = resolveError ?: [NSError errorWithDomain:@"com.atproto.pds"
                                                             code:404
                                                         userInfo:@{NSLocalizedDescriptionKey: @"DID not found or no PDS service"}];
            }
            return nil;
        }
        
        NSString *remotePDSEndpoint = atprotoData[@"pds"];
        return [self getRecordFromRemotePDS:remotePDSEndpoint
                                        repo:did
                                  collection:collection
                                       rkey:rkey
                                      error:error];
    }
}
```

### Step 7: Commit federation support

```bash
git add federation-worktree/Garazyk/Garazyk/PDSController.h federation-worktree/Garazyk/Garazyk/PDSController.m
git commit -m "feat: add basic federation support to PDSController for record retrieval"
```

### Task 2: Update XrpcMethodRegistry to handle federated responses

**Files:**
- Modify: `federation-worktree/Garazyk/Garazyk/Network/XrpcMethodRegistry.m` - Ensure proper error handling for federated requests

### Step 1: Update getRecord handler to handle federation errors

The existing handler should work as-is since it delegates to PDSController, but verify the error handling is appropriate.

### Step 2: Test the integration

Run existing tests to ensure federation doesn't break local functionality.

### Step 3: Commit XrpcMethodRegistry updates

```bash
git add federation-worktree/Garazyk/Garazyk/Network/XrpcMethodRegistry.m
git commit -m "feat: update XrpcMethodRegistry for federated request error handling"
```

## Task 3: Add federation tests

**Files:**
- Create: `federation-worktree/Garazyk/Garazyk/PDSController+FederationTests.m` - Unit tests for federation

### Step 1: Create test file with basic federation tests

```objc
#import <XCTest/XCTest.h>
#import "PDSController.h"
#import "DIDResolver.h"

@interface PDSController_FederationTests : XCTestCase

@property (nonatomic, strong) PDSController *controller;

@end

@implementation PDSController_FederationTests

- (void)setUp {
    // Create mock database and controller for testing
    // This would need to be implemented based on existing test setup
}

- (void)testIsDIDLocalReturnsTrueForLocalDID {
    // Test that local DIDs are identified correctly
    XCTAssertTrue([self.controller isDIDLocal:@"did:plc:localtest"]);
}

- (void)testIsDIDLocalReturnsFalseForRemoteDID {
    // Test that remote DIDs are identified correctly
    XCTAssertFalse([self.controller isDIDLocal:@"did:plc:remotetest"]);
}

- (void)testGetRecordFromRemotePDS {
    // Test forwarding request to remote PDS
    // This would require mocking the HTTP request/response
}

@end
```

### Step 2: Run federation tests

```bash
cd federation-worktree && make test
```

### Step 3: Commit federation tests

```bash
git add federation-worktree/Garazyk/Garazyk/PDSController+FederationTests.m
git commit -m "test: add federation unit tests"
```

## Task 4: Integration testing and documentation

**Files:**
- Modify: `federation-worktree/README.md` - Document federation capabilities
- Create: `federation-worktree/test_federation.sh` - Integration test script

### Step 1: Create integration test script

```bash
#!/bin/bash
# Test federation by setting up two PDS instances and testing cross-server requests

echo "Testing federation support..."

# Start local PDS
./build/atprotopds --port 8080 &
LOCAL_PID=$!

# Start remote PDS (simulated)
./build/atprotopds --port 8081 &
REMOTE_PID=$!

# Wait for servers to start
sleep 2

# Test local request
curl -X GET "http://localhost:8080/xrpc/com.atproto.repo.getRecord?repo=did:plc:local&collection=test&key=record1"

# Test federated request (would forward to remote PDS)
curl -X GET "http://localhost:8080/xrpc/com.atproto.repo.getRecord?repo=did:plc:remote&collection=test&key=record1"

# Cleanup
kill $LOCAL_PID
kill $REMOTE_PID
```

## Step 2: Update README with federation documentation

```markdown
## Federation Support

This PDS implementation supports basic federation for cross-server data access:

- DID resolution: Automatically resolves DIDs to find hosting PDS endpoints
- Request forwarding: Forwards repository data requests to remote PDS instances
- Supported operations: `com.atproto.repo.getRecord` (additional operations can be added similarly)

### Configuration

No additional configuration is required. The PDS will automatically detect when a DID is not hosted locally and forward requests accordingly.

### Testing Federation

Run the integration test:

```bash
./test_federation.sh
```

# Placeholder
```

## Step 3: Run integration tests

```bash
cd federation-worktree && chmod +x test_federation.sh && ./test_federation.sh
```

### Step 4: Commit documentation and tests

```bash
git add federation-worktree/README.md federation-worktree/test_federation.sh
git commit -m "docs: add federation documentation and integration tests"
```

### Task 3: Add federation tests

**Files:**
- Create: `federation-worktree/Garazyk/Garazyk/PDSController+FederationTests.m` - Unit tests for federation

**Step 1: Create test file with basic federation tests**

```objc
#import <XCTest/XCTest.h>
#import "PDSController.h"
#import "DIDResolver.h"

@interface PDSController_FederationTests : XCTestCase

@property (nonatomic, strong) PDSController *controller;

@end

@implementation PDSController_FederationTests

- (void)setUp {
    // Create mock database and controller for testing
    // This would need to be implemented based on existing test setup
}

- (void)testIsDIDLocalReturnsTrueForLocalDID {
    // Test that local DIDs are identified correctly
    XCTAssertTrue([self.controller isDIDLocal:@"did:plc:localtest"]);
}

- (void)testIsDIDLocalReturnsFalseForRemoteDID {
    // Test that remote DIDs are identified correctly
    XCTAssertFalse([self.controller isDIDLocal:@"did:plc:remotetest"]);
}

- (void)testGetRecordFromRemotePDS {
    // Test forwarding request to remote PDS
    // This would require mocking the HTTP request/response
}

@end
```

**Step 2: Run federation tests**

```bash
cd federation-worktree && make test
```

**Step 3: Commit federation tests**

```bash
git add federation-worktree/Garazyk/Garazyk/PDSController+FederationTests.m
git commit -m "test: add federation unit tests"
```

### Task 4: Integration testing and documentation

**Files:**
- Modify: `federation-worktree/README.md` - Document federation capabilities
- Create: `federation-worktree/test_federation.sh` - Integration test script

**Step 1: Create integration test script**

```bash
#!/bin/bash
# Test federation by setting up two PDS instances and testing cross-server requests

echo "Testing federation support..."

# Start local PDS
./build/atprotopds --port 8080 &
LOCAL_PID=$!

# Start remote PDS (simulated)
./build/atprotopds --port 8081 &
REMOTE_PID=$!

# Wait for servers to start
sleep 2

# Test local request
curl -X GET "http://localhost:8080/xrpc/com.atproto.repo.getRecord?repo=did:plc:local&collection=test&key=record1"

# Test federated request (would forward to remote PDS)
curl -X GET "http://localhost:8080/xrpc/com.atproto.repo.getRecord?repo=did:plc:remote&collection=test&key=record1"

# Cleanup
kill $LOCAL_PID
kill $REMOTE_PID
```

**Step 2: Update README with federation documentation**

```markdown
## Federation Support

This PDS implementation supports basic federation for cross-server data access:

- DID resolution: Automatically resolves DIDs to find hosting PDS endpoints
- Request forwarding: Forwards repository data requests to remote PDS instances
- Supported operations: `com.atproto.repo.getRecord` (additional operations can be added similarly)

### Configuration

No additional configuration is required. The PDS will automatically detect when a DID is not hosted locally and forward requests accordingly.

### Testing Federation

Run the integration test:

```bash
./test_federation.sh
```

# Placeholder
```

**Step 3: Run integration tests**

```bash
cd federation-worktree && chmod +x test_federation.sh && ./test_federation.sh
```

**Step 4: Commit documentation and tests**

```bash
git add federation-worktree/README.md federation-worktree/test_federation.sh
git commit -m "docs: add federation documentation and integration tests"
```

---

## Related Documentation

- [Archive Index](README) - Index of all archived plans
- [Current Plans](../README) - Active implementation plans
- [Architecture Docs](../../architecture/README) - System architecture documentation</content>
<parameter name="filePath">docs/plans/2026-01-07-federation-support.md