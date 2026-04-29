#ifndef OBJC_JUPYTER_WASM_RUNTIME_H
#define OBJC_JUPYTER_WASM_RUNTIME_H

typedef struct objc_class *Class;
typedef struct objc_object *id;
typedef const struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef signed char BOOL;

#ifndef YES
#define YES ((BOOL)1)
#endif

#ifndef NO
#define NO ((BOOL)0)
#endif

Class objc_getClass(const char *name);
SEL sel_registerName(const char *name);
const char *sel_getName(SEL selector);
const char *class_getName(Class cls);
Class objc_allocateClassPair(Class superclass, const char *name, unsigned long extraBytes);
BOOL class_addMethod(Class cls, SEL name, void *implementation, const char *types);
int objc_runtime_smoke_version(void);

#endif
