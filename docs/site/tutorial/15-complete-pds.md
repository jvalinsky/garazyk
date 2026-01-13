# Chapter 15: Complete PDS Integration

Congratulations! In this final chapter, we bring everything together into a working Personal Data Server. We'll cover the CLI interface, component wiring, and deployment considerations.

## PDS Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         atprotopds-cli                          │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ HttpServer  │  │   Router    │  │     PDSController       │  │
│  │  (Port)     │──│   (XRPC)    │──│  (Business Logic)       │  │
│  └─────────────┘  └─────────────┘  └────────────┬────────────┘  │
│                                                  │               │
│  ┌─────────────────────────────────────────────┼───────────────┐│
│  │                     Services                 ▼               ││
│  │  ┌───────────┐  ┌───────────┐  ┌───────────────────────────┐││
│  │  │  Identity │  │   Repo    │  │        Database           │││
│  │  │  (DIDs)   │  │   (MST)   │  │        (SQLite)           │││
│  │  └───────────┘  └───────────┘  └───────────────────────────┘││
│  └──────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

## CLI Entry Point

```objc
// main.m
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            printUsage();
            return 1;
        }
        
        NSString *command = @(argv[1]);
        
        if ([command isEqualToString:@"serve"]) {
            return runServer(argc, argv);
        } else if ([command isEqualToString:@"create-account"]) {
            return createAccount(argc, argv);
        } else if ([command isEqualToString:@"export-repo"]) {
            return exportRepo(argc, argv);
        }
        
        printUsage();
        return 1;
    }
}

int runServer(int argc, const char *argv[]) {
    PDSConfig *config = [PDSConfig loadFromEnvironment];
    
    // Initialize database
    PDSDatabase *db = [PDSDatabase databaseAtURL:config.databaseURL];
    NSError *error = nil;
    if (![db openWithError:&error]) {
        NSLog(@"Failed to open database: %@", error);
        return 1;
    }
    
    // Initialize components
    Secp256k1KeyPair *serverKey = [Secp256k1KeyPair keyPairWithPrivateKey:config.signingKey 
                                                                    error:nil];
    JWTMinter *jwtMinter = [[JWTMinter alloc] init];
    jwtMinter.issuer = config.serverDID;
    jwtMinter.privateKey = serverKey.privateKey;
    
    PDSController *controller = [[PDSController alloc] init];
    controller.database = db;
    controller.jwtMinter = jwtMinter;
    controller.serverDID = config.serverDID;
    
    // Start HTTP server
    HttpServer *server = [HttpServer serverWithPort:config.port];
    [controller registerRoutes:server];
    
    if (![server startWithError:&error]) {
        NSLog(@"Failed to start server: %@", error);
        return 1;
    }
    
    NSLog(@"PDS running at http://localhost:%lu", (unsigned long)config.port);
    
    // Run until interrupted
    [[NSRunLoop currentRunLoop] run];
    
    return 0;
}
```

## PDSController: Component Wiring

```objc
@interface PDSController : NSObject

@property (nonatomic, strong) PDSDatabase *database;
@property (nonatomic, strong) JWTMinter *jwtMinter;
@property (nonatomic, strong) JWTVerifier *jwtVerifier;
@property (nonatomic, copy) NSString *serverDID;
@property (nonatomic, copy) NSString *pdsEndpoint;

- (void)registerRoutes:(HttpServer *)server;

@end

@implementation PDSController

- (void)registerRoutes:(HttpServer *)server {
    __weak typeof(self) weakSelf = self;
    
    // Health check
    [server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
        resp.statusCode = 200;
        [resp setJsonBody:@{@"status": @"ok"}];
    }];
    
    // Server info
    [server addRoute:@"GET" path:@"/xrpc/com.atproto.server.describeServer" 
             handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleDescribeServer:req response:resp];
    }];
    
    // Identity
    [server addRoute:@"GET" path:@"/xrpc/com.atproto.identity.resolveHandle" 
             handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleResolveHandle:req response:resp];
    }];
    
    // Repository
    [server addRoute:@"GET" path:@"/xrpc/com.atproto.repo.getRecord" 
             handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetRecord:req response:resp];
    }];
    
    [server addRoute:@"POST" path:@"/xrpc/com.atproto.repo.createRecord" 
             handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleCreateRecord:req response:resp];
    }];
    
    // Sync
    [server addRoute:@"GET" path:@"/xrpc/com.atproto.sync.getRepo" 
             handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleGetRepo:req response:resp];
    }];
    
    // OAuth
    [server addRoute:@"POST" path:@"/oauth/token" 
             handler:^(HttpRequest *req, HttpResponse *resp) {
        [weakSelf handleTokenRequest:req response:resp];
    }];
}

@end
```

