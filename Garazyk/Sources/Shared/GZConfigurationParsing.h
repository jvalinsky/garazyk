// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GZConfigurationPropertyType) {
    GZConfigurationPropertyTypeString,
    GZConfigurationPropertyTypeInteger,
    GZConfigurationPropertyTypeDouble,
    GZConfigurationPropertyTypeBoolean,
    GZConfigurationPropertyTypeStringArray // Accepts array of strings or CSV string
};

/*!
 @class GZConfigurationProperty
 @brief Defines a schema mapping for a configuration property.
 */
@interface GZConfigurationProperty : NSObject

@property (nonatomic, copy, readonly) NSString *targetKey;
@property (nonatomic, copy, readonly) NSArray<NSString *> *jsonKeys;
@property (nonatomic, copy, readonly) NSString *envVar;
@property (nonatomic, assign, readonly) GZConfigurationPropertyType type;

+ (instancetype)propertyWithTargetKey:(NSString *)targetKey
                             jsonKeys:(NSArray<NSString *> *)jsonKeys
                               envVar:(NSString *)envVar
                                 type:(GZConfigurationPropertyType)type;

@end

/*!
 @class GZConfigurationParsing
 @brief Utility to parse configurations from dictionaries and environment variables based on a schema.
 */
@interface GZConfigurationParsing : NSObject

- (instancetype)initWithProperties:(NSArray<GZConfigurationProperty *> *)properties;

/*!
 @brief Applies environment variables matching the schema to the target object using KVC.
 */
- (void)applyEnvironmentVariables:(NSDictionary<NSString *, NSString *> *)env toTarget:(id)target;

/*!
 @brief Applies dictionary values matching the schema to the target object using KVC.
 */
- (void)applyDictionary:(NSDictionary *)dict toTarget:(id)target;

@end

NS_ASSUME_NONNULL_END
