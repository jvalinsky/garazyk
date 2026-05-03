#ifndef OBJC_INTERP_AST_H
#define OBJC_INTERP_AST_H

#include "objc_interp_types.h"

/* AST arena management */
AstNode *ast_alloc(void);
AstNode *ast_make_if(AstNode *condition, AstNode *then_branch, AstNode *else_branch);
AstNode *ast_make_while(AstNode *condition, AstNode *body);
AstNode *ast_make_do_while(AstNode *body, AstNode *condition);
AstNode *ast_make_for(AstNode *init, AstNode *condition, AstNode *increment, AstNode *body);
AstNode *ast_make_block(void);
int ast_block_add(AstNode *block, AstNode *child);
AstNode *ast_make_source(AstNodeType type, unsigned int start, unsigned int len);
AstNode *ast_make_noop(void);

/* Expression helpers shared with the main parser */
Value parse_bitwise_and(struct Parser *p);

/* AST construction from parser */
AstNode *parse_block_ast(struct Parser *p);
AstNode *parse_statement_ast(struct Parser *p);

/* AST evaluation */
Value eval_source_range(unsigned int start, unsigned int len, const char *source,
                        unsigned int line_offset);
Value eval_ast(AstNode *node, const char *source);

/* Truthiness check */
int is_truthy(Value v);

#endif
