#import "ATProtoLexiconSchema.h"
#import "ATProtoLexiconDef.h"
#import "ATProtoLexiconError.h"

@implementation ATProtoLexiconSchema

+ (nullable instancetype)schemaFromJSONData:(NSData *)data error:(NSError **)error {
    NSError *parseError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];

    if (parseError || ![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Invalid JSON in lexicon file"
                                                context:nil];
        }
        return nil;
    }

    return [self schemaFromJSONObject:json error:error];
}

+ (nullable instancetype)schemaFromJSONObject:(NSDictionary *)json error:(NSError **)error {
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Lexicon must be a JSON object"
                                                context:nil];
        }
        return nil;
    }

    // Validate required fields
    NSNumber *lexiconVersion = json[@"lexicon"];
    NSString *nsid = json[@"id"];

    if (!lexiconVersion || ![lexiconVersion isKindOfClass:[NSNumber class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Missing or invalid 'lexicon' field"
                                                context:nil];
        }
        return nil;
    }

    if (!nsid || ![nsid isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Missing or invalid 'id' field"
                                                context:nil];
        }
        return nil;
    }

    if ([lexiconVersion integerValue] != 1) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:[NSString stringWithFormat:@"Unsupported lexicon version: %@", lexiconVersion]
                                                context:nil];
        }
        return nil;
    }

    // Parse definitions
    NSDictionary *defsJSON = json[@"defs"];
    if (!defsJSON || ![defsJSON isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Missing or invalid 'defs' field"
                                                context:nil];
        }
        return nil;
    }

    NSMutableDictionary *defs = [NSMutableDictionary dictionary];
    for (NSString *defName in defsJSON) {
        NSError *defError = nil;
        ATProtoLexiconDef *def = [ATProtoLexiconDef defFromJSONObject:defsJSON[defName] error:&defError];

        if (defError) {
            if (error) {
                NSString *message = [NSString stringWithFormat:@"Failed to parse definition '%@': %@",
                                    defName, defError.localizedDescription];
                *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                    message:message
                                                    context:nil];
            }
            return nil;
        }

        if (def) {
            defs[defName] = def;
        }
    }

    // Create schema instance
    ATProtoLexiconSchema *schema = [[self alloc] init];
    schema.lexicon = [lexiconVersion integerValue];
    schema.nsid = nsid;
    schema.schemaDescription = json[@"description"];
    schema.defs = defs;

    return schema;
}

- (nullable ATProtoLexiconDef *)mainDefinition {
    return self.defs[@"main"];
}

- (nullable ATProtoLexiconDef *)definitionForName:(NSString *)name {
    return self.defs[name];
}

@end
