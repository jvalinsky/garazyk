# Swift API Naming Translation to Objective-C

## Overview

Swift and Objective-C have fundamentally different API design philosophies. Swift follows the "API Design Guidelines" emphasizing clarity and fluency, while Objective-C follows "Coding Guidelines for Cocoa" requiring descriptive method names with parameter types. The Clang importer automatically translates between these paradigms using rules defined in Swift Evolution SE-0005.

## Core Translation Rules

### 1. Method Name Transformation

**Swift Pattern → Objective-C Pattern**

#### Prune Redundant Type Information
Swift omits type names that are obvious from context:

```swift
// Swift (fluent, omits redundant "array")
func contains(_ element: Element) -> Bool

// Objective-C (explicit types)
- (BOOL)containsObject:(ObjectType)anObject;
```

#### Split at Prepositions for Argument Labels
Swift splits method names at prepositions to create labeled first arguments:

```swift
// Swift (reads like English)
func move(to point: CGPoint)

// Objective-C (concatenated)
- (void)moveToPoint:(CGPoint)point;
```

#### Add Default Arguments
Swift APIs often have defaults that aren't visible in Objective-C:

```swift
// Swift (defaults inferred)
func sorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows

// Objective-C (explicit parameters)
- (NSArray<ElementType> *)sortedArrayUsingComparator:(NSComparator NS_NOESCAPE)cmptr;
```

### 2. Property Translation

#### Boolean Properties Get "is" Prefix
```swift
// Swift
var isEmpty: Bool { get }

// Objective-C
@property (readonly, getter=isEmpty) BOOL empty;
```

#### Simple Noun Properties
```swift
// Swift
var count: Int { get }

// Objective-C
@property (readonly) NSUInteger count;
```

### 3. Type Name Conventions

#### UpperCamelCase for Types (Both Languages)
```swift
// Swift
class UIBezierPath
enum UIControlState

// Objective-C
@interface UIBezierPath : NSObject
typedef NS_ENUM(NSInteger, UIControlState);
```

## Real Framework Examples

### Array Operations (NSArray)

```objc
// Objective-C originals
- (BOOL)containsObject:(ObjectType)anObject;
- (NSArray<ObjectType> *)arrayByAddingObject:(ObjectType)anObject;
- (void)enumerateObjectsUsingBlock:(void (^)(ObjectType obj, NSUInteger idx, BOOL *stop))block;

// Swift translations
func contains(_ element: Element) -> Bool
func appending(_ newElement: __owned Element) -> [Element]
func forEach(_ body: (Element) throws -> Void) rethrows
```

### File Manager (NSFileManager)

```objc
// Objective-C
- (BOOL)createDirectoryAtURL:(NSURL *)url 
   withIntermediateDirectories:(BOOL)createIntermediates 
                   attributes:(NSDictionary<NSString *,id> *)attributes 
                        error:(NSError **)error;

// Swift
func createDirectory(at url: URL, 
                   withIntermediateDirectories createIntermediates: Bool = false, 
                   attributes: [FileAttributeKey : Any]? = nil) throws
```

### View Controllers (UIViewController/NSViewController)

```objc
// Objective-C
- (void)presentViewController:(UIViewController *)viewControllerToPresent 
                     animated:(BOOL)flag 
                   completion:(void (^ __nullable)(void))completion;

// Swift
func present(_ viewControllerToPresent: UIViewController, 
           animated flag: Bool, 
           completion: (() -> Void)? = nil)
```

## @objc Attribute Control

### Basic Exposure
```swift
@objc class MyClass: NSObject {
    @objc var name: String                    // Exposed as property
    @objc func doSomething()                  // Exposed as method
}
```

### Custom Naming
```swift
@objc(SWMMyClass) 
class MyClass: NSObject {
    @objc(SWMName) var name: String
    @objc(SWMDoSomething) func doSomething()
}
```

### Bulk Exposure
```swift
@objcMembers 
class MyClass: NSObject {
    func exposedMethod()     // Implicitly @objc
    @nonobjc func hiddenMethod()  // Not exposed
}
```

