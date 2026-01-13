# Chapter 1: Introduction to Objective-C

Welcome to the first chapter of our journey to build an AT Protocol Personal Data Server from scratch. Before we can implement cryptographic identities, Merkle trees, and federated protocols, we need a solid foundation in Objective-C—the language that powers our entire codebase.

## Why Objective-C?

You might wonder why we're using Objective-C in an era dominated by Swift. Here's why:

1. **Historical significance**: Objective-C powered macOS and iOS for decades and formed the foundation of NeXTSTEP, the operating system Steve Jobs built at NeXT that became the basis for modern macOS.

2. **Direct C interoperability**: Objective-C is a strict superset of C, meaning any C code is valid Objective-C. This is crucial for our PDS—we'll interface directly with SQLite's C API, libsecp256k1 for cryptography, and BSD sockets for networking.

3. **Runtime dynamism**: Objective-C's runtime allows method swizzling, dynamic dispatch, and introspection that make it uniquely powerful for building flexible server architectures.

## The Basics: Classes and Objects

Objective-C uses a two-file convention for classes:

- **Header file (.h)**: Declares the public interface
- **Implementation file (.m)**: Contains the actual code

Let's examine a real example from our codebase—the `ATProtoValidator` class:

### The Header File

```objc
// ATProtoValidator.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoValidator : NSObject

+ (BOOL)validateDID:(NSString *)did error:(NSError **)error;
+ (BOOL)validateHandle:(NSString *)handle error:(NSError **)error;
+ (BOOL)validateCID:(NSString *)cid error:(NSError **)error;
+ (BOOL)validateTID:(NSString *)tid error:(NSError **)error;
+ (BOOL)validateNSID:(NSString *)nsid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
```

Let's break this down:

| Element | Purpose |
|---------|---------|
| `#import` | Like C's `#include` but prevents double-inclusion |
| `<Foundation/Foundation.h>` | Apple's core library (strings, arrays, etc.) |
| `NS_ASSUME_NONNULL_BEGIN/END` | Nullability annotation block—pointers are non-null by default |
| `@interface` | Declares a class interface |
| `: NSObject` | Inherits from the root class `NSObject` |
| `+` prefix | Class method (like `static` in other languages) |
| `-` prefix | Instance method (called on an object) |
| `(NSString *)` | Parameter type in parentheses |
| `error:(NSError **)error` | Output parameter pattern for errors |

### The Implementation File

```objc
// ATProtoValidator.m
#import "ATProtoValidator.h"

@implementation ATProtoValidator

+ (BOOL)validateDID:(NSString *)did error:(NSError **)error {
    if (!did) {
        if (error) {
            *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                         code:1 
                                     userInfo:@{NSLocalizedDescriptionKey: @"DID cannot be nil"}];
        }
        return NO;
    }
    
    // Check for did:plc: prefix
    if ([did hasPrefix:@"did:plc:"]) {
        NSRegularExpression *regex = [NSRegularExpression 
            regularExpressionWithPattern:@"^did:plc:[a-z2-7]{24}$" 
                                 options:0 
                                   error:nil];
        
        if ([regex numberOfMatchesInString:did 
                                   options:0 
                                     range:NSMakeRange(0, did.length)] == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                             code:2 
                                         userInfo:@{
                    NSLocalizedDescriptionKey: @"Invalid did:plc format"
                }];
            }
            return NO;
        }
        return YES;
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"ATProtoValidator" 
                                     code:4 
                                 userInfo:@{
            NSLocalizedDescriptionKey: @"Unsupported DID method"
        }];
    }
    return NO;
}

@end
```

## Message Syntax

Objective-C uses **message-passing** syntax inherited from Smalltalk:

```objc
// Other languages:
object.method(arg1, arg2);

// Objective-C:
[object methodWithArg1:arg1 arg2:arg2];
```

The method name is **distributed across the arguments**, making code read more like natural language:

```objc
// Create an error with domain, code, and user info:
[NSError errorWithDomain:@"MyDomain" 
                    code:42 
                userInfo:@{NSLocalizedDescriptionKey: @"Something went wrong"}];

// Check if a string has a prefix:
[did hasPrefix:@"did:plc:"];

// Get substring from an index:
[did substringFromIndex:8];
```

## Key Objective-C Concepts

### 1. The `id` Type

`id` is a pointer to any Objective-C object—similar to `void*` but type-safe for objects:

