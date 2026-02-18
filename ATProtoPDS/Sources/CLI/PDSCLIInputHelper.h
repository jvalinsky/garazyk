#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PDSCLIInputHelper : NSObject

+ (BOOL)isInteractiveTTY;
+ (nullable NSString *)promptForInput:(NSString *)prompt defaultValue:(nullable NSString *)defaultValue;
+ (nullable NSString *)promptForPassword:(NSString *)prompt;
+ (nullable NSString *)promptForPasswordWithConfirmation:(NSString *)prompt
                                            confirmPrompt:(NSString *)confirmPrompt
                                                minLength:(NSUInteger)minLength
                                              maxAttempts:(NSUInteger)maxAttempts;
+ (BOOL)promptForConfirmation:(NSString *)prompt defaultYes:(BOOL)defaultYes;
+ (NSInteger)promptForChoice:(NSString *)prompt choices:(NSArray<NSString *> *)choices defaultIndex:(NSInteger)defaultIndex;

@end

NS_ASSUME_NONNULL_END
