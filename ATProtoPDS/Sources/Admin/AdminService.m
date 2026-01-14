#import "AdminService.h"
#import "App/PDSController.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"
#import <CommonCrypto/CommonHMAC.h>

NSString * const AdminServiceErrorDomain = @"com.atproto.pds.admin";

static NSDateFormatter * adminIso8601Formatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
        [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    });
    return formatter;
}

@interface AdminService ()

@property (nonatomic, strong) PDSDatabase *database;

@end

@implementation AdminService

- (instancetype)initWithDatabase:(PDSDatabase *)database {
    self = [super init];
    if (self) {
        _database = database;
    }
    return self;
}

- (nullable NSDictionary *)getAccountInfoForDid:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"did"] = account.did;
    result[@"handle"] = account.handle;
    
    if (account.email) {
        result[@"email"] = account.email;
    }
    
    result[@"createdAt"] = [adminIso8601Formatter() stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.createdAt]];
    result[@"updatedAt"] = [adminIso8601Formatter() stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]];
    
    return result;
}

- (nullable NSArray<NSDictionary *> *)getAccountInfosForDids:(NSArray<NSString *> *)dids error:(NSError **)error {
    NSMutableArray *results = [NSMutableArray array];
    
    for (NSString *did in dids) {
        NSDictionary *accountInfo = [self getAccountInfoForDid:did error:error];
        if (accountInfo) {
            [results addObject:accountInfo];
        }
    }
    
    return results;
}

- (nullable NSDictionary *)updateAccountHandle:(NSString *)did newHandle:(NSString *)handle error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    account.handle = handle;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    BOOL success = [self.database updateAccount:account error:error];
    
    if (!success) {
        return nil;
    }
    if (success) {
        PDS_LOG_ADMIN_INFO(@"Updated handle for account %@ to %@", did, handle);
    }
    
    return @{
        @"did": did,
        @"handle": handle,
        @"updatedAt": [adminIso8601Formatter() stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]]
    };
}

- (nullable NSDictionary *)updateAccountEmail:(NSString *)did email:(NSString *)email error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    account.email = email;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    BOOL success = [self.database updateAccount:account error:error];
    
    if (!success) {
        return nil;
    }
    if (success) {
        PDS_LOG_ADMIN_INFO(@"Updated email for account %@", did);
    }
    
    return @{
        @"did": did,
        @"email": email,
        @"updatedAt": [adminIso8601Formatter() stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]]
    };
}

- (nullable NSDictionary *)updateAccountPassword:(NSString *)did newPassword:(NSString *)password error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    NSData *salt = [self generateSalt];
    NSData *hash = [self hashPassword:password withSalt:salt];
    
    account.passwordHash = hash;
    account.passwordSalt = salt;
    account.updatedAt = [[NSDate date] timeIntervalSince1970];
    
    BOOL success = [self.database updateAccount:account error:error];
    
    if (!success) {
        return nil;
    }
    if (success) {
        PDS_LOG_ADMIN_INFO(@"Updated password for account %@", did);
    }
    
    return @{
        @"did": did,
        @"updatedAt": [adminIso8601Formatter() stringFromDate:[NSDate dateWithTimeIntervalSince1970:account.updatedAt]]
    };
}

- (nullable NSDictionary *)enableAccountInvites:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    NSError *updateError = nil;
    // FIXED: Use parameterized query to prevent SQL injection
    NSString *sql = @"UPDATE accounts SET invite_enabled = 1, updated_at = ? WHERE did = ?";
    NSString *updatedAt = [adminIso8601Formatter() stringFromDate:[NSDate date]];
    BOOL success = [self.database executeParameterizedUpdate:sql params:@[updatedAt, did] error:&updateError];
    
    if (!success) {
        if (error) *error = updateError;
        return nil;
    }
    if (success) {
        PDS_LOG_ADMIN_INFO(@"Enabled invites for account %@", did);
    }
    
    return @{
        @"did": did,
        @"invitesEnabled": @YES,
        @"updatedAt": [adminIso8601Formatter() stringFromDate:[NSDate date]]
    };
}

- (nullable NSDictionary *)disableAccountInvites:(NSString *)did error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    NSError *updateError = nil;
    // FIXED: Use parameterized query to prevent SQL injection
    NSString *sql = @"UPDATE accounts SET invite_enabled = 0, updated_at = ? WHERE did = ?";
    NSString *updatedAt = [adminIso8601Formatter() stringFromDate:[NSDate date]];
    BOOL success = [self.database executeParameterizedUpdate:sql params:@[updatedAt, did] error:&updateError];
    
    if (!success) {
        if (error) *error = updateError;
        return nil;
    }
    if (success) {
        PDS_LOG_ADMIN_INFO(@"Disabled invites for account %@", did);
    }
    
    return @{
        @"did": did,
        @"invitesEnabled": @NO,
        @"updatedAt": [adminIso8601Formatter() stringFromDate:[NSDate date]]
    };
}

- (nullable NSArray<NSDictionary *> *)getInviteCodesWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error {
    NSMutableArray *results = [NSMutableArray array];
    
    NSString *sql = @"SELECT code, account_did, created_at, uses, max_uses FROM invite_codes";
    
    if (cursor) {
        sql = [sql stringByAppendingFormat:@" WHERE created_at < '%@'", cursor];
    }
    
    sql = [sql stringByAppendingFormat:@" ORDER BY created_at DESC LIMIT %ld", (long)limit];
    
    NSArray *rows = [self.database executeQuery:sql error:error];
    
    for (NSDictionary *row in rows) {
        [results addObject:@{
            @"code": row[@"code"] ?: @"",
            @"accountDid": row[@"account_did"] ?: @"",
            @"createdAt": row[@"created_at"] ?: @"",
            @"uses": row[@"uses"] ?: @0,
            @"maxUses": row[@"max_uses"] ?: @0
        }];
    }
    
    return results;
}

