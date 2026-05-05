#ifndef OBJC_INTERP_MESSAGES_H
#define OBJC_INTERP_MESSAGES_H

#include "objc_interp_types.h"

Value parse_message_send(struct Parser *p);

/* Programmatic message send (for internal use by AST evaluator) */
Value execute_message_send_internal(struct Parser *p, Value target, const char *sel_name,
                                    const Value *args, unsigned int arg_count);

#endif /* OBJC_INTERP_MESSAGES_H */
