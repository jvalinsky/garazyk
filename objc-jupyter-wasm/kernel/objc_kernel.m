//
//  objc_kernel.m
//  Objective-C Jupyter Kernel Protocol Implementation
//
//  Copyright (c) 2026 Jack Valinsky
//

#import "objc_kernel.h"
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

// MARK: - Globals

static ObjcKernel *_sharedKernel = nil;

// MARK: - ObjcKernel Implementation

@implementation ObjcKernel

- (instancetype)init {
    self = [super init];
    if (self) {
        _executionCount = 0;
    }
    return self;
}

+ (instancetype)sharedKernel {
    if (!_sharedKernel) {
        _sharedKernel = [[ObjcKernel alloc] init];
    }
    return _sharedKernel;
}

// MARK: - Kernel Info

- (NSDictionary *)kernel_info_request {
    return @{
        @"protocol_version": @[@5, @3],
        @"language_info": @{
            @"name": @"objective-c",
            @"version": @"2.2",
            @"mimetype": @"text/x-objective-c",
            @"file_extension": @".m",
            @"pygments_lexer": @"objective-c",
            @"codemirror_mode": @"clike"
        },
        @"status": @"ok"
    };
}

// MARK: - Execute Request

- (NSDictionary *)execute_request:(NSString *)code
                       cellId:(NSString *)cellId {
    
    @try {
        // 1. Write code to temp file
        NSString *tempFile = [NSString stringWithFormat:@"/tmp/objc_cell_%@.m", cellId ?: @"0"];
        NSError *writeError = nil;
        BOOL written = [code writeToFile:tempFile
                                atomically:YES
                                  encoding:NSUTF8StringEncoding
                                     error:&writeError];
        
        if (!written) {
            return @{
                @"status": @"error",
                @"ename": @"WriteError",
                @"evalue": [writeError localizedDescription] ?: @"Failed to write code",
                @"traceback": @[]
            };
        }
        
        // 2. Compile and execute (simplified - in production, use WASM runtime)
        id result = [self evaluateCode:code];
        
        self.executionCount++;
        
        // 3. Return result
        return @{
            @"status": @"ok",
            @"execution_count": @(self.executionCount),
            @"data": @{
                @"text/plain": result ? [result description] : @"<nil>"
            }
        };
    }
    @catch (NSException *exception) {
        return @{
            @"status": @"error",
            @"ename": exception.name ?: @"NSException",
            @"evalue": exception.reason ?: @"Unknown error",
            @"traceback": @[]
        };
    }
}

// MARK: - Code Evaluation (Placeholder for WASM execution)

- (id)evaluateCode:(NSString *)code {
    // In production: Load code into WASM runtime and execute
    // For now, return a description of what would happen
    
    // Parse code to detect class definitions, method calls, etc.
    if ([code containsString:@"@interface"]) {
        return @"Class definition detected (would be registered in WASM runtime)";
    }
    
    if ([code containsString:@"@implementation"]) {
        return @"Implementation detected (would be compiled and loaded)";
    }
    
    // Simple expression evaluation placeholder
    return [NSString stringWithFormat:@"[Evaluated: %@ chars]", @(code.length)];
}

// MARK: - Complete Request

- (NSDictionary *)complete_request:(NSString *)code
                         cursorPos:(NSInteger)cursorPos {
    
    NSMutableArray *matches = [NSMutableArray array];
    
    // Get all registered classes
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    
    if (classes) {
        for (unsigned int i = 0; i < classCount; i++) {
            const char *className = class_getName(classes[i]);
            NSString *name = [NSString stringWithUTF8String:className];
            
            if ([name containsString:@"NS"] || [name containsString:@"UI"]) {
                [matches addObject:name];
            }
        }
        free(classes);
    }
    
    // Add common selectors
    [matches addObjectsFromArray:@[
        @"alloc", @"init", @"new",
        @"retain", @"release", @"autorelease",
        @"class", @"superclass", @"description"
    ]];
    
    return @{
        @"status": @"ok",
        @"matches": matches,
        @"cursor_start": @(MAX(0, cursorPos - 1)),
        @"cursor_end": @(cursorPos)
    };
}

// MARK: - Inspect Request

- (NSDictionary *)inspect_request:(NSString *)code
                        cursorPos:(NSInteger)cursorPos
                       detailLevel:(NSInteger)detailLevel {
    
    // Try to get object at cursor position
    NSString *token = [self extractTokenAtPosition:cursorPos inCode:code];
    
    if (!token) {
        return @{
            @"status": @"ok",
            @"found": @NO,
            @"data": @{}
        };
    }
    
    // Look up class
    Class cls = objc_getClass([token UTF8String]);
    if (cls) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"name"] = [NSString stringWithUTF8String:class_getName(cls)];
        info[@"superclass"] = [NSString stringWithUTF8String:class_getName(class_getSuperclass(cls))];
        
        // Get methods
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (methods) {
            NSMutableArray *methodNames = [NSMutableArray array];
            for (unsigned int i = 0; i < methodCount; i++) {
                SEL sel = method_getName(methods[i]);
                [methodNames addObject:NSStringFromSelector(sel)];
            }
            info[@"methods"] = methodNames;
            free(methods);
        }
        
        return @{
            @"status": @"ok",
            @"found": @YES,
            @"data": @{
                @"text/plain": [info description],
                @"application/json": info
            }
        };
    }
    
    return @{
        @"status": @"ok",
        @"found": @NO,
        @"data": @{}
    };
}

// MARK: - History Request

- (NSDictionary *)history_request:(NSString *)historyAccessType
                         start:(NSInteger)start
                           stop:(NSInteger)stop
                           n:(NSInteger)n
                        pattern:(NSString *)pattern
                             raw:(BOOL)raw
                        session:(NSString *)session {
    // Placeholder - would maintain execution history
    return @{
        @"status": @"ok",
        @"history": @[]
    };
}

// MARK: - Helper Methods

- (NSString *)extractTokenAtPosition:(NSInteger)pos inCode:(NSString *)code {
    if (pos >= code.length) return nil;
    
    NSRange searchRange = NSMakeRange(0, MIN(pos, code.length));
    NSRange range = [code rangeOfString:@" " options:NSBackwardsSearch range:searchRange];
    
    NSUInteger start = (range.location == NSNotFound) ? 0 : range.location + 1;
    return [code substringWithRange:NSMakeRange(start, pos - start)];
}

@end
