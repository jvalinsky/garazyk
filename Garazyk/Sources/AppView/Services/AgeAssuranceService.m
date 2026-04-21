#import "AgeAssuranceService.h"
#import "Database/PDSQueryDatabase.h"
#import "Email/PDSEmailProvider.h"

@interface AgeAssuranceService ()
@property (nonatomic, strong) id<PDSQueryDatabase> database;
@property (nonatomic, strong, nullable) id<PDSEmailProvider> emailProvider;
@end

@implementation AgeAssuranceService

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database
                   emailProvider:(nullable id<PDSEmailProvider>)emailProvider {
    self = [super init];
    if (self) {
        _database = database;
        _emailProvider = emailProvider;
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
    NSString *tokenId = [NSString stringWithFormat:@"%06u", arc4random_uniform(1000000)];
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
    
    // Send verification email if provider is available
    if (self.emailProvider) {
        NSString *subject = @"Bluesky Age Assurance Verification";
        NSString *body = [NSString stringWithFormat:@"Your verification code is: %@", tokenId];
        [self.emailProvider sendEmailTo:email subject:subject body:body error:nil];
    }
    
    return @{
        @"id": assuranceId,
        @"status": @"pending"
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
        return @{ @"status": @"unknown", @"access": @"none" };
    }
    
    NSDictionary *row = results.firstObject;
    return @{
        @"status": row[@"status"] ?: @"unknown",
        @"access": [row[@"status"] isEqualToString:@"assured"] ? @"full" : @"none"
    };
}

- (BOOL)confirmAgeAssuranceWithToken:(NSString *)token
                               error:(NSError **)error {
    // Find the state associated with this token
    NSString *querySql = @"SELECT * FROM age_assurance_states WHERE token = ? AND status = 'pending'";
    NSArray *results = [self.database executeParameterizedQuery:querySql params:@[token] error:error];
    
    if (!results) {
        return NO;
    }
    
    if (results.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"AgeAssuranceService" 
                                         code:404 
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid or expired token"}];
        }
        return NO;
    }
    
    NSDictionary *row = results.firstObject;
    NSString *assuranceId = row[@"id"];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    
    // Update the state to 'assured'
    NSString *updateSql = @"UPDATE age_assurance_states SET status = 'assured', updated_at = ? WHERE id = ?";
    NSArray *params = @[
        @( (long long)now ),
        assuranceId
    ];
    
    return [self.database executeParameterizedUpdate:updateSql params:params error:error];
}

@end
