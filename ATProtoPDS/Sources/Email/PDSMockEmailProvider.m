#import "PDSMockEmailProvider.h"

@interface PDSMockEmailProvider ()

@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mutableSentEmails;

@end

@implementation PDSMockEmailProvider

- (instancetype)init {
    if (self = [super init]) {
        _mutableSentEmails = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSDictionary *> *)sentEmails {
    return [_mutableSentEmails copy];
}

- (void)clearSentEmails {
    [_mutableSentEmails removeAllObjects];
}

- (nullable NSDictionary *)lastSentEmail {
    return [_mutableSentEmails lastObject];
}

#pragma mark - PDSEmailProvider

- (BOOL)sendEmailTo:(NSString *)to
            subject:(NSString *)subject
               body:(NSString *)body
              error:(NSError **)error {
    NSDictionary *email = @{
        @"to": to,
        @"subject": subject,
        @"body": body,
        @"timestamp": [NSDate date]
    };
    [_mutableSentEmails addObject:email];
    return YES;
}

- (BOOL)sendHtmlEmailTo:(NSString *)to
                subject:(NSString *)subject
               htmlBody:(NSString *)htmlBody
               textBody:(NSString *)textBody
                  error:(NSError **)error {
    NSDictionary *email = @{
        @"to": to,
        @"subject": subject,
        @"htmlBody": htmlBody,
        @"body": textBody,
        @"timestamp": [NSDate date]
    };
    [_mutableSentEmails addObject:email];
    return YES;
}

@end
