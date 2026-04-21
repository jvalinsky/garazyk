#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AgeAssuranceService
 @abstract Service for managing user age assurance (begin flow, config, state).
 */
@interface AgeAssuranceService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

/*!
 @method beginAgeAssurance:email:language:countryCode:regionCode:error:
 @abstract Start an age assurance verification flow for a user.
 */
- (nullable NSDictionary *)beginAgeAssurance:(NSString *)did
                                     email:(NSString *)email
                                  language:(NSString *)language
                               countryCode:(nullable NSString *)countryCode
                                regionCode:(nullable NSString *)regionCode
                                     error:(NSError **)error;

/*!
 @method getAgeAssuranceConfig:
 @abstract Get the current age assurance configuration.
 */
- (nullable NSDictionary *)getAgeAssuranceConfig:(NSError **)error;

/*!
 @method getAgeAssuranceState:countryCode:regionCode:error:
 @abstract Get the current age assurance state for a user.
 */
- (nullable NSDictionary *)getAgeAssuranceState:(NSString *)did
                                    countryCode:(nullable NSString *)countryCode
                                     regionCode:(nullable NSString *)regionCode
                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