## Configuration

```objc
@interface PDSConfig : NSObject

@property (nonatomic, assign) NSUInteger port;
@property (nonatomic, copy) NSString *serverDID;
@property (nonatomic, copy) NSString *pdsEndpoint;
@property (nonatomic, strong) NSURL *databaseURL;
@property (nonatomic, strong) NSData *signingKey;

+ (instancetype)loadFromEnvironment;

@end

@implementation PDSConfig

+ (instancetype)loadFromEnvironment {
    PDSConfig *config = [[PDSConfig alloc] init];
    
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    
    config.port = [env[@"PDS_PORT"] integerValue] ?: 3000;
    config.serverDID = env[@"PDS_DID"] ?: @"did:plc:localhost";
    config.pdsEndpoint = env[@"PDS_ENDPOINT"] ?: @"http://localhost:3000";
    
    NSString *dataDir = env[@"PDS_DATA_DIR"] ?: @"./data";
    [[NSFileManager defaultManager] createDirectoryAtPath:dataDir 
                              withIntermediateDirectories:YES 
                                               attributes:nil 
                                                    error:nil];
    config.databaseURL = [NSURL fileURLWithPath:
        [dataDir stringByAppendingPathComponent:@"pds.db"]];
    
    // Load or generate signing key
    NSString *keyPath = [dataDir stringByAppendingPathComponent:@"signing.key"];
    config.signingKey = [NSData dataWithContentsOfFile:keyPath];
    if (!config.signingKey) {
        Secp256k1KeyPair *keyPair = [Secp256k1KeyPair generateKeyPair:nil];
        config.signingKey = keyPair.privateKey;
        [config.signingKey writeToFile:keyPath atomically:YES];
    }
    
    return config;
}

@end
```

## Account Creation

```objc
int createAccount(int argc, const char *argv[]) {
    if (argc < 4) {
        NSLog(@"Usage: atprotopds-cli create-account <handle> <password>");
        return 1;
    }
    
    NSString *handle = @(argv[2]);
    NSString *password = @(argv[3]);
    
    PDSConfig *config = [PDSConfig loadFromEnvironment];
    PDSDatabase *db = [PDSDatabase databaseAtURL:config.databaseURL];
    [db openWithError:nil];
    
    // Generate keys
    DIDKey *signingKey = [DIDKey generateSecp256k1];
    DIDKey *recoveryKey = [DIDKey generateSecp256k1];
    
    // Create PLC genesis operation
    PLCOperation *genesis = [PLCOperation genesisOperationWithRotationKeys:
        @[recoveryKey.didKey, signingKey.didKey]
        verificationMethods:@{@"atproto": signingKey.didKey}
        alsoKnownAs:@[[NSString stringWithFormat:@"at://%@", handle]]
        services:@{
            @"atproto_pds": @{
                @"type": @"AtprotoPersonalDataServer",
                @"endpoint": config.pdsEndpoint
            }
        }
    ];
    
    NSError *error = nil;
    NSString *did = [genesis computeCID:&error];
    
    // Store account
    [db createAccount:did handle:handle error:&error];
    
    // Store password hash
    NSData *passwordHash = [self hashPassword:password];
    [db storePasswordHash:passwordHash forDID:did error:&error];
    
    // Store keys
    [db storePrivateKey:signingKey.privateKeyData forDID:did label:@"signing" error:&error];
    
    NSLog(@"Created account:");
    NSLog(@"  DID: %@", did);
    NSLog(@"  Handle: %@", handle);
    
    [db close];
    return 0;
}
```

