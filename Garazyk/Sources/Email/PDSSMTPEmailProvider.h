#import <Foundation/Foundation.h>
#import "PDSEmailProvider.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * @class PDSSMTPEmailProvider
 * @abstract An implementation of PDSEmailProvider that sends emails via SMTP.
 * @discussion This currently serves as a skeleton for future expansion into 
 * a full SMTP client or a wrapper around a system SMTP utility.
 */
@interface PDSSMTPEmailProvider : NSObject <PDSEmailProvider>

/** The SMTP server hostname. */
@property (nonatomic, copy) NSString *smtpHost;

/** The SMTP server port (e.g., 587 or 465). */
@property (nonatomic, assign) NSUInteger smtpPort;

/** The username for authentication. */
@property (nonatomic, copy, nullable) NSString *username;

/** The password for authentication. */
@property (nonatomic, copy, nullable) NSString *password;

/** Whether to use SSL/TLS. */
@property (nonatomic, assign) BOOL useTLS;

/**
 * Initializes the SMTP provider with server details.
 */
- (instancetype)initWithHost:(NSString *)host
                        port:(NSUInteger)port
                    username:(nullable NSString *)username
                    password:(nullable NSString *)password
                      useTLS:(BOOL)useTLS;

@end

NS_ASSUME_NONNULL_END
