#import "ATProtoLexiconDef.h"
#import "ATProtoLexiconConstraints.h"
#import "ATProtoLexiconError.h"

@implementation ATProtoLexiconDef

+ (nullable instancetype)defFromJSONObject:(NSDictionary *)json error:(NSError **)error {
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Definition must be a JSON object"
                                                context:nil];
        }
        return nil;
    }

    NSString *typeString = json[@"type"];
    if (!typeString || ![typeString isKindOfClass:[NSString class]]) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:@"Definition missing 'type' field"
                                                context:nil];
        }
        return nil;
    }

    ATProtoLexiconDefType type = [self typeFromString:typeString];
    if (type == -1) {
        if (error) {
            *error = [ATProtoLexiconError errorWithCode:ATProtoLexiconErrorInvalidSchema
                                                message:[NSString stringWithFormat:@"Unknown type: %@", typeString]
                                                context:nil];
        }
        return nil;
    }

    ATProtoLexiconDef *def = [[self alloc] init];
    def.type = type;
    def.lexiconDescription = json[@"description"];

    // Parse type-specific constraints
    id constraints = [self parseConstraintsForType:type fromJSON:json error:error];
    if (error && *error) {
        return nil;
    }
    def.constraints = constraints;

    return def;
}

+ (nullable id)parseConstraintsForType:(ATProtoLexiconDefType)type
                              fromJSON:(NSDictionary *)json
                                 error:(NSError **)error {
    switch (type) {
        case ATProtoLexiconDefTypeString:
            return [self parseStringConstraints:json error:error];

        case ATProtoLexiconDefTypeInteger:
            return [self parseIntegerConstraints:json error:error];

        case ATProtoLexiconDefTypeBoolean:
            return [self parseBooleanConstraints:json error:error];

        case ATProtoLexiconDefTypeBytes:
            return [self parseBytesConstraints:json error:error];

        case ATProtoLexiconDefTypeArray:
            return [self parseArrayConstraints:json error:error];

        case ATProtoLexiconDefTypeRecord:
            if (json[@"record"]) {
                return [self parseObjectConstraints:json[@"record"] error:error];
            }
            return [self parseObjectConstraints:json error:error];

        case ATProtoLexiconDefTypeObject:
        case ATProtoLexiconDefTypeParams:
            return [self parseObjectConstraints:json error:error];

        case ATProtoLexiconDefTypeBlob:
            return [self parseBlobConstraints:json error:error];

        case ATProtoLexiconDefTypeUnion:
            return [self parseUnionConstraints:json error:error];

        case ATProtoLexiconDefTypeRef:
            return [self parseRefConstraints:json error:error];

        case ATProtoLexiconDefTypeToken:
        case ATProtoLexiconDefTypeUnknown:
        case ATProtoLexiconDefTypeQuery:
        case ATProtoLexiconDefTypeProcedure:
        case ATProtoLexiconDefTypeSubscription:
        case ATProtoLexiconDefTypeCIDLink:
        case ATProtoLexiconDefTypePermissionSet:
            // These types don't have additional constraints
            return nil;
    }

    return nil;
}

#pragma mark - Constraint Parsing

+ (ATProtoLexiconStringConstraints *)parseStringConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconStringConstraints *constraints = [[ATProtoLexiconStringConstraints alloc] init];

    constraints.format = json[@"format"];
    constraints.maxLength = json[@"maxLength"];
    constraints.minLength = json[@"minLength"];
    constraints.maxGraphemes = json[@"maxGraphemes"];
    constraints.minGraphemes = json[@"minGraphemes"];
    constraints.constValue = json[@"const"];
    constraints.defaultValue = json[@"default"];

    if (json[@"enum"]) {
        constraints.enumValues = json[@"enum"];
    }
    if (json[@"knownValues"]) {
        constraints.knownValues = json[@"knownValues"];
    }

    return constraints;
}

+ (ATProtoLexiconIntegerConstraints *)parseIntegerConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconIntegerConstraints *constraints = [[ATProtoLexiconIntegerConstraints alloc] init];

    constraints.minimum = json[@"minimum"];
    constraints.maximum = json[@"maximum"];
    constraints.constValue = json[@"const"];
    constraints.defaultValue = json[@"default"];

    if (json[@"enum"]) {
        constraints.enumValues = json[@"enum"];
    }

    return constraints;
}

+ (ATProtoLexiconBooleanConstraints *)parseBooleanConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconBooleanConstraints *constraints = [[ATProtoLexiconBooleanConstraints alloc] init];

    constraints.constValue = json[@"const"];
    constraints.defaultValue = json[@"default"];

    return constraints;
}

+ (ATProtoLexiconBytesConstraints *)parseBytesConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconBytesConstraints *constraints = [[ATProtoLexiconBytesConstraints alloc] init];

    constraints.minLength = json[@"minLength"];
    constraints.maxLength = json[@"maxLength"];

    return constraints;
}