- (nullable NSDictionary *)disableInviteCodesForAccount:(NSString *)did error:(NSError **)error {
    NSError *updateError = nil;
    // FIXED: Use parameterized query to prevent SQL injection
    NSString *sql = @"UPDATE invite_codes SET disabled = 1 WHERE account_did = ?";
    BOOL success = [self.database executeParameterizedUpdate:sql params:@[did] error:&updateError];
    
    if (!success) {
        if (error) *error = updateError;
        return nil;
    }
    if (success) {
        PDS_LOG_ADMIN_INFO(@"Disabled invite codes for account %@", did);
    }
    
    return @{
        @"accountDid": did,
        @"disabled": @YES
    };
}

- (nullable NSDictionary *)getSubjectStatus:(NSString *)subject error:(NSError **)error {
    // FIXED: Use parameterized query to prevent SQL injection
    NSString *sql = @"SELECT * FROM admin_takedowns WHERE subjectId = ? AND applied = 1 ORDER BY createdAt DESC LIMIT 1";
    NSArray *rows = [self.database executeParameterizedQuery:sql params:@[subject] error:error];
    
    if (rows.count == 0) {
        return @{
            @"subject": subject,
            @"takedown": @NO
        };
    }
    
    NSDictionary *takedown = rows.firstObject;
    
    return @{
        @"subject": subject,
        @"takedown": @YES,
        @"ref": takedown[@"takedownRef"] ?: [NSNull null],
        @"reason": takedown[@"reason"] ?: [NSNull null],
        @"createdAt": takedown[@"createdAt"] ?: [NSNull null]
    };
}

- (nullable NSDictionary *)updateSubjectStatus:(NSString *)subject takedown:(BOOL)takedown reason:(nullable NSString *)reason error:(NSError **)error {
    NSString *takedownRef = [[NSUUID UUID] UUIDString];
    NSString *createdAt = [adminIso8601Formatter() stringFromDate:[NSDate date]];
    
    if (takedown) {
        NSString *sql = [NSString stringWithFormat:
                         @"INSERT INTO admin_takedowns (id, subjectType, subjectId, reason, takedownRef, applied, createdBy, createdAt) "
                         @"VALUES ('%@', 'account', '%@', '%@', '%@', 1, 'admin', '%@')",
                         takedownRef, subject, reason ?: @"", takedownRef, createdAt];
        
        BOOL success = [self.database executeRawSQL:sql error:error];
        
        if (!success) {
            return nil;
        }
        if (takedown) {
            PDS_LOG_ADMIN_INFO(@"Applied takedown for subject %@: %@", subject, reason);
        } else {
            PDS_LOG_ADMIN_INFO(@"Removed takedown for subject %@", subject);
        }
    } else {
        NSString *sql = [NSString stringWithFormat:
                         @"INSERT INTO admin_takedowns (id, subjectType, subjectId, reason, takedownRef, applied, createdBy, createdAt) "
                         @"VALUES ('%@', 'account', '%@', '%@', '%@', 0, 'admin', '%@')",
                         takedownRef, subject, reason ?: @"", takedownRef, createdAt];
        
        BOOL success = [self.database executeRawSQL:sql error:error];
        
        if (!success) {
            return nil;
        }
        if (takedown) {
            PDS_LOG_ADMIN_INFO(@"Applied takedown for subject %@: %@", subject, reason);
        } else {
            PDS_LOG_ADMIN_INFO(@"Removed takedown for subject %@", subject);
        }
    }
    
    return @{
        @"subject": subject,
        @"takedown": @(takedown),
        @"ref": takedownRef,
        @"reason": reason ?: [NSNull null],
        @"createdAt": createdAt
    };
}

- (nullable NSDictionary *)sendEmailToAccount:(NSString *)did subject:(NSString *)subject message:(NSString *)message error:(NSError **)error {
    PDSDatabaseAccount *account = [self.database getAccountByDid:did error:error];
    
    if (!account) {
        return nil;
    }
    
    if (!account.email) {
        if (error) {
            *error = [NSError errorWithDomain:AdminServiceErrorDomain
                                         code:AdminServiceErrorInvalidRequest
                                     userInfo:@{NSLocalizedDescriptionKey: @"Account has no email address"}];
        }
        return nil;
    }
    
    // In a real implementation, this would send an actual email
    PDS_LOG_ADMIN_INFO(@"Sending email to %@ (did: %@): %@", account.email, did, subject);
    
    return @{
        @"recipientDid": did,
        @"recipientEmail": account.email,
        @"subject": subject,
        @"sentAt": [adminIso8601Formatter() stringFromDate:[NSDate date]]
    };
}

- (NSData *)generateSalt {
    unsigned char salt[16];
    arc4random_buf(salt, sizeof(salt));
    return [NSData dataWithBytes:salt length:sizeof(salt)];
}

- (NSData *)hashPassword:(NSString *)password withSalt:(NSData *)salt {
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData *keyData = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    
    CCHmac(kCCHmacAlgSHA256, salt.bytes, salt.length, passwordData.bytes, passwordData.length, keyData.mutableBytes);
    
    return keyData;
}

@end
