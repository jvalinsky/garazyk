# Chapter 2: The Foundation Framework

The Foundation framework is the bedrock of all Apple platform development.  Originally developed by NeXT Computer, it provides essential data types, collections, and utilities that every Objective-C application relies upon. In this chapter, we'll master the core classes you'll use throughout our PDS implementation.

## The NS Prefix

You'll notice that Foundation classes start with `NS`—this stands for **NeXTSTEP**, the operating system that became the foundation of macOS. This prefix exists because Objective-C doesn't have namespaces, so class prefixes prevent naming collisions.

## NSString: Text Handling

`NSString` is an immutable sequence of Unicode characters. It's the most fundamental class you'll use.

### Creating Strings

```objc
// String literals (most common)
NSString *did = @"did:plc:z72i7hdynmk6r22z27h6tvur";

// From format (like printf)
NSString *uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];

// From C string
const char *cString = "Hello, World!";
NSString *fromC = [NSString stringWithUTF8String:cString];

// From data (with encoding)
NSData *utf8Data = /* ... */;
NSString *fromData = [[NSString alloc] initWithData:utf8Data encoding:NSUTF8StringEncoding];
```

### Common Operations

```objc
NSString *handle = @"alice.bsky.social";

// Length and comparison
NSUInteger length = handle.length;                    // 17
BOOL equal = [handle isEqualToString:@"bob.bsky.social"];  // NO

// Prefix/suffix checking (used throughout ATProto validation)
BOOL isDID = [handle hasPrefix:@"did:"];              // NO
BOOL isBsky = [handle hasSuffix:@".bsky.social"];     // YES

// Substrings
NSString *tld = [handle substringFromIndex:14];       // "ial"
NSString *first5 = [handle substringToIndex:5];       // "alice"
NSString *range = [handle substringWithRange:NSMakeRange(0, 5)];  // "alice"

// Case conversion  
NSString *upper = [handle uppercaseString];           // "ALICE.BSKY.SOCIAL"
NSString *lower = [handle lowercaseString];           // (no change)

// Searching
NSRange found = [handle rangeOfString:@"bsky"];
if (found.location != NSNotFound) {
    NSLog(@"Found at index %lu", (unsigned long)found.location);  // 6
}

// Splitting into components
NSArray *parts = [handle componentsSeparatedByString:@"."];
// @[@"alice", @"bsky", @"social"]

// Joining components
NSString *rejoined = [parts componentsJoinedByString:@"-"];
// "alice-bsky-social"

// Converting to C string (for C APIs like SQLite)
const char *utf8 = [handle UTF8String];
```

<script setup>
const foundationCode = `#import <Foundation/Foundation.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // NSString Operations
        NSString *handle = @"alice.bsky.social";
        NSLog(@"Handle: %@", handle);
        
        if ([handle hasSuffix:@".bsky.social"]) {
            NSLog(@"✅ Valid domain");
        }
        
        // NSArray & Components
        NSArray *parts = [handle componentsSeparatedByString:@"."];
        NSLog(@"Parts: %@", parts);
        
        // NSDictionary
        NSDictionary *repo = @{
            @"handle": handle,
            @"did": @"did:plc:z72i7hd...",
            @"collections": @[@"app.bsky.feed.post", @"app.bsky.graph.follow"]
        };
        
        NSLog(@"Repo Data: %@", repo);
    }
    return 0;
}`;
</script>

<ObjcRunner :initialCode="foundationCode" />

### NSMutableString

When you need to build up a string incrementally:

```objc
NSMutableString *builder = [NSMutableString string];

[builder appendString:@"at://"];
[builder appendString:did];
[builder appendString:@"/"];
[builder appendString:collection];
[builder appendFormat:@"/%@", rkey];

NSString *result = [builder copy];  // Convert to immutable
```

## NSData: Binary Data

`NSData` represents a buffer of bytes—essential for cryptography, network I/O, and file handling.

### Creating NSData

