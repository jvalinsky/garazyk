# Collapsible Code Blocks Example

This page demonstrates the collapsible code blocks feature for long code examples.

## Basic Usage

Use the `::: code-collapse` container to wrap code blocks that should be collapsible:

::: code-collapse Click to see the complete implementation
```objc
@implementation PDSApplication

- (instancetype)initWithConfiguration:(PDSConfiguration *)config {
    self = [super init];
    if (self) {
        _config = config;
        _serviceDb = [[PDSServiceDatabases alloc] initWithPath:config.databasePath];
        _databasePool = [[PDSDatabasePool alloc] initWithServiceDb:_serviceDb];
        _accountService = [[PDSAccountService alloc] initWithServiceDb:_serviceDb];
        _recordService = [[PDSRecordService alloc] initWithPool:_databasePool];
        _blobService = [[PDSBlobService alloc] initWithConfig:config];
        _repositoryService = [[PDSRepositoryService alloc] initWithPool:_databasePool];
        _relayService = [[PDSRelayService alloc] initWithConfig:config];
    }
    return self;
}

- (BOOL)startServer:(NSError **)error {
    // Initialize database
    if (![self.serviceDb initialize:error]) {
        return NO;
    }
    
    // Start HTTP server
    self.httpServer = [[HttpServer alloc] initWithPort:self.config.port];
    [self configureRoutes];
    
    if (![self.httpServer start:error]) {
        return NO;
    }
    
    NSLog(@"Server started on port %d", self.config.port);
    return YES;
}

- (void)configureRoutes {
    // Configure XRPC routes
    XrpcMethodRegistry *registry = [[XrpcMethodRegistry alloc] initWithApplication:self];
    [registry registerAllMethods];
    
    // Configure OAuth routes
    [self.httpServer addRoute:@"/oauth/authorize" handler:^(HttpRequest *req, HttpResponse *res) {
        [self handleOAuthAuthorize:req response:res];
    }];
    
    // Configure admin routes
    [self.httpServer addRoute:@"/admin" handler:^(HttpRequest *req, HttpResponse *res) {
        [self handleAdminRequest:req response:res];
    }];
}

@end
```
:::

## With Custom Summary Text

You can customize the summary text that appears in the collapsed state:

::: code-collapse Complete database migration implementation (150+ lines)
```objc
@implementation PDSMigrationManager

- (BOOL)migrateToVersion:(NSInteger)targetVersion error:(NSError **)error {
    NSInteger currentVersion = [self currentSchemaVersion:error];
    if (currentVersion < 0) {
        return NO;
    }
    
    if (currentVersion == targetVersion) {
        NSLog(@"Database already at version %ld", (long)targetVersion);
        return YES;
    }
    
    // Begin transaction
    [self.database beginTransaction];
    
    @try {
        // Apply migrations sequentially
        for (NSInteger version = currentVersion + 1; version <= targetVersion; version++) {
            NSLog(@"Migrating to version %ld", (long)version);
            
            if (![self applyMigration:version error:error]) {
                [self.database rollbackTransaction];
                return NO;
            }
        }
        
        // Update schema version
        [self setSchemaVersion:targetVersion error:error];
        
        // Commit transaction
        [self.database commitTransaction];
        
        NSLog(@"Migration complete: v%ld -> v%ld", (long)currentVersion, (long)targetVersion);
        return YES;
    }
    @catch (NSException *exception) {
        [self.database rollbackTransaction];
        if (error) {
            *error = [NSError errorWithDomain:@"PDSMigrationError"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason}];
        }
        return NO;
    }
}

- (BOOL)applyMigration:(NSInteger)version error:(NSError **)error {
    NSString *migrationSQL = [self migrationSQLForVersion:version];
    if (!migrationSQL) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSMigrationError"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Migration SQL not found"}];
        }
        return NO;
    }
    
    return [self.database executeSQL:migrationSQL error:error];
}

@end
```
:::

## Multiple Code Blocks in One Collapse

You can include multiple code blocks or even code groups inside a collapse:

::: code-collapse Platform-specific implementations
::: code-group
```objc [macOS]
#import <Security/Security.h>

@implementation PDSKeychainManager

- (BOOL)storeKey:(NSData *)keyData identifier:(NSString *)identifier error:(NSError **)error {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassKey,
        (__bridge id)kSecAttrApplicationTag: [identifier dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecValueData: keyData,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    };
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    if (status != errSecSuccess) {
        if (error) {
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        return NO;
    }
    
    return YES;
}

@end
```

```objc [Linux]
#import <openssl/evp.h>
#import <openssl/rand.h>

@implementation PDSKeychainManager

- (BOOL)storeKey:(NSData *)keyData identifier:(NSString *)identifier error:(NSError **)error {
    // On Linux, store encrypted keys in filesystem
    NSString *keyPath = [self keyPathForIdentifier:identifier];
    
    // Generate encryption key from system entropy
    unsigned char encKey[32];
    if (RAND_bytes(encKey, sizeof(encKey)) != 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"OpenSSLError" code:-1 userInfo:nil];
        }
        return NO;
    }
    
    // Encrypt key data
    NSData *encryptedData = [self encryptData:keyData withKey:encKey error:error];
    if (!encryptedData) {
        return NO;
    }
    
    // Write to secure location
    return [encryptedData writeToFile:keyPath options:NSDataWritingAtomic error:error];
}

@end
```
:::
:::

## Benefits

Collapsible code blocks are useful for:

1. **Long implementations** - Hide detailed implementation code that readers may not need immediately
2. **Complete examples** - Provide full working code without overwhelming the page
3. **Optional details** - Allow readers to expand only the sections they're interested in
4. **Better navigation** - Keep pages scannable while still providing comprehensive code
5. **Progressive disclosure** - Show summaries first, details on demand

## Accessibility

The collapsible code blocks are fully accessible:

- Keyboard navigable (Tab to focus, Enter/Space to toggle)
- Screen reader compatible with proper ARIA semantics
- Clear focus indicators
- Semantic HTML using `<details>` and `<summary>` elements

## State Preservation

The collapsed/expanded state is preserved during navigation within the same page session. However, it resets when navigating to a different page or refreshing, which is the expected behavior for `<details>` elements.

For persistent state across navigation, consider using localStorage with custom JavaScript, though this adds complexity and may not be necessary for most documentation use cases.