```objc
id anyObject = @"Hello";  // Can hold any object
anyObject = @42;          // Now holds an NSNumber
anyObject = @[@1, @2];    // Now holds an NSArray
```

### 2. The `nil` Object

Unlike null pointers in C/C++ that crash when dereferenced, messaging `nil` in Objective-C is safe and returns:
- `0` for numeric types
- `nil` for object types
- `NO` for BOOLs

```objc
NSString *name = nil;
NSUInteger length = [name length];  // Returns 0, no crash!
```

### 3. Properties

Properties provide automatic getter/setter generation:

```objc
@interface Person : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSUInteger age;
@property (nonatomic, readonly) NSString *identifier;

@end
```

| Attribute | Meaning |
|-----------|---------|
| `nonatomic` | Not thread-safe (faster) |
| `atomic` | Thread-safe (default) |
| `copy` | Create a copy when setting |
| `strong` | Keep a strong reference (ARC default) |
| `weak` | Weak reference, auto-nils |
| `readonly` | No setter generated |

### 4. Blocks (Closures)

Blocks are anonymous functions, similar to lambdas or closures:

```objc
// Define a block type
typedef void (^CompletionHandler)(NSData *data, NSError *error);

// Use it as a parameter
- (void)fetchDataWithCompletion:(CompletionHandler)completion {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSData *result = [self doWork];
        completion(result, nil);
    });
}

// Call with an inline block
[self fetchDataWithCompletion:^(NSData *data, NSError *error) {
    if (error) {
        NSLog(@"Error: %@", error);
        return;
    }
    NSLog(@"Got %lu bytes", (unsigned long)data.length);
}];
```

### 5. Protocols

Protocols define a contract that classes can adopt (similar to interfaces):

```objc
@protocol DataValidator <NSObject>

@required
- (BOOL)validate:(id)data error:(NSError **)error;

@optional
- (NSString *)validatorName;

@end

// Adoption
@interface MyValidator : NSObject <DataValidator>
@end
```

### 6. Categories

Categories add methods to existing classes without subclassing:

```objc
// NSString+Validation.h
@interface NSString (Validation)
- (BOOL)isValidDID;
- (BOOL)isValidHandle;
@end

// NSString+Validation.m
@implementation NSString (Validation)
- (BOOL)isValidDID {
    return [self hasPrefix:@"did:"];
}
- (BOOL)isValidHandle {
    return [self containsString:@"."];
}
@end

// Usage anywhere:
NSString *did = @"did:plc:abc123";
if ([did isValidDID]) {
    NSLog(@"Valid!");
}
```

## Error Handling Pattern

Objective-C uses a pass-by-reference pattern for errors:

```objc
- (BOOL)doSomethingWithError:(NSError **)error {
    if (somethingWentWrong) {
        if (error) {  // Always check if caller wants errors
            *error = [NSError errorWithDomain:@"MyDomain"
                                         code:100
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Description",
                NSLocalizedFailureReasonErrorKey: @"Reason"
            }];
        }
        return NO;
    }
    return YES;
}

// Usage:
NSError *error = nil;
if (![obj doSomethingWithError:&error]) {
    NSLog(@"Failed: %@", error.localizedDescription);
}
```

## Practical Exercise: Build PDSConfig

Create a configuration class for our PDS that:
1. Loads settings from a JSON file
2. Validates required fields
3. Provides typed accessors

**PDSConfig.h:**
```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSConfig : NSObject

@property (nonatomic, readonly) NSString *hostname;
@property (nonatomic, readonly) NSUInteger port;
@property (nonatomic, readonly) NSString *databasePath;

+ (nullable instancetype)configFromFile:(NSString *)path 
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
```

**PDSConfig.m:**
```objc
#import "PDSConfig.h"

@implementation PDSConfig

+ (nullable instancetype)configFromFile:(NSString *)path error:(NSError **)error {
    // Read file data
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    if (!data) return nil;
    
    // Parse JSON
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data 
                                                         options:0 
                                                           error:error];
    if (!json) return nil;
    
    // Validate required fields
    NSString *hostname = json[@"hostname"];
    NSNumber *port = json[@"port"];
    NSString *dbPath = json[@"databasePath"];
    
    if (!hostname || !port || !dbPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"PDSConfig"
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"Missing required config fields"
            }];
        }
        return nil;
    }
    
    // Create instance
    PDSConfig *config = [[PDSConfig alloc] init];
    config->_hostname = [hostname copy];
    config->_port = port.unsignedIntegerValue;
    config->_databasePath = [dbPath copy];
    
    return config;
}

@end
```