```objc
// From raw bytes
uint8_t bytes[] = {0x01, 0x71, 0x12, 0x20};
NSData *data = [NSData dataWithBytes:bytes length:4];

// From a file
NSError *error = nil;
NSData *fileData = [NSData dataWithContentsOfFile:@"/path/to/file" 
                                          options:0 
                                            error:&error];

// From a string
NSData *stringData = [@"Hello" dataUsingEncoding:NSUTF8StringEncoding];
```

### Working with NSData

```objc
NSData *hash = /* SHA-256 result */;

// Length
NSUInteger len = hash.length;  // 32 for SHA-256

// Access raw bytes
const uint8_t *bytes = hash.bytes;
uint8_t firstByte = bytes[0];

// Extract subdata
NSData *first4 = [hash subdataWithRange:NSMakeRange(0, 4)];

// Compare
BOOL equal = [hash isEqualToData:expectedHash];

// Write to file
[hash writeToFile:@"/path/to/output" atomically:YES];
```

### NSMutableData

```objc
NSMutableData *buffer = [NSMutableData data];

// Append CIDv1 version byte
uint8_t version = 0x01;
[buffer appendBytes:&version length:1];

// Append more data
[buffer appendData:codecBytes];
[buffer appendData:multihash];

NSData *cid = [buffer copy];  // Convert to immutable
```

## NSArray: Ordered Collections

`NSArray` is an ordered, immutable collection of objects.

### Creating Arrays

```objc
// Literal syntax (most common)
NSArray *methods = @[@"did:plc", @"did:web"];

// Empty array
NSArray *empty = @[];

// From objects
NSArray *fromObjects = [NSArray arrayWithObjects:@"one", @"two", nil];
// Note: Must terminate with nil!
```

### Array Operations

```objc
NSArray *tlds = @[@"alt", @"arpa", @"example", @"invalid", @"local"];

// Count and access
NSUInteger count = tlds.count;              // 5
NSString *first = tlds[0];                  // "alt" (subscript syntax)
NSString *last = [tlds lastObject];         // "local"

// Searching
BOOL hasLocal = [tlds containsObject:@"local"];  // YES
NSUInteger idx = [tlds indexOfObject:@"arpa"];   // 1

// Iteration
for (NSString *tld in tlds) {
    NSLog(@"TLD: %@", tld);
}

// With index
[tlds enumerateObjectsUsingBlock:^(NSString *tld, NSUInteger idx, BOOL *stop) {
    NSLog(@"%lu: %@", (unsigned long)idx, tld);
    if ([tld isEqualToString:@"example"]) {
        *stop = YES;  // Break out of enumeration
    }
}];

// Filtering
NSArray *short = [tlds filteredArrayUsingPredicate:
    [NSPredicate predicateWithFormat:@"length < 5"]];
// @[@"alt", @"arpa"]

// Joining to string
NSString *joined = [tlds componentsJoinedByString:@", "];
// "alt, arpa, example, invalid, local"
```

### NSMutableArray

```objc
NSMutableArray *accounts = [NSMutableArray array];

// Add objects
[accounts addObject:@"alice"];
[accounts addObject:@"bob"];
[accounts insertObject:@"carol" atIndex:1];
// @[@"alice", @"carol", @"bob"]

// Remove
[accounts removeObject:@"carol"];
[accounts removeObjectAtIndex:0];
[accounts removeLastObject];

// Replace
accounts[0] = @"dave";

// Sorting
[accounts sortUsingSelector:@selector(compare:)];
```

## NSDictionary: Key-Value Storage

`NSDictionary` maps keys to values—essential for JSON handling and configuration.

### Creating Dictionaries

```objc
// Literal syntax
NSDictionary *commit = @{
    @"did": @"did:plc:z72i7hdynmk6r22z27h6tvur",
    @"version": @3,
    @"rev": @"3jwdwj2ctlk26",
    @"prev": [NSNull null]  // Use NSNull for JSON null
};

// Empty dictionary
NSDictionary *empty = @{};
```

### Dictionary Operations

