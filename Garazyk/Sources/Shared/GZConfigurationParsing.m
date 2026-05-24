// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Shared/GZConfigurationParsing.h"

@implementation GZConfigurationProperty

+ (instancetype)propertyWithTargetKey:(NSString *)targetKey
                             jsonKeys:(NSArray<NSString *> *)jsonKeys
                               envVar:(NSString *)envVar
                                 type:(GZConfigurationPropertyType)type {
    GZConfigurationProperty *prop = [[GZConfigurationProperty alloc] init];
    if (prop) {
        prop->_targetKey = [targetKey copy];
        prop->_jsonKeys = [jsonKeys copy];
        prop->_envVar = [envVar copy];
        prop->_type = type;
    }
    return prop;
}

@end

@interface GZConfigurationParsing ()
@property (nonatomic, copy) NSArray<GZConfigurationProperty *> *properties;
@end

@implementation GZConfigurationParsing

- (instancetype)initWithProperties:(NSArray<GZConfigurationProperty *> *)properties {
    self = [super init];
    if (self) {
        _properties = [properties copy];
    }
    return self;
}

- (void)applyEnvironmentVariables:(NSDictionary<NSString *, NSString *> *)env toTarget:(id)target {
    for (GZConfigurationProperty *prop in self.properties) {
        NSString *envValue = env[prop.envVar];
        if (envValue.length > 0) {
            id parsedValue = [self parseString:envValue forType:prop.type];
            if (parsedValue) {
                [target setValue:parsedValue forKey:prop.targetKey];
            }
        }
    }
}

- (void)applyDictionary:(NSDictionary *)dict toTarget:(id)target {
    for (GZConfigurationProperty *prop in self.properties) {
        id dictValue = nil;
        for (NSString *jsonKey in prop.jsonKeys) {
            dictValue = dict[jsonKey];
            if (dictValue) {
                break;
            }
        }
        if (dictValue) {
            id parsedValue = [self parseObject:dictValue forType:prop.type];
            if (parsedValue) {
                [target setValue:parsedValue forKey:prop.targetKey];
            }
        }
    }
}

- (id)parseString:(NSString *)string forType:(GZConfigurationPropertyType)type {
    switch (type) {
        case GZConfigurationPropertyTypeString:
            return string;
        case GZConfigurationPropertyTypeInteger:
            return @([string integerValue]);
        case GZConfigurationPropertyTypeDouble:
            return @([string doubleValue]);
        case GZConfigurationPropertyTypeBoolean:
            return @([string boolValue]);
        case GZConfigurationPropertyTypeStringArray:
            return [[self class] splitCSV:string];
    }
    return nil;
}

- (id)parseObject:(id)object forType:(GZConfigurationPropertyType)type {
    switch (type) {
        case GZConfigurationPropertyTypeString:
            if ([object isKindOfClass:[NSString class]]) {
                return object;
            } else if ([object respondsToSelector:@selector(stringValue)]) {
                return [object stringValue];
            }
            break;
        case GZConfigurationPropertyTypeInteger:
            if ([object isKindOfClass:[NSNumber class]]) {
                return object;
            } else if ([object isKindOfClass:[NSString class]] && [(NSString *)object length] > 0) {
                NSInteger value = -1;
                NSScanner *scanner = [NSScanner scannerWithString:(NSString *)object];
                scanner.charactersToBeSkipped = nil;
                if ([scanner scanInteger:&value] && scanner.isAtEnd) {
                    return @(value);
                }
            }
            break;
        case GZConfigurationPropertyTypeDouble:
            if ([object respondsToSelector:@selector(doubleValue)]) {
                return @([object doubleValue]);
            }
            break;
        case GZConfigurationPropertyTypeBoolean:
            if ([object respondsToSelector:@selector(boolValue)]) {
                return @([object boolValue]);
            }
            break;
        case GZConfigurationPropertyTypeStringArray:
            if ([object isKindOfClass:[NSArray class]]) {
                return object;
            } else if ([object isKindOfClass:[NSString class]]) {
                return [[self class] splitCSV:(NSString *)object];
            }
            break;
    }
    return nil;
}

+ (NSArray<NSString *> *)splitCSV:(NSString *)value {
    NSMutableArray<NSString *> *items = [NSMutableArray array];
    for (NSString *part in [value componentsSeparatedByString:@","]) {
        NSString *trimmed = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length > 0) {
            [items addObject:trimmed];
        }
    }
    return [items copy];
}

@end