+ (ATProtoLexiconArrayConstraints *)parseArrayConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconArrayConstraints *constraints = [[ATProtoLexiconArrayConstraints alloc] init];

    constraints.minLength = json[@"minLength"];
    constraints.maxLength = json[@"maxLength"];

    // Parse items definition
    if (json[@"items"]) {
        constraints.items = [self defFromJSONObject:json[@"items"] error:error];
        if (error && *error) {
            return nil;
        }
    }

    return constraints;
}

+ (ATProtoLexiconObjectConstraints *)parseObjectConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconObjectConstraints *constraints = [[ATProtoLexiconObjectConstraints alloc] init];

    constraints.required = json[@"required"];
    constraints.nullable = json[@"nullable"];

    // Parse properties
    NSDictionary *props = json[@"properties"];
    if (props && [props isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *parsedProps = [NSMutableDictionary dictionary];
        for (NSString *key in props) {
            ATProtoLexiconDef *propDef = [self defFromJSONObject:props[key] error:error];
            if (error && *error) {
                return nil;
            }
            if (propDef) {
                parsedProps[key] = propDef;
            }
        }
        constraints.properties = parsedProps;
    }

    return constraints;
}

+ (ATProtoLexiconBlobConstraints *)parseBlobConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconBlobConstraints *constraints = [[ATProtoLexiconBlobConstraints alloc] init];

    constraints.accept = json[@"accept"];
    constraints.maxSize = json[@"maxSize"];

    return constraints;
}

+ (ATProtoLexiconUnionConstraints *)parseUnionConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconUnionConstraints *constraints = [[ATProtoLexiconUnionConstraints alloc] init];

    constraints.refs = json[@"refs"];
    constraints.closed = [json[@"closed"] boolValue]; // Defaults to NO if absent

    return constraints;
}

+ (ATProtoLexiconRefConstraints *)parseRefConstraints:(NSDictionary *)json error:(NSError **)error {
    ATProtoLexiconRefConstraints *constraints = [[ATProtoLexiconRefConstraints alloc] init];

    constraints.ref = json[@"ref"];

    return constraints;
}

#pragma mark - Type Conversion

+ (ATProtoLexiconDefType)typeFromString:(NSString *)typeString {
    static NSDictionary *typeMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        typeMap = @{
            @"record": @(ATProtoLexiconDefTypeRecord),
            @"query": @(ATProtoLexiconDefTypeQuery),
            @"procedure": @(ATProtoLexiconDefTypeProcedure),
            @"subscription": @(ATProtoLexiconDefTypeSubscription),
            @"object": @(ATProtoLexiconDefTypeObject),
            @"array": @(ATProtoLexiconDefTypeArray),
            @"string": @(ATProtoLexiconDefTypeString),
            @"integer": @(ATProtoLexiconDefTypeInteger),
            @"boolean": @(ATProtoLexiconDefTypeBoolean),
            @"bytes": @(ATProtoLexiconDefTypeBytes),
            @"blob": @(ATProtoLexiconDefTypeBlob),
            @"union": @(ATProtoLexiconDefTypeUnion),
            @"ref": @(ATProtoLexiconDefTypeRef),
            @"token": @(ATProtoLexiconDefTypeToken),
            @"unknown": @(ATProtoLexiconDefTypeUnknown),
            @"params": @(ATProtoLexiconDefTypeParams),
            @"cid-link": @(ATProtoLexiconDefTypeCIDLink),
            @"permission-set": @(ATProtoLexiconDefTypePermissionSet),
        };
    });

    NSNumber *typeNum = typeMap[typeString];
    return typeNum ? [typeNum integerValue] : -1;
}

+ (NSString *)stringFromType:(ATProtoLexiconDefType)type {
    static NSDictionary *stringMap = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stringMap = @{
            @(ATProtoLexiconDefTypeRecord): @"record",
            @(ATProtoLexiconDefTypeQuery): @"query",
            @(ATProtoLexiconDefTypeProcedure): @"procedure",
            @(ATProtoLexiconDefTypeSubscription): @"subscription",
            @(ATProtoLexiconDefTypeObject): @"object",
            @(ATProtoLexiconDefTypeArray): @"array",
            @(ATProtoLexiconDefTypeString): @"string",
            @(ATProtoLexiconDefTypeInteger): @"integer",
            @(ATProtoLexiconDefTypeBoolean): @"boolean",
            @(ATProtoLexiconDefTypeBytes): @"bytes",
            @(ATProtoLexiconDefTypeBlob): @"blob",
            @(ATProtoLexiconDefTypeUnion): @"union",
            @(ATProtoLexiconDefTypeRef): @"ref",
            @(ATProtoLexiconDefTypeToken): @"token",
            @(ATProtoLexiconDefTypeUnknown): @"unknown",
            @(ATProtoLexiconDefTypeParams): @"params",
            @(ATProtoLexiconDefTypeCIDLink): @"cid-link",
            @(ATProtoLexiconDefTypePermissionSet): @"permission-set",
        };
    });

    return stringMap[@(type)] ?: @"unknown";
}

@end