```objc
NSDictionary *account = @{
    @"did": @"did:plc:abc123",
    @"handle": @"alice.bsky.social",
    @"email": @"alice@example.com"
};

// Access values
NSString *did = account[@"did"];              // Subscript syntax
NSString *handle = [account objectForKey:@"handle"];

// Safe access (nil if missing)
NSString *avatar = account[@"avatar"];        // nil

// Check for key
BOOL hasEmail = [account.allKeys containsObject:@"email"];  // YES

// Get all keys/values
NSArray *keys = account.allKeys;
NSArray *values = account.allValues;

// Iteration
for (NSString *key in account) {
    NSLog(@"%@: %@", key, account[key]);
}

[account enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
    NSLog(@"%@ = %@", key, value);
}];
```

### NSMutableDictionary

```objc
NSMutableDictionary *params = [NSMutableDictionary dictionary];

// Add/update entries
params[@"repo"] = did;
params[@"collection"] = @"app.bsky.feed.post";
[params setObject:@"self" forKey:@"rkey"];

// Remove entries
[params removeObjectForKey:@"rkey"];

// Merge another dictionary
[params addEntriesFromDictionary:@{@"limit": @50}];
```

## NSNumber: Boxing Primitives

Objective-C collections can only hold objects, so primitives need boxing:

```objc
// Boxing with literals
NSNumber *count = @42;
NSNumber *pi = @3.14159;
NSNumber *yes = @YES;

// From primitives
NSNumber *timestamp = [NSNumber numberWithUnsignedLongLong:1704067200000000ULL];

// Unboxing
NSInteger intVal = [count integerValue];
double doubleVal = [pi doubleValue];
BOOL boolVal = [yes boolValue];
uint64_t ts = [timestamp unsignedLongLongValue];
```

## NSDate: Time Handling

```objc
// Current time
NSDate *now = [NSDate date];

// Unix timestamp (seconds since 1970)
NSTimeInterval timestamp = [now timeIntervalSince1970];

// From timestamp
NSDate *fromTimestamp = [NSDate dateWithTimeIntervalSince1970:1704067200.0];

// Comparison
if ([date1 compare:date2] == NSOrderedAscending) {
    NSLog(@"date1 is earlier");
}

// Formatting for display
NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
NSString *iso8601 = [formatter stringFromDate:now];
```

## JSON Serialization

`NSJSONSerialization` converts between JSON and Foundation objects:

### Parsing JSON

```objc
NSString *jsonString = @"{\"did\": \"did:plc:abc\", \"handle\": \"alice.bsky.social\"}";
NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];

NSError *error = nil;
NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:jsonData
                                                       options:0
                                                         error:&error];
if (error) {
    NSLog(@"Parse error: %@", error.localizedDescription);
} else {
    NSString *did = parsed[@"did"];
}
```

### Writing JSON

```objc
NSDictionary *record = @{
    @"$type": @"app.bsky.feed.post",
    @"text": @"Hello from NSPds!",
    @"createdAt": @"2024-01-01T00:00:00Z"
};

NSError *error = nil;
NSData *jsonData = [NSJSONSerialization dataWithJSONObject:record
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
if (!error) {
    NSString *jsonString = [[NSString alloc] initWithData:jsonData 
                                                 encoding:NSUTF8StringEncoding];
    NSLog(@"%@", jsonString);
}
```

## NSError: Error Handling

Foundation uses `NSError` for detailed error information:

```objc
// Creating an error
NSError *error = [NSError errorWithDomain:@"PDSDatabase"
                                     code:1001
                                 userInfo:@{
    NSLocalizedDescriptionKey: @"Query execution failed",
    NSLocalizedFailureReasonErrorKey: @"Table 'accounts' does not exist",
    @"sql": @"SELECT * FROM accounts"
}];

// Reading error properties
NSString *domain = error.domain;              // "PDSDatabase"
NSInteger code = error.code;                  // 1001
NSString *message = error.localizedDescription;
NSString *reason = error.localizedFailureReason;
NSString *sql = error.userInfo[@"sql"];
```

