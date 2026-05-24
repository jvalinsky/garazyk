// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "CLI/GZCommandLineOptions.h"

@implementation GZCommandLineOption

+ (instancetype)optionWithLongName:(NSString *)longName
                         shortName:(nullable NSString *)shortName
                              type:(GZCommandLineOptionType)type
                        isRequired:(BOOL)isRequired {
    GZCommandLineOption *opt = [[GZCommandLineOption alloc] init];
    opt->_longName = [longName copy];
    opt->_shortName = [shortName copy];
    opt->_type = type;
    opt->_isRequired = isRequired;
    return opt;
}

@end

@interface GZCommandLineOptions ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<GZCommandLineOption *> *> *schemas;
@end

@implementation GZCommandLineOptions

- (instancetype)init {
    self = [super init];
    if (self) {
        _schemas = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)registerOptions:(NSArray<GZCommandLineOption *> *)options forCommand:(NSString *)command {
    self.schemas[command] = [options copy];
}

- (NSDictionary<NSString *, id> *)parseArguments:(NSArray<NSString *> *)arguments
                                      forCommand:(NSString *)command
                                           error:(NSError **)error {
    NSArray<GZCommandLineOption *> *schema = self.schemas[command];
    if (!schema) {
        if (error) {
            *error = [NSError errorWithDomain:@"GZCommandLineOptionsErrorDomain"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown command schema: %@", command]}];
        }
        return nil;
    }

    NSMutableDictionary<NSString *, GZCommandLineOption *> *optionMap = [NSMutableDictionary dictionary];
    for (GZCommandLineOption *opt in schema) {
        NSString *longKey = [NSString stringWithFormat:@"--%@", opt.longName];
        optionMap[longKey] = opt;
        if (opt.shortName) {
            NSString *shortKey = [NSString stringWithFormat:@"-%@", opt.shortName];
            optionMap[shortKey] = opt;
        }
    }

    NSMutableDictionary<NSString *, id> *results = [NSMutableDictionary dictionary];

    for (GZCommandLineOption *opt in schema) {
        if (opt.type == GZCommandLineOptionTypeRepeatableString) {
            results[opt.longName] = [NSMutableArray array];
        } else if (opt.type == GZCommandLineOptionTypeBoolean) {
            results[opt.longName] = @(NO);
        }
    }

    for (NSUInteger i = 0; i < arguments.count; i++) {
        NSString *arg = arguments[i];
        
        GZCommandLineOption *matchedOpt = optionMap[arg];
        if (matchedOpt) {
            if (matchedOpt.type == GZCommandLineOptionTypeBoolean) {
                results[matchedOpt.longName] = @(YES);
            } else {
                if (i + 1 >= arguments.count) {
                    if (error) {
                        *error = [NSError errorWithDomain:@"GZCommandLineOptionsErrorDomain"
                                                     code:2
                                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing value for %@", arg]}];
                    }
                    return nil;
                }
                NSString *val = arguments[++i];
                if (matchedOpt.type == GZCommandLineOptionTypeString) {
                    results[matchedOpt.longName] = val;
                } else if (matchedOpt.type == GZCommandLineOptionTypeRepeatableString) {
                    NSMutableArray *arr = results[matchedOpt.longName];
                    [arr addObject:val];
                }
            }
        } else if ([arg hasPrefix:@"-"]) {
            if (error) {
                *error = [NSError errorWithDomain:@"GZCommandLineOptionsErrorDomain"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unknown option: %@", arg]}];
            }
            return nil;
        } else {
            if (error) {
                *error = [NSError errorWithDomain:@"GZCommandLineOptionsErrorDomain"
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unexpected argument: %@", arg]}];
            }
            return nil;
        }
    }

    for (GZCommandLineOption *opt in schema) {
        if (opt.isRequired) {
            if (opt.type == GZCommandLineOptionTypeString && !results[opt.longName]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GZCommandLineOptionsErrorDomain"
                                                 code:5
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing required option: --%@", opt.longName]}];
                }
                return nil;
            } else if (opt.type == GZCommandLineOptionTypeRepeatableString && [(NSArray *)results[opt.longName] count] == 0) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GZCommandLineOptionsErrorDomain"
                                                 code:5
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Missing required option: --%@", opt.longName]}];
                }
                return nil;
            }
        }
    }

    return [results copy];
}

@end
