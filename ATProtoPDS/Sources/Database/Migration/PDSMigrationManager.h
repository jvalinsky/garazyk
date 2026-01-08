#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;
@class PDSDatabaseAccount;
@class PDSDatabaseRepo;
@class PDSDatabaseRecord;
@class PDSDatabaseBlock;
@class PDSDatabaseBlob;
@class PDSActorStore;

extern NSString * const PDSMigrationErrorDomain;

typedef NS_ENUM(NSInteger, PDSMigrationError) {
    PDSMigrationErrorSourceNotFound = 1000,
    PDSMigrationErrorDestinationExists,
    PDSMigrationErrorMigrationFailed,
    PDSMigrationErrorCancelled,
};

typedef void (^PDSMigrationProgressBlock)(double progress, NSString *status);
typedef BOOL (^PDSMigrationCancellationBlock)(void);

@interface PDSMigrationManager : NSObject

@property (nonatomic, copy, nullable) PDSMigrationProgressBlock progressBlock;
@property (nonatomic, copy, nullable) PDSMigrationCancellationBlock cancelBlock;

+ (instancetype)sharedManager;

- (BOOL)migrateFromMonolithicDatabase:(NSString *)sourcePath 
                    toSingleTenantDirectory:(NSString *)destinationDirectory
                                  error:(NSError **)error;

- (void)migrateFromMonolithicDatabaseAsync:(NSString *)sourcePath 
                        toSingleTenantDirectory:(NSString *)destinationDirectory
                                completion:(void (^)(NSError * _Nullable error))completion;

- (NSUInteger)estimatedMigrateTimeWithSourcePath:(NSString *)sourcePath;

@end

NS_ASSUME_NONNULL_END