## Practical Example: TID Implementation

Let's examine the `TID` (Timestamp Identifier) class from our codebase—it demonstrates many Foundation patterns:

```objc
// TID.h
@interface TID : NSObject <NSCopying, NSSecureCoding>

@property (readonly, nonatomic, strong) NSString *stringValue;
@property (readonly, nonatomic) uint64_t timestamp;

+ (instancetype)tid;                                    // Current time
+ (nullable instancetype)tidFromString:(NSString *)string;
+ (instancetype)tidWithDate:(NSDate *)date;

- (NSComparisonResult)compare:(TID *)other;

@end
```

```objc
// TID.m
static const char kTIDBase32Alphabet[] = "234567abcdefghijklmnopqrstuvwxyz";

@implementation TID

+ (instancetype)tid {
    // NSDate for current time, convert to microseconds
    return [self tidWithTimestamp:[[NSDate date] timeIntervalSince1970] * 1000000];
}

+ (instancetype)tidWithTimestamp:(uint64_t)timestamp {
    TID *tid = [[TID alloc] init];
    tid->_timestamp = timestamp;
    tid->_stringValue = [self encodeTimestamp:timestamp];
    return tid;
}

+ (NSString *)encodeTimestamp:(uint64_t)timestamp {
    // Use base32-sortable encoding
    uint64_t remaining = timestamp;
    char buffer[14];
    
    for (int i = 12; i >= 0; i--) {
        uint32_t index = remaining % 32;
        buffer[i] = kTIDBase32Alphabet[index];
        remaining /= 32;
    }
    buffer[13] = '\0';
    
    // Create NSString from C string
    return [NSString stringWithUTF8String:buffer];
}

+ (nullable instancetype)tidFromString:(NSString *)string {
    // Validate length
    if (string.length != 13) {
        return nil;  // Return nil for invalid input
    }
    // ... decode logic
}

- (NSComparisonResult)compare:(TID *)other {
    // Use NSComparisonResult enum for sorting
    if (self.timestamp < other.timestamp) {
        return NSOrderedAscending;
    } else if (self.timestamp > other.timestamp) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (NSString *)description {
    // Custom NSLog representation
    return [NSString stringWithFormat:@"TID(%@)", self.stringValue];
}

@end
```

## Practical Exercise: Build RecordURI

Create a class that parses and validates AT Protocol URIs (`at://did/collection/rkey`):

**RecordURI.h:**
```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RecordURI : NSObject

@property (readonly, nonatomic, copy) NSString *did;
@property (readonly, nonatomic, copy) NSString *collection;
@property (readonly, nonatomic, copy) NSString *rkey;

+ (nullable instancetype)uriFromString:(NSString *)string error:(NSError **)error;
- (NSString *)stringValue;

@end

NS_ASSUME_NONNULL_END
```

**RecordURI.m:**
```objc
#import "RecordURI.h"

@implementation RecordURI

+ (nullable instancetype)uriFromString:(NSString *)string error:(NSError **)error {
    // Check prefix
    if (![string hasPrefix:@"at://"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"RecordURI" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"URI must start with at://"}];
        }
        return nil;
    }
    
    // Remove prefix and split
    NSString *path = [string substringFromIndex:5];
    NSArray *parts = [path componentsSeparatedByString:@"/"];
    
    if (parts.count < 3) {
        if (error) {
            *error = [NSError errorWithDomain:@"RecordURI" code:2
                userInfo:@{NSLocalizedDescriptionKey: @"URI must have did/collection/rkey"}];
        }
        return nil;
    }
    
    RecordURI *uri = [[RecordURI alloc] init];
    uri->_did = [parts[0] copy];
    uri->_collection = [parts[1] copy];
    uri->_rkey = [parts[2] copy];
    
    return uri;
}

- (NSString *)stringValue {
    return [NSString stringWithFormat:@"at://%@/%@/%@", 
            self.did, self.collection, self.rkey];
}

- (NSString *)description {
    return [self stringValue];
}

@end
```

