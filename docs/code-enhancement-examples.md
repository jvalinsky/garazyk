# Code Enhancement Examples

This page demonstrates all the code enhancement features available in the VitePress documentation system.

## Built-in VitePress Features

VitePress provides powerful code block features out of the box via Shiki syntax highlighting.

### 1. Basic Syntax Highlighting

All code blocks automatically get syntax highlighting based on the language identifier:

```objective-c
@interface PDSApplication : NSObject

@property (nonatomic, strong) NSString *serverURL;
@property (nonatomic, assign) NSInteger port;

- (instancetype)initWithConfiguration:(NSDictionary *)config;
- (void)startServer;
- (void)stopServer;

@end
```

### 2. Line Numbers

Line numbers are enabled by default for all code blocks (configured in `config.ts`):

```typescript
interface VitePressConfig {
  title: string;
  description: string;
  base: string;
  markdown: {
    lineNumbers: boolean;  // This enables line numbers
  };
}
```

### 3. Line Highlighting

Highlight specific lines using the `{line-numbers}` syntax after the language identifier:

```objective-c{2,5-7}
@implementation PDSApplication

- (void)startServer {
    NSLog(@"Starting server on port %ld", (long)self.port);
    // These lines are highlighted
    [self validateConfiguration];
    [self bindToPort:self.port];
    [self startListening];
}

@end
```

**Syntax**: ` ```objective-c{2,5-7} `

- `{2}` - Highlights line 2
- `{5-7}` - Highlights lines 5 through 7
- `{2,5-7,10}` - Highlights line 2, lines 5-7, and line 10

### 4. Code Block Titles

Add a title to code blocks using square brackets after the language identifier:

```objective-c [PDSApplication.m]
@implementation PDSApplication

- (instancetype)initWithConfiguration:(NSDictionary *)config {
    self = [super init];
    if (self) {
        _serverURL = config[@"serverURL"];
        _port = [config[@"port"] integerValue];
    }
    return self;
}

@end
```

**Syntax**: ` ```objective-c [PDSApplication.m] `

### 5. Combining Features

You can combine line highlighting and titles:

```objective-c{3-5} [PDSAccountService.m]
@implementation PDSAccountService

- (BOOL)createAccount:(NSString *)handle
             password:(NSString *)password
                error:(NSError **)error {
    // Account creation logic
    return YES;
}

@end
```

**Syntax**: ` ```objective-c{3-5} [PDSAccountService.m] `

### 6. Copy-to-Clipboard Buttons

All code blocks automatically include a copy button in the top-right corner. Hover over any code block to see it.

### 7. Code Groups (Platform-Specific Code)

Use code groups to show platform-specific implementations with tabs:

::: code-group

```objective-c [macOS]
#import <Security/Security.h>

- (NSData *)generateSecureRandomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    return data;
}
```

```objective-c [Linux]
#import <openssl/rand.h>

- (NSData *)generateSecureRandomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    RAND_bytes(data.mutableBytes, (int)length);
    return data;
}
```

:::

**Syntax**:
```markdown
::: code-group

```objective-c [macOS]
// macOS code
\```

```objective-c [Linux]
// Linux code
\```

:::
```

## Custom Annotation Features

The custom code enhancer plugin adds support for inline annotations using special comment syntax.

### Annotation Types

Four annotation types are supported:

- `[!NOTE]` - Important information (blue)
- `[!WARNING]` - Warnings and cautions (yellow)
- `[!ERROR]` - Errors and critical issues (red)
- `[!TIP]` - Helpful tips and best practices (green)

### NOTE Annotations

Use `[!NOTE]` for important implementation details:

```objective-c
@implementation PDSRepositoryService

- (BOOL)commitChanges:(NSArray *)records error:(NSError **)error {
    // [!NOTE] Always validate records before committing to MST
    if (![self validateRecords:records]) {
        return NO;
    }
    
    // Commit to Merkle Search Tree
    return [self.mst addRecords:records error:error];
}

@end
```

### WARNING Annotations

