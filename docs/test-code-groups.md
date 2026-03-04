# Code Groups Test Page

This page tests the VitePress code group feature for platform-specific code.

## Basic Code Group

::: code-group

```objective-c [macOS]
#import <Security/Security.h>

- (NSData *)generateRandomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    SecRandomCopyBytes(kSecRandomDefault, length, data.mutableBytes);
    return data;
}
```

```objective-c [Linux]
#import <openssl/rand.h>

- (NSData *)generateRandomBytes:(NSUInteger)length {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    RAND_bytes(data.mutableBytes, (int)length);
    return data;
}
```

:::

## Code Group with Line Highlighting

::: code-group

```objective-c{3-4} [macOS]
- (void)setupKeychain {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.atproto.pds"
    };
    SecItemAdd((__bridge CFDictionaryRef)query, NULL);
}
```

```objective-c{3-4} [Linux]
- (void)setupKeystore {
    NSString *path = @"/var/lib/pds/keys";
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions: @0700}
                                                    error:nil];
}
```

:::

## Code Group with Titles

::: code-group

```objective-c [macOS] [PDSKeyManagerMac.m]
#import <Security/Security.h>

@implementation PDSKeyManagerMac

- (BOOL)storeKey:(NSData *)keyData forAccount:(NSString *)account {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.atproto.pds.signing",
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecValueData: keyData
    };
    
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess;
}

@end
```

```objective-c [Linux] [PDSKeyManagerLinux.m]
#import <Foundation/Foundation.h>

@implementation PDSKeyManagerLinux

- (BOOL)storeKey:(NSData *)keyData forAccount:(NSString *)account {
    NSString *keystorePath = @"/var/lib/pds/keys";
    NSString *keyPath = [keystorePath stringByAppendingPathComponent:account];
    
    // Write with restricted permissions
    int fd = open([keyPath fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd == -1) return NO;
    
    write(fd, keyData.bytes, keyData.length);
    fsync(fd);
    close(fd);
    
    return YES;
}

@end
```

:::

## Three-Way Code Group

::: code-group

```bash [macOS Build]
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(sysctl -n hw.ncpu)
```

```bash [Linux Build]
mkdir build-linux && cd build-linux
cmake .. -DCMAKE_BUILD_TYPE=Debug
make -j$(nproc)
```

```bash [Docker Build]
docker build -f docker/Dockerfile.gnustep -t atprotopds:latest .
docker run -p 2583:2583 atprotopds:latest
```

:::

## Expected Behavior

When viewing this page:
1. Each code group should show tabs at the top
2. Clicking a tab should switch the displayed code
3. Syntax highlighting should work in all tabs
4. Line highlighting should work when specified
5. Copy buttons should appear on hover
6. The feature should work in both light and dark themes