---

## When to Use Which Class

A quick reference for choosing the right Foundation class:

| Need | Immutable | Mutable |
|------|-----------|---------|
| Text | `NSString` | `NSMutableString` |
| Binary data | `NSData` | `NSMutableData` |
| Ordered list | `NSArray` | `NSMutableArray` |
| Key-value map | `NSDictionary` | `NSMutableDictionary` |
| Unique values | `NSSet` | `NSMutableSet` |
| Ordered unique | `NSOrderedSet` | `NSMutableOrderedSet` |

**Decision guide:**
- **Start immutable** - Use mutable only when building incrementally
- **Return immutable** - Always return `copy` from methods
- **Prefer literals** - `@"string"`, `@[]`, `@{}` when possible

---

## Common Mistakes

### Mistake 1: Modifying Collections While Iterating

❌ **What people do:**
```objc
for (NSString *item in mutableArray) {
    if ([item hasPrefix:@"temp_"]) {
        [mutableArray removeObject:item];  // CRASH!
    }
}
```

**Why this fails:**
- Fast enumeration tracks collection state
- Mutation during enumeration throws exception

✅ **Correct approach:**
```objc
// Collect items to remove first
NSMutableArray *toRemove = [NSMutableArray array];
for (NSString *item in mutableArray) {
    if ([item hasPrefix:@"temp_"]) {
        [toRemove addObject:item];
    }
}
[mutableArray removeObjectsInArray:toRemove];

// Or use filter predicate
[mutableArray filterUsingPredicate:
    [NSPredicate predicateWithFormat:@"NOT SELF BEGINSWITH 'temp_'"]];
```

### Mistake 2: Forgetting NSNull in JSON

❌ **What people do:**
```objc
NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ...];
NSString *avatar = json[@"avatar"];
NSUInteger len = avatar.length;  // CRASH if avatar is NSNull!
```

**Why this fails:**
- JSON `null` becomes `[NSNull null]`, not `nil`
- `[NSNull null]` doesn't respond to `length`

✅ **Correct approach:**
```objc
id avatar = json[@"avatar"];
if (avatar && avatar != [NSNull null]) {
    NSString *avatarString = (NSString *)avatar;
    // Now safe to use
}
```

### Mistake 3: Using Wrong Encoding for NSData/NSString

❌ **What people do:**
```objc
NSData *data = [string dataUsingEncoding:NSASCIIStringEncoding];
// Returns nil for non-ASCII characters like emoji!
```

**Why this fails:**
- ASCII only supports 128 characters
- Unicode characters (emoji, non-English) are dropped or cause nil

✅ **Correct approach:**
```objc
// Always use UTF-8 for AT Protocol data
NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
if (!data) {
    NSLog(@"String contains invalid UTF-8 sequences");
}
```

---

## Summary

In this chapter, you learned:

- ✅ **NSString** for text handling, prefix/suffix checks, splitting and joining
- ✅ **NSData** for binary data, bytes access, and file I/O
- ✅ **NSArray** and **NSDictionary** for collections
- ✅ **NSNumber** for boxing primitives
- ✅ **NSDate** for time handling
- ✅ **NSJSONSerialization** for JSON parsing
- ✅ **NSError** for rich error information

## Key Takeaways

1. **Immutable by default** - Use mutable variants only when building incrementally.

2. **UTF-8 everywhere** - Always use `NSUTF8StringEncoding` for AT Protocol data.

3. **Watch for NSNull** - JSON null is `[NSNull null]`, not `nil`.

4. **Never mutate during enumeration** - Collect changes first, apply after.

## Next Steps

In **Chapter 3**, we'll set up a proper build system with CMake and XcodeGen, establishing the project structure that will hold all our PDS modules.

---

**Files Referenced in This Chapter:**
- [TID.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/TID.h)
- [TID.m](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Core/TID.m)
- [PDSDatabase.h](file:///Users/jack/Software/objpds/ATProtoPDS/Sources/Database/PDSDatabase.h)
