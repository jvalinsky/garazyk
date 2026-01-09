#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ExploreCache : NSObject

+ (instancetype)sharedCache;

- (nullable NSString *)getDidDocument:(NSString *)did;
- (void)setDidDocument:(NSString *)did value:(NSString *)document;

- (nullable NSString *)getPlcLog:(NSString *)did;
- (void)setPlcLog:(NSString *)did value:(NSString *)log;

- (nullable NSString *)getAccountList;
- (void)setAccountList:(NSString *)accountList;

- (void)clearExpiredEntries;
- (void)clearAll;

@end

NS_ASSUME_NONNULL_END