## Running the PDS

```bash
# Set environment variables
export PDS_PORT=3000
export PDS_ENDPOINT="https://pds.example.com"
export PDS_DATA_DIR="./data"

# Start the server
./atprotopds-cli serve

# Create an account
./atprotopds-cli create-account alice.example.com mysecretpassword

# Test endpoints
curl http://localhost:3000/health
curl http://localhost:3000/xrpc/com.atproto.server.describeServer
curl "http://localhost:3000/xrpc/com.atproto.identity.resolveHandle?handle=alice.example.com"
```

---

## Common Mistakes

### Mistake 1: Not Securing the Signing Key

❌ **What people do:**
```bash
# WRONG: Signing key in repo
git add data/signing.key
git commit -m "Add signing key"
```

**Why this fails:**
- Signing key is equivalent to server identity
- Anyone with key can impersonate your PDS
- Key should never be in version control

✅ **Correct approach:**
```bash
# RIGHT: Exclude from git and secure permissions
echo "data/*.key" >> .gitignore
chmod 600 data/signing.key
```

### Mistake 2: Missing Weak-Strong Dance

❌ **What people do:**
```objc
// WRONG: Capturing self strongly in block
[server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
    [self handleHealth:req response:resp];  // Strong capture → retain cycle!
}];
```

**Why this fails:**
- Server holds block → Block holds controller
- Neither can be deallocated
- Memory leak grows with each route

✅ **Correct approach:**
```objc
__weak typeof(self) weakSelf = self;
[server addRoute:@"GET" path:@"/health" handler:^(HttpRequest *req, HttpResponse *resp) {
    typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf) {
        [strongSelf handleHealth:req response:resp];
    }
}];
```

### Mistake 3: Forgetting RunLoop for Server

❌ **What people do:**
```objc
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        HttpServer *server = [HttpServer serverWithPort:3000];
        [server start];
        // Server starts... and program exits immediately!
    }
    return 0;
}
```

**Why this fails:**
- Without RunLoop, main() exits immediately
- Server never gets to handle requests
- Network connections are dropped

✅ **Correct approach:**
```objc
[server startWithError:nil];
NSLog(@"Server running on port 3000");
[[NSRunLoop currentRunLoop] run];  // Block forever, handle events
```

---

<script setup>
const mockIntegrationCode = `#import <Foundation/Foundation.h>

// --- Mock PDS Client for Integration Tests ---

@interface PDSClient : NSObject
@property (nonatomic, strong) NSMutableDictionary *serverState; // "DB"
@end

@implementation PDSClient
- (instancetype)init { self=[super init]; _serverState=[NSMutableDictionary dictionary]; return self; }

- (void)createAccount:(NSString *)handle password:(NSString *)password {
    self.serverState[handle] = password;
    printf("Client: Account created for %s\\n", handle.UTF8String);
}

- (NSString *)authenticate:(NSString *)handle password:(NSString *)password {
    if ([self.serverState[handle] isEqualToString:password]) {
        printf("Client: Authenticated %s\\n", handle.UTF8String);
        return [NSString stringWithFormat:@"token_for_%@", handle];
    }
    printf("Client: Auth failed for %s\\n", handle.UTF8String);
    return nil;
}

- (void)createRecord:(NSString *)token collection:(NSString *)collection record:(NSDictionary *)record {
    if (!token) { printf("Client: 401 Unauthorized\\n"); return; }
    NSString *key = [NSString stringWithFormat:@"%@/%@", token, collection];
    self.serverState[key] = record;
    printf("Client: Created record in %s\\n", collection.UTF8String);
}

- (NSDictionary *)getRecord:(NSString *)token collection:(NSString *)collection {
    NSString *key = [NSString stringWithFormat:@"%@/%@", token, collection];
    return self.serverState[key];
}
@end
`;