Use `[!WARNING]` for potential issues or important cautions:

```objective-c
@implementation PDSBlobService

- (BOOL)uploadBlob:(NSData *)data
        identifier:(NSString *)identifier
             error:(NSError **)error {
    // [!WARNING] Check blob size limits before processing
    if (data.length > self.maxBlobSize) {
        *error = [NSError errorWithDomain:@"BlobError"
                                     code:413
                                 userInfo:@{NSLocalizedDescriptionKey: @"Blob too large"}];
        return NO;
    }
    
    return [self storeBlobData:data withIdentifier:identifier error:error];
}

@end
```

### ERROR Annotations

Use `[!ERROR]` to highlight error conditions or critical issues:

```objective-c
@implementation PDSAuthService

- (NSString *)generateJWT:(NSDictionary *)claims error:(NSError **)error {
    // [!ERROR] Never use weak signing algorithms in production
    // Use ES256 (ECDSA with P-256 and SHA-256) for JWT signing
    
    if ([self.signingAlgorithm isEqualToString:@"HS256"]) {
        *error = [NSError errorWithDomain:@"AuthError"
                                     code:500
                                 userInfo:@{NSLocalizedDescriptionKey: @"Weak signing algorithm"}];
        return nil;
    }
    
    return [self signJWTWithClaims:claims algorithm:@"ES256" error:error];
}

@end
```

### TIP Annotations

Use `[!TIP]` for helpful tips and best practices:

```objective-c
@implementation PDSDatabasePool

- (sqlite3 *)getDatabaseForDID:(NSString *)did error:(NSError **)error {
    // [!TIP] Use connection pooling to improve performance
    // Reuse existing connections instead of creating new ones
    
    sqlite3 *db = [self.connectionPool objectForKey:did];
    if (!db) {
        db = [self createNewConnection:did error:error];
        [self.connectionPool setObject:db forKey:did];
    }
    
    return db;
}

@end
```

### Multiple Annotations

You can use multiple annotations in the same code block:

```objective-c{5,10,15}
@implementation PDSFirehoseService

- (void)broadcastCommit:(PDSCommit *)commit {
    // [!NOTE] Commits are broadcast to all connected WebSocket clients
    NSArray *clients = [self.websocketServer connectedClients];
    
    NSData *commitData = [self serializeCommit:commit];
    
    for (PDSWebSocketClient *client in clients) {
        // [!WARNING] Handle backpressure to prevent memory issues
        if ([client sendQueueSize] > self.maxQueueSize) {
            [self handleBackpressure:client];
            continue;
        }
        // [!TIP] Send asynchronously to avoid blocking the main thread
        [client sendData:commitData async:YES];
    }
}

@end
```

## Advanced Examples

### Complete Implementation with All Features

Here's a complete example combining multiple enhancement features:

```objective-c{8-10,15-17,22} [PDSXrpcDispatcher.m]
@implementation PDSXrpcDispatcher

- (void)handleRequest:(HttpRequest *)request
             response:(HttpResponse *)response {
    // Extract NSID from request path
    NSString *nsid = [self extractNSID:request.path];
    
    // [!NOTE] NSID format: com.atproto.server.createSession
    // Validate NSID format before lookup
    if (![self isValidNSID:nsid]) {
        [response setStatusCode:400];
        return;
    }
    
    // [!WARNING] Always authenticate before executing methods
    // Some methods require authentication, others don't
    if ([self requiresAuth:nsid] && ![self authenticate:request]) {
        [response setStatusCode:401];
        return;
    }
    
    // [!TIP] Use method registry for clean separation of concerns
    XrpcMethod *method = [self.methodRegistry methodForNSID:nsid];
    if (!method) {
        [response setStatusCode:404];
        return;
    }
    
    // Execute the method
    [method executeWithRequest:request response:response];
}

@end
```

### Platform-Specific Code with Annotations

::: code-group