---

## Memory Management: ARC

Modern Objective-C uses **ARC (Automatic Reference Counting)** to manage memory. Unlike garbage collection, ARC inserts retain/release calls at compile time.

### The Basics

```objc
// ARC automatically:
// - Retains objects when assigned to strong references
// - Releases objects when strong references go out of scope
// - Nils weak references when the object is deallocated

@property (nonatomic, strong) NSString *name;  // Keeps object alive
@property (nonatomic, weak) id<Delegate> delegate;  // Doesn't keep alive
```

### Strong vs Weak References

```objc
// Strong: "I need this object to stay alive"
@property (nonatomic, strong) NSArray *items;

// Weak: "I want to reference this, but don't keep it alive"
@property (nonatomic, weak) id<MyDelegate> delegate;

// Copy: "I want my own copy of this value"
@property (nonatomic, copy) NSString *name;
```

### The Weak-Strong Dance (for blocks)

When using `self` in blocks, avoid retain cycles:

```objc
// WRONG: Creates retain cycle
[self.server handleRequest:^{
    [self processResult];  // Block captures self strongly
}];

// RIGHT: Break the cycle
__weak typeof(self) weakSelf = self;
[self.server handleRequest:^{
    typeof(weakSelf) strongSelf = weakSelf;
    if (strongSelf) {
        [strongSelf processResult];
    }
}];
```

---

## Common Mistakes

### Mistake 1: Forgetting Error Parameter Guard

❌ **What people do:**
```objc
- (BOOL)doSomethingWithError:(NSError **)error {
    if (failed) {
        *error = [NSError errorWithDomain:@"X" code:1 userInfo:nil];  // CRASH if error is NULL!
        return NO;
    }
}
```

**Why this fails:**
- Caller can pass `nil` for error if they don't care
- Dereferencing NULL causes crash

✅ **Correct approach:**
```objc
- (BOOL)doSomethingWithError:(NSError **)error {
    if (failed) {
        if (error) {  // Always check!
            *error = [NSError errorWithDomain:@"X" code:1 userInfo:nil];
        }
        return NO;
    }
}
```

### Mistake 2: Using `==` for String Comparison

❌ **What people do:**
```objc
NSString *handle = @"alice.bsky.social";
if (handle == @"alice.bsky.social") {  // WRONG!
    // May not work - comparing pointers, not content
}
```

**Why this fails:**
- `==` compares object pointers, not content
- Works sometimes with string literals (cached), fails with runtime strings

✅ **Correct approach:**
```objc
if ([handle isEqualToString:@"alice.bsky.social"]) {
    // Correctly compares string content
}
```

### Mistake 3: Forgetting `copy` for NSString Properties

❌ **What people do:**
```objc
@property (nonatomic, strong) NSString *handle;  // WRONG for strings

// Later...
NSMutableString *temp = [NSMutableString stringWithString:@"alice"];
obj.handle = temp;
[temp appendString:@".evil.com"];  // obj.handle also changed!
```

**Why this fails:**
- NSMutableString is a subclass of NSString
- Strong just keeps a reference; caller can mutate it

✅ **Correct approach:**
```objc
@property (nonatomic, copy) NSString *handle;  // Creates immutable copy
// Now mutations to the original don't affect the property
```

---

## Summary

In this chapter, you learned:

- ✅ Objective-C's message-passing syntax
- ✅ Class structure with `.h` and `.m` files
- ✅ Properties and their attributes (strong, weak, copy)
- ✅ The `id` type and `nil` safety
- ✅ Blocks for closures/callbacks
- ✅ Protocols and categories
- ✅ Error handling patterns
- ✅ ARC memory management basics

## Key Takeaways

1. **Message syntax is self-documenting** - `[obj doThis:x withThat:y]` reads like English.

2. **nil is safe to message** - No null pointer exceptions, just returns 0/nil/NO.

3. **Always guard error parameters** - Check `if (error)` before dereferencing.

4. **Use `copy` for string properties** - Prevents unexpected mutations.

## Next Steps

In **Chapter 2**, we'll dive deep into the **Foundation framework**—the collection of classes like `NSString`, `NSArray`, `NSDictionary`, and `NSData` that form the backbone of every Objective-C application.

---

**Files Referenced in This Chapter:**
- [ATProtoValidator.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/ATProtoValidator.h)
- [ATProtoValidator.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/ATProtoValidator.m)
