/*
 * libobjc2_smoke.c
 * Minimal libobjc2-compatible smoke module for the first WASM milestone.
 *
 * It is not a full Objective-C runtime. The purpose is to provide a stable
 * runtime-shaped artifact that can be loaded and validated while the real
 * libobjc2 port is brought up behind the same package boundary.
 */

#include "objc/runtime.h"

struct objc_class {
    const char *name;
};

struct objc_selector {
    const char *name;
};

static struct objc_class ns_object_class = { "NSObject" };
static struct objc_class smoke_class = { "ObjCWasmSmoke" };
static struct objc_selector selectors[32];
static unsigned int selector_count = 0u;

static int cstr_equal(const char *left, const char *right) {
    unsigned int i = 0u;
    if (left == 0 || right == 0) {
        return 0;
    }
    while (left[i] != '\0' && right[i] != '\0') {
        if (left[i] != right[i]) {
            return 0;
        }
        i++;
    }
    return left[i] == right[i];
}

Class objc_getClass(const char *name) {
    if (cstr_equal(name, "NSObject")) {
        return &ns_object_class;
    }
    if (cstr_equal(name, "ObjCWasmSmoke")) {
        return &smoke_class;
    }
    return 0;
}

SEL sel_registerName(const char *name) {
    unsigned int i = 0u;
    if (name == 0) {
        return 0;
    }
    while (i < selector_count) {
        if (cstr_equal(selectors[i].name, name)) {
            return &selectors[i];
        }
        i++;
    }
    if (selector_count >= 32u) {
        return 0;
    }
    selectors[selector_count].name = name;
    selector_count++;
    return &selectors[selector_count - 1u];
}

const char *sel_getName(SEL selector) {
    if (selector == 0) {
        return "";
    }
    return selector->name;
}

const char *class_getName(Class cls) {
    if (cls == 0) {
        return "";
    }
    return cls->name;
}

Class objc_allocateClassPair(Class superclass, const char *name, unsigned long extraBytes) {
    (void)superclass;
    (void)extraBytes;
    smoke_class.name = name == 0 ? "ObjCWasmSmoke" : name;
    return &smoke_class;
}

BOOL class_addMethod(Class cls, SEL name, void *implementation, const char *types) {
    (void)cls;
    (void)name;
    (void)implementation;
    (void)types;
    return YES;
}

void *objc_msgSend(void *receiver, SEL selector, ...) {
    (void)selector;
    return receiver;
}

int objc_runtime_smoke_version(void) {
    return 1;
}
