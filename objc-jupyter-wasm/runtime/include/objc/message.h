#ifndef OBJC_JUPYTER_WASM_MESSAGE_H
#define OBJC_JUPYTER_WASM_MESSAGE_H

#include "runtime.h"

void *objc_msgSend(void *receiver, SEL selector, ...);

#endif
