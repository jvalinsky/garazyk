//
//  objc_runtime_bridge.c
//  WebAssembly ↔ Objective-C Runtime Bridge (WasmPatch-style)
//
//  Copyright (c) 2026 Jack Valinsky
//

#include <stdio.h>
#include <string.h>
#include <objc/runtime.h>
#include <objc/message.h>

// MARK: - WASM Import Declarations
// These will be imported from JavaScript

extern void wasm_import_objc_log(const char *message);
extern void wasm_import_kernel_result(const char *result_json);

// MARK: - Logging Bridge

void objc_log_bridge(const char *message) {
    wasm_import_objc_log(message);
}

// Override NSLog to capture output
void NSLog_bridge(const char *format, ...) {
    char buffer[4096];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    objc_log_bridge(buffer);
}

// MARK: - Runtime Bridge Functions

void *wasm_objc_getClass(const char *className) {
    return (void *)objc_getClass(className);
}

void *wasm_objc_msgSend(void *obj, const char *selectorName, ...) {
    SEL selector = sel_registerName(selectorName);
    
    // Handle different return types
    Method method = class_getInstanceMethod(object_getClass((id)obj), selector);
    if (!method) {
        return NULL;
    }
    
    // Call the method
    return objc_msgSend((id)obj, selector);
}

const char *wasm_objc_className(void *cls) {
    return class_getName((Class)cls);
}

// MARK: - Kernel Entry Point

int wasm_kernel_init() {
    // Initialize Objective-C runtime
    // (Runtime auto-initializes in modern ObjC)
    return 0;
}

const char *wasm_kernel_info() {
    static char info[] = "{\"protocol_version\":[5,3],\"name\":\"objective-c\"}";
    return info;
}

const char *wasm_execute_code(const char *code) {
    // Placeholder: In production, this would:
    // 1. Write code to temp file
    // 2. Compile with clang.wasm
    // 3. Load WASM module
    // 4. Execute and return result
    
    static char result[4096];
    snprintf(result, sizeof(result), "{\"status\":\"ok\",\"execution_count\":1,\"data\":{\"text/plain\":\"%s\"}}", code);
    return result;
}