```objective-c [macOS]
#import <Security/Security.h>

@implementation PDSKeyManager

- (NSData *)generateKeyPair:(NSError **)error {
    // [!NOTE] macOS uses Security framework for hardware-backed keys
    // Keys are stored in the Secure Enclave when available
    
    NSDictionary *attributes = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits: @256,
        // [!TIP] Use kSecAttrTokenIDSecureEnclave for hardware backing
        (__bridge id)kSecAttrTokenID: (__bridge id)kSecAttrTokenIDSecureEnclave
    };
    
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes,
                                                  (CFErrorRef *)error);
    return [self exportKey:privateKey];
}

@end
```

```objective-c [Linux]
#import <openssl/evp.h>
#import <openssl/ec.h>

@implementation PDSKeyManager

- (NSData *)generateKeyPair:(NSError **)error {
    // [!NOTE] Linux uses OpenSSL for cryptographic operations
    // Keys are stored in filesystem with appropriate permissions
    
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, NULL);
    EVP_PKEY *pkey = NULL;
    
    // [!WARNING] Always check return values for OpenSSL functions
    if (!ctx || EVP_PKEY_keygen_init(ctx) <= 0) {
        *error = [NSError errorWithDomain:@"CryptoError" code:500 userInfo:nil];
        return nil;
    }
    
    // [!TIP] Use P-256 curve for compatibility with AT Protocol
    EVP_PKEY_CTX_set_ec_paramgen_curve_nid(ctx, NID_X9_62_prime256v1);
    EVP_PKEY_keygen(ctx, &pkey);
    
    return [self exportKey:pkey];
}

@end
```

:::

## Best Practices

### When to Use Line Highlighting

Use line highlighting to:
- Draw attention to the most important lines
- Show what changed in a before/after comparison
- Highlight lines being discussed in the surrounding text
- Emphasize error handling or security-critical code

**Don't overuse it** - highlighting too many lines reduces its effectiveness.

### When to Use Annotations

Use annotations to:
- **[!NOTE]** - Explain non-obvious implementation details
- **[!WARNING]** - Point out potential pitfalls or gotchas
- **[!ERROR]** - Show what NOT to do or highlight critical issues
- **[!TIP]** - Share best practices and optimization opportunities

### When to Use Code Groups

Use code groups when:
- Showing platform-specific implementations (macOS vs Linux)
- Comparing different approaches to the same problem
- Showing before/after refactoring
- Demonstrating alternative configurations

### Combining Features Effectively

```objective-c{5,10-12} [PDSExample.m]
@implementation PDSExample

- (void)demonstrateFeatures {
    // [!NOTE] This example combines multiple enhancement features
    // Line 5 is highlighted to draw attention
    NSLog(@"Important line here");
    
    // Regular code without highlighting
    [self doSomething];
    // [!TIP] These lines are highlighted AND annotated
    // This combination is very effective for teaching
    [self doSomethingImportant];
}

@end
```

## Testing the Features

To verify all features are working:

1. **Syntax highlighting**: All code should have colored syntax
2. **Line numbers**: Numbers should appear on the left of all code blocks
3. **Line highlighting**: Highlighted lines should have a different background color
4. **Titles**: Code block titles should appear above the code
5. **Copy buttons**: Hover over code blocks to see the copy button
6. **Code groups**: Tabs should be clickable and switch between code variants
7. **Annotations**: Lines with annotations should have colored left borders
8. **Theme switching**: Toggle between light/dark mode - all features should work in both

## Summary

The VitePress documentation system provides:

**Built-in features** (no configuration needed):
- ✅ Syntax highlighting for 100+ languages
- ✅ Line numbers
- ✅ Line highlighting with `{line-numbers}` syntax
- ✅ Code block titles with `[filename]` syntax
- ✅ Copy-to-clipboard buttons
- ✅ Code groups with `::: code-group` syntax

**Custom features** (via code-enhancer plugin):
- ✅ Inline annotations with `[!NOTE]`, `[!WARNING]`, `[!ERROR]`, `[!TIP]`
- ✅ Colored left borders for annotated lines
- ✅ Theme-aware styling for light and dark modes

All features work together seamlessly to create an excellent code reading experience.
