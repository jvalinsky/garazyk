#ifndef OBJC_INTERP_PARSER_H
#define OBJC_INTERP_PARSER_H

#include "objc_interp_types.h"

Value parse_expression(struct Parser *p);
Value parse_expression_safe(struct Parser *p);
Value parse_type_and_var_decl(struct Parser *p);
Value parse_statement(struct Parser *p);
Value parse_block(struct Parser *p);

#endif /* OBJC_INTERP_PARSER_H */