const exercise3Code = mockIntegrationCode + `
// --- EXERCISE 3: Integration Test ---

void runTest() {
    PDSClient *client = [PDSClient new];
    
    // TODO: Implement the integration flow
    // 1. Create account "alice" with password "secure"
    // 2. Authenticate to get token
    // 3. Create a record in "app.bsky.feed.post" with text "Hello"
    // 4. Get the record back and verify text is "Hello"
    
    // Example:
    // [client createAccount:@"alice" password:@"secure"];
    // NSString *token = [client authenticate:@"alice" password:@"secure"];
    // ...
    
    // Your validation code here
    
    // Check (Mock verification)
    NSDictionary *rec = [client getRecord:@"token_for_alice" collection:@"app.bsky.feed.post"];
    if (rec && [rec[@"text"] isEqualToString:@"Hello"]) {
        printf("PASS: Integration test successful.\\n");
    } else {
        printf("FAIL: Record verification failed.\\n");
    }
}

int main() {
    @autoreleasepool {
        runTest();
    }
    return 0;
}`;
</script>


📝 **Exercise 1: Add Rate Limiting**

Implement a simple rate limiter for XRPC endpoints:

```objc
@interface RateLimiter : NSObject
- (BOOL)allowRequestForIP:(NSString *)ipAddress;
@end
```

- Hint: Track request counts per IP with timestamps
- Challenge: Use sliding window algorithm

📝 **Exercise 2: Implement Blob Upload**

Add blob storage support for images:

```objc
// POST /xrpc/com.atproto.repo.uploadBlob
- (void)handleUploadBlob:(HttpRequest *)req response:(HttpResponse *)resp;
```

- Hint: Store blob data, return CID and MIME type
- Consider: Maximum file size limits

📝 **Exercise 3: Write Integration Tests**

Create tests that exercise the full request flow:

<ObjcRunner :initialCode="exercise3Code" />


---

## What You've Built

Congratulations! You've built a Personal Data Server from scratch that includes:

- ✅ **Objective-C fundamentals** and Foundation framework mastery
- ✅ **Content addressing** with CIDs, hashing, and base encodings
- ✅ **CBOR serialization** with DAG-CBOR constraints
- ✅ **Merkle Search Trees** for ordered, verifiable data storage
- ✅ **CAR file archives** for repository export/import
- ✅ **secp256k1 cryptography** for signing and verification
- ✅ **Decentralized Identifiers** with did:key and did:plc
- ✅ **HTTP server** with GCD for concurrent request handling
- ✅ **XRPC endpoints** implementing the AT Protocol API
- ✅ **SQLite persistence** for accounts and data
- ✅ **OAuth 2.1 authentication** with JWT tokens

## Key Takeaways

1. **Content-addressing everywhere** - Every piece of data has a CID, enabling verification and deduplication.

2. **Cryptographic identity** - DIDs and PLC operations create portable, self-sovereign account identity.

3. **Signed commits** - Every repository change is cryptographically signed, creating an auditable history.

4. **Modular design** - Components (HTTP, database, crypto) are separate, testable units.

## Going Further

To make this a production-ready PDS:

1. **Firehose**: Implement the WebSocket event stream for real-time sync
2. **Blob storage**: Handle image and video uploads at scale
3. **Federation**: Connect to the relay network (app.bsky.social)
4. **Moderation**: Implement content filtering and labeling
5. **Monitoring**: Add logging, metrics, alerting, and health checks
6. **TLS**: Add HTTPS termination (via nginx or built-in)
7. **Backups**: Automated database and key backups

---

**The complete source code is available in the [NSPds repository](file:///Users/jack/Software/objpds).**

Thank you for following this tutorial! 🎉
