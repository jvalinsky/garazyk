#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabasePool;

@class MST;
@class CID;

@interface PDSRepositoryService : NSObject

@property (nonatomic, weak) PDSDatabasePool *databasePool;

- (instancetype)initWithDatabasePool:(PDSDatabasePool *)databasePool;

#pragma mark - Repo Operations

- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

- (BOOL)updateMSTForDid:(NSString *)did key:(NSString *)key cid:(nullable CID *)cid error:(NSError **)error;

- (nullable NSData *)getRepoRoot:(NSString *)did error:(NSError **)error;

- (nullable NSData *)getRepoContents:(NSString *)did since:(nullable NSData *)sinceCid error:(NSError **)error;

- (BOOL)updateRepo:(NSString *)did commit:(NSData *)commitData error:(NSError **)error;

/*!
 @method getRecordWithProof:collection:rkey:error:
 @abstract Returns a record as CAR bytes with MST proof path.
 @discussion Builds a CAR file containing the record block and the MST nodes
             from root to the record, enabling cryptographic verification.
 @param did The repository DID.
 @param collection The collection NSID.
 @param rkey The record key.
 @param error Error output.
 @return CAR bytes or nil on error.
 */
- (nullable NSData *)getRecordWithProof:(NSString *)did
                             collection:(NSString *)collection
                                   rkey:(NSString *)rkey
                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
