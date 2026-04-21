#import "AgeAssuranceService.h"

@interface AgeAssuranceService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@end

@implementation AgeAssuranceService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)beginAgeAssurance:(NSString *)did
                                     email:(NSString *)email
                                  language:(NSString *)language
                               countryCode:(nullable NSString *)countryCode
                                regionCode:(nullable NSString *)regionCode
                                     error:(NSError **)error {
    // Basic implementation: Generate a token and insert a record
    NSString *tokenId = [[NSUUID UUID] UUIDString];
    NSString *assuranceId = [[NSUUID UUID] UUIDString];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    NSString *sql = @"INSERT INTO age_assurance_states (id, did, status, email, country_code, region_code, language, token, created_at, updated_at) "
                    @"VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    
    NSArray *params = @[
        assuranceId,
        did,
        @"pending",
        email,
        countryCode ?: [NSNull null],
        regionCode ?: [NSNull null],
        language,
        tokenId,
        @( (long long)now ),
        @( (long long)now )
    ];
    
    BOOL success = [self.database executeParameterizedUpdate:sql params:params error:error];
    if (!success) {
        return nil;
    }
    
    return @{
        @"id": assuranceId,
        @"status": @"pending",
        @"token": tokenId
    };
}

- (nullable NSDictionary *)getAgeAssuranceConfig:(NSError **)error {
    // Return default configuration matching the lexicon
    return @{
        @"regions": @[
            @{
                @"countryCode": @"US",
                @"minAccessAge": @13,
                @"rules": @[
                    @{
                        @"$type": @"app.bsky.ageassurance.defs#configRegionRuleDefault",
                        @"access": @"full"
                    }
                ]
            }
        ]
    };
}

- (nullable NSDictionary *)getAgeAssuranceState:(NSString *)did
                                    countryCode:(nullable NSString *)countryCode
                                     regionCode:(nullable NSString *)regionCode
                                          error:(NSError **)error {
    NSString *sql = @"SELECT * FROM age_assurance_states WHERE did = ? ORDER BY created_at DESC LIMIT 1";
    NSArray *results = [self.database executeParameterizedQuery:sql params:@[did] error:error];
    
    if (!results) {
        return nil;
    }
    
    if (results.count == 0) {
        return @{ @"status": @"unknown" };
    }
    
    return results.firstObject;
}

@end
