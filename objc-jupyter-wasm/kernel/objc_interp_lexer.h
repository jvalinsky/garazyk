/* objc_interp_lexer.h — Lexer function declarations */

#ifndef OBJC_INTERP_LEXER_H
#define OBJC_INTERP_LEXER_H

#include "objc_interp_types.h"

void lexer_init(Lexer *lex, const char *source, unsigned int length,
                unsigned int line_offset);
char lexer_peek(Lexer *lex);
char lexer_next(Lexer *lex);
void lexer_skip_whitespace_and_comments(Lexer *lex);
Token lexer_next_token(Lexer *lex);

#endif /* OBJC_INTERP_LEXER_H */
