#import <Foundation/Foundation.h>

@class PDSDatabase;
@class MST;
@class Session;
@class BlobStorage;
@class CID;
@class FederationClient;

NS_ASSUME_NONNULL_BEGIN

@interface PDSController : NSObject

- (instancetype)initWithDatabase:(PDSDatabase *)database;
- (void)startServer;
- (void)stopServer;

@property (nonatomic, readonly) PDSDatabase *database;
@property (nonatomic, readonly) BlobStorage *blobStorage;
@property (nonatomic, readonly) FederationClient *federationClient;

- (nullable NSDictionary *)createSessionForIdentifier:(NSString *)identifier
                                             password:(NSString *)password
                                              handle:(NSString *)handle
                                                did:(NSString *)did
                                               error:(NSError **)error;

- (nullable NSDictionary *)createAccountForEmail:(NSString *)email
                                         password:(NSString *)password
                                          handle:(NSString *)handle
                                             did:(nullable NSString *)did
                                            error:(NSError **)error;

- (nullable NSDictionary *)refreshSessionWithRefreshToken:(NSString *)refreshToken
                                                     error:(NSError **)error;

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                      collection:(NSString *)collection
                                           record:(NSDictionary *)record
                                            error:(NSError **)error;

- (BOOL)validateRecord:(NSDictionary *)record
          forCollection:(NSString *)collection
                 error:(NSError **)error;

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                      collection:(NSString *)collection
                                           record:(NSDictionary *)record
                                             rkey:(nullable NSString *)rkey
                                            error:(NSError **)error;

- (nullable NSDictionary *)createRecordForDid:(NSString *)did
                                     collection:(NSString *)collection
                                          record:(NSDictionary *)record
                                           rkey:(nullable NSString *)rkey
                                           error:(NSError **)error;

- (nullable NSDictionary *)putRecordForDid:(NSString *)did
                                  collection:(NSString *)collection
                                       rkey:(NSString *)rkey
                                      record:(NSDictionary *)record
                                       error:(NSError **)error;

- (nullable NSDictionary *)getRecordForDid:(NSString *)did
                                   collection:(NSString *)collection
                                        rkey:(NSString *)rkey
                                       error:(NSError **)error;

- (NSArray<NSDictionary *> *)listRecordsForDid:(NSString *)did
                                     collection:(NSString *)collection
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

- (BOOL)deleteRecordForDid:(NSString *)did
                  collection:(NSString *)collection
                       rkey:(NSString *)rkey
                      error:(NSError **)error;

- (nullable NSDictionary *)applyWrites:(NSArray *)writes
                                  repo:(NSString *)repo
                              validate:(BOOL)validate
                            swapCommit:(nullable NSString *)swapCommit
                                 error:(NSError **)error;

- (nullable NSDictionary *)describeRepo:(NSString *)repo error:(NSError **)error;

- (nullable MST *)getRepoForDid:(NSString *)did;

- (nullable NSData *)getRepoDataForDid:(NSString *)did
                                 error:(NSError **)error;

- (nullable NSString *)getRepoHeadForDid:(NSString *)did
                                    error:(NSError **)error;

- (nullable NSDictionary *)uploadBlob:(NSData *)data
                             mimeType:(NSString *)mimeType
                                  did:(NSString *)did
                               error:(NSError **)error;

- (nullable NSDictionary *)getBlobWithCID:(NSString *)cidString
                                       did:(NSString *)did
                                    error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listBlobsForDID:(NSString *)did
                                                 limit:(NSInteger)limit
                                                cursor:(nullable NSString *)cursor
                                                 error:(NSError **)error;

#pragma mark - Federation-Aware Methods

- (nullable NSDictionary *)federatedGetRecordForDid:(NSString *)did
                                                     collection:(NSString *)collection
                                                          rkey:(NSString *)rkey
                                                         error:(NSError **)error;

- (NSArray<NSDictionary *> *)federatedListRecordsForDid:(NSString *)did
                                              collection:(NSString *)collection
                                                   limit:(NSInteger)limit
                                                  cursor:(nullable NSString *)cursor
                                                   error:(NSError **)error;

- (nullable NSDictionary *)federatedDescribeRepo:(NSString *)did error:(NSError **)error;

- (nullable NSDictionary *)federatedGetRepoDataForDid:(NSString *)did error:(NSError **)error;

- (nullable NSString *)federatedGetRepoHeadForDid:(NSString *)did error:(NSError **)error;

- (nullable NSDictionary *)federatedGetBlobWithCID:(NSString *)cidString
                                                did:(NSString *)did
                                              error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)federatedListBlobsForDID:(NSString *)did
                                                          limit:(NSInteger)limit
                                                         cursor:(nullable NSString *)cursor
                                                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END