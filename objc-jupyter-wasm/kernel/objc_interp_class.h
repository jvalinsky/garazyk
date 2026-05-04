#ifndef OBJC_INTERP_CLASS_H
#define OBJC_INTERP_CLASS_H

#include "objc_interp_types.h"

Value parse_interface(struct Parser *p);
Value parse_implementation(struct Parser *p);
Value parse_protocol(struct Parser *p);

#endif
