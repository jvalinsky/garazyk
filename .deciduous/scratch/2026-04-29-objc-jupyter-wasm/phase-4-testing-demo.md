# Phase 4 - Testing & Demo

Date: 2026-04-29
Action node: (fill in from deciduous)

## Scope
- Test basic ObjC expressions
- Create demo notebook with ObjC features
- Test in JupyterLab + classic notebook
- Document usage and build pipeline

## Node Links
- Action node: # (fill in after creation)
- Related outcomes: # (O1, O2, O3, O4 - fill in after creation)

## Test Matrix

### Browsers
- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)

### Jupyter Versions
- [ ] JupyterLab 4.x
- [ ] Classic Notebook 6.x

## Demo Notebook Content

### Cell 1: Initialize kernel
```objective-c
// (kernel auto-initializes)
NSLog(@"Objective-C kernel ready!");
```

### Cell 2: Basic expression
```objective-c
NSString *greeting = @"Hello from ObjC in WASM!";
NSLog(@"%@", greeting);
```

### Cell 3: Object creation
```objective-c
NSObject *obj = [[NSObject alloc] init];
NSLog(@"Object: %@", obj);
NSLog(@"Description: %@", [obj description]);
```

### Cell 4: Message sending
```objective-c
@interface Greeter : NSObject
- (NSString *)greet:(NSString *)name;
@end

@implementation Greeter
- (NSString *)greet:(NSString *)name {
    return [NSString stringWithFormat:@"Hello, %@!", name];
}
@end

Greeter *g = [[Greeter alloc] init];
NSString *result = [g greet:@"World"];
NSLog(@"Result: %@", result);
```

### Cell 5: Foundation classes
```objective-c
NSArray *languages = @[@"Objective-C", @"WebAssembly", @"Jupyter"];
for (NSString *lang in languages) {
    NSLog(@"Language: %@", lang);
}
NSLog(@"Count: %ld", (long)[languages count]);
```

## Performance Results
- WASM startup time: ___ ms (fill in after testing)
- First eval latency: ___ ms
- Subsequent eval latency: ___ ms
- WASM binary size: ___ KB (clang: ___, runtime: ___, kernel: ___)

## Bugs Found
- [ ] List any bugs and their status
- [ ] NSLog output not captured
- [ ] Code completion not working
- [ ] Object persistence across cells broken

## Documentation

### README.md (already created)
- [x] Overview
- [x] Quick start
- [x] Directory structure
- [ ] Build instructions (verify)
- [ ] Usage guide
- [ ] Demo notebook published to: ____

### Build Pipeline Documented
- [ ] `scripts/wasm/build-clang-wasm.sh` - works
- [ ] `scripts/wasm/build-runtime-wasm.sh` - works
- [ ] `scripts/wasm/build-kernel-wasm.sh` - works
- [ ] `scripts/build-all.sh` - works

## Success Criteria
- [ ] WASM module loads and initializes ObjC runtime
- [ ] Basic ObjC expressions evaluate in Jupyter cell
- [ ] Demo notebook runs in JupyterLab browser
- [ ] Build pipeline documented and reproducible