## Selector Generation

Swift methods get Objective-C selectors based on their Swift names:

```swift
// Swift method → Objective-C selector
func move(to point: CGPoint)        // moveToPoint:
func addLine(to point: CGPoint)      // addLineToPoint:
func setFillColor(_ color: UIColor) // setFillColor:
```

## Translation Edge Cases

### Overloaded Methods
```swift
// Swift allows overloading
func add(_ lhs: Int, _ rhs: Int) -> Int
func add(_ lhs: Double, _ rhs: Double) -> Double

// Objective-C requires unique selectors
- (NSInteger)addInt:(NSInteger)lhs rhs:(NSInteger)rhs;
- (double)addDouble:(double)lhs rhs:(double)rhs;
```

### Generics Become id
```swift
// Swift
func append<C: Collection>(_ newElements: C) where C.Element == Element

// Objective-C
- (void)addObjectsFromArray:(NSArray *)otherArray;
```

### Tuples Not Supported
```swift
// Swift (tuples in returns not @objc compatible)
func minMax() -> (min: Element, max: Element)

// Objective-C (separate methods)
- (ElementType)minValue;
- (ElementType)maxValue;
```

### Error Handling
```swift
// Swift
func data(from url: URL) throws -> Data

// Objective-C (NSError out parameter)
- (nullable NSData *)dataWithContentsOfURL:(NSURL *)url 
                                     error:(NSError **)error;
```

## NS_SWIFT_UNAVAILABLE Annotations

Apple uses special annotations to guide Swift usage:

```objc
// Discourage Swift usage with guidance
- (void)getObjects:(ObjectType __unsafe_unretained [])objects 
    NS_SWIFT_UNAVAILABLE("Use 'as [AnyObject]' instead");

// Mark as unavailable in Swift entirely
- (void)makeObjectsPerformSelector:(SEL)aSelector 
    NS_SWIFT_UNAVAILABLE("Use enumerateObjectsUsingBlock: or a for loop instead");
```

## Practical Translation Workflow

### For New Swift APIs:
1. Check `developer.apple.com/documentation/[API]` for Swift docs
2. Look for "Objective-C" tab or examples
3. Search headers: `grep -r "API" /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`
4. Test compilation with `@import Framework;`
5. Check WWDC sessions for ObjC examples

### For Legacy Objective-C APIs:
1. Apply SE-0005 rules mentally:
   - Remove redundant type names
   - Split at prepositions for labels
   - Add defaults where logical
   - Convert to fluent Swift patterns

### Debugging Translation Issues:
1. Use `@objc` attributes to force specific names
2. Check generated Swift bridging header (`MyApp-Swift.h`)
3. Use `NSClassFromString()` and `NSSelectorFromString()` for dynamic access
4. Consider `NSHostingController` for SwiftUI components

## Framework-Specific Patterns

### Foundation (Collections)
- Arrays: `contains(_:)` ← `containsObject:`
- Dictionaries: `subscript` ← `objectForKey:`
- Sets: `insert(_:)` ← `addObject:`

### AppKit/UIKit (Views)
- Views: `frame` property ← `setFrame:`/`frame` methods
- Colors: `setFill()` ← `setFillColor:`
- Events: `mouseDown(with:)` ← `mouseDown:`

### SwiftUI (Modern)
- Many APIs not exposed to Objective-C
- Use `NSHostingController` for bridging
- Limited programmatic control from ObjC

## Sources

- [Swift Evolution SE-0005](https://github.com/apple/swift-evolution/blob/main/proposals/0005-objective-c-name-translation.md)
- [API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [Coding Guidelines for Cocoa](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CodingGuidelines/CodingGuidelines.html)
- Apple Framework Headers (Foundation, AppKit, UIKit)
- WWDC Sessions on Swift/Objective-C Interoperability

## Key Takeaway

Swift APIs are designed for fluency and clarity at the call site, while Objective-C APIs include full type information in method names. The translation preserves functionality while adapting to each language's design philosophy.</content>
<parameter name="filePath">/Users/jack/Software/objpds/docs/research/swift-api-naming-translation.md