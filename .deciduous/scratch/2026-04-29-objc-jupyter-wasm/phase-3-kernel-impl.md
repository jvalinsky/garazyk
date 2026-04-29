# Phase 3 - Kernel Implementation

Date: 2026-04-29
Action node: (fill in from deciduous)

## Scope
- Implement Jupyter kernel protocol in ObjC
- Build WASM module with runtime + kernel glue
- Implement kernel.js bootstrap
- Wire REPL eval loop

## Node Links
- Action node: # (fill in after creation)
- Related decisions: # (D3: Transport - postMessage, D5: Kernel Template - xeus-like)

## Jupyter Protocol Implementation

### Messages to Handle

#### kernel_info_request/reply
```objective-c
- (NSDictionary *)kernel_info_request {
    return @{
        @"protocol_version": @[@5, @3],
        @"language_info": @{
            @"name": @"objective-c",
            @"version": @"2.2",
            @"mimetype": @"text/x-objective-c"
        },
        @"status": @"ok"
    };
}
```

#### execute_request/reply
```objective-c
- (NSDictionary *)execute_request:(NSString *)code cellId:(NSString *)cellId {
    @try {
        // Write code to temp file
        NSString *tempFile = [NSString stringWithFormat:@"/tmp/cell_%@.m", cellId ?: @"0"];
        [code writeToFile:tempFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        // Compile to WASM (using embedded clang.wasm)
        NSString *outputWasm = [tempFile stringByAppendingString:@".wasm"];
        BOOL compiled = [self compileObjCToWasm:tempFile output:outputWasm];
        
        if (!compiled) {
            return @{
                @"status": @"error",
                @"ename": @"CompileError",
                @"evalue": @"Failed to compile ObjC code"
            };
        }
        
        // Load and execute WASM module
        void *wasmModule = load_wasm(outputWasm);
        id result = execute_wasm_entry(wasmModule);
        
        // Capture NSLog output (redirected to JS)
        // Return result as Jupyter message
        return @{
            @"status": @"ok",
            @"execution_count": @(self.executionCount++),
            @"data": @{
                @"text/plain": [result description] ?: @""
            }
        };
    }
    @catch (NSException *exception) {
        return @{
            @"status": @"error",
            @"ename": @"NSException",
            @"evalue": exception.reason ?: @"Unknown error",
            @"traceback": @[]
        };
    }
}
```

#### complete_request/reply (code completion)
```objective-c
- (NSDictionary *)complete_request:(NSString *)code cursorPos:(NSInteger)cursorPos {
    NSMutableArray *matches = [NSMutableArray array];
    
    // Get all registered classes
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    
    if (classes) {
        NSString *partial = [self extractPartialAtPosition:cursorPos inCode:code];
        
        for (unsigned int i = 0; i < classCount; i++) {
            const char *className = class_getName(classes[i]);
            NSString *name = [NSString stringWithUTF8String:className];
            
            if (partial && [name hasPrefix:partial]) {
                [matches addObject:name];
            } else if (!partial) {
                if ([name hasPrefix:@"NS"] || [name hasPrefix:@"UI"]) {
                    [matches addObject:name];
                }
            }
        }
        free(classes);
    }
    
    return @{
        @"status": @"ok",
        @"matches": matches,
        @"cursor_start": @(MAX(0, cursorPos - (partial ? partial.length : 0))),
        @"cursor_end": @(cursorPos)
    };
}
```

## REPL Loop

```
Jupyter message (postMessage)
  -> kernel.js receives
    -> Calls WASM export with code string
    -> WASM: objc runtime evaluates expression
    -> Result returned to JavaScript
    -> Post result back to Jupyter
```

## Code Architecture

```
kernel.js          # Jupyter handshake, postMessage bridge
  └── runtime.wasm # Compiled ObjC runtime + kernel glue
        └── libobjc2.a # Objective-C runtime
```

## WASM Exports Needed
- [ ] `init_kernel()` - Initialize ObjC runtime
- [ ] `execute_code(cStr)` - Evaluate ObjC code string
- [ ] `get_result()` - Get last evaluation result
- [ ] `complete_code(cStr, pos)` - Code completion

## JS Imports Needed
- [ ] `objc_log(ptr)` - NSLog bridge to Jupyter IOPub stream
- [ ] `kernel_result(jsonPtr)` - Return execution result to JS

## Build Commands

```bash
# Compile kernel to WASM
emcc -O2 \
  -target wasm32-unknown-emscripten \
  -fobjc-runtime=gnustep-2.2 \
  -fwasm-exceptions \
  -I../compiler/ \
  -L../compiler/ \
  -lobjc2 \
  -o ../jupyterlite/kernel/kernel.wasm \
  kernel/objc_kernel.m \
  kernel/objc_runtime_bridge.c

echo "kernel.wasm built: $(du -h ../jupyterlite/kernel/kernel.wasm | cut -f1)"
```

## Issues Encountered
- [ ] List any bugs and fixes
- [ ] WASM export/import binding issues
- [ ] NSLog capture not working
- [ ] ObjC runtime initialization problems
