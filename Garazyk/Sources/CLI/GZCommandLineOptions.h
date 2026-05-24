// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GZCommandLineOptionType) {
    GZCommandLineOptionTypeBoolean,
    GZCommandLineOptionTypeString,
    GZCommandLineOptionTypeRepeatableString
};

@interface GZCommandLineOption : NSObject

@property (nonatomic, copy, readonly) NSString *longName;
@property (nonatomic, copy, readonly, nullable) NSString *shortName;
@property (nonatomic, assign, readonly) GZCommandLineOptionType type;
@property (nonatomic, assign, readonly) BOOL isRequired;

+ (instancetype)optionWithLongName:(NSString *)longName
                         shortName:(nullable NSString *)shortName
                              type:(GZCommandLineOptionType)type
                        isRequired:(BOOL)isRequired;

@end

@interface GZCommandLineOptions : NSObject

- (void)registerOptions:(NSArray<GZCommandLineOption *> *)options forCommand:(NSString *)command;

// Returns parsed values where key is the `longName`.
// Booleans return @(YES) or @(NO).
// Strings return NSString.
// RepeatableStrings return NSArray<NSString *>.
- (nullable NSDictionary<NSString *, id> *)parseArguments:(NSArray<NSString *> *)arguments
                                               forCommand:(NSString *)command
                                                    error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
