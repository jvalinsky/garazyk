#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MST;
@class MSTNode;
@class CID;
@class PDSDatabase;

@interface MSTPersistence : NSObject

+ (instancetype)shared;

- (BOOL)saveMST:(MST *)mst forDid:(NSString *)did error:(NSError **)error;
- (nullable MST *)loadMSTForDid:(NSString *)did error:(NSError **)error;

- (BOOL)saveMSTNode:(MSTNode *)node withCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error;
- (nullable MSTNode *)loadMSTNodeWithCID:(CID *)cid forDid:(NSString *)did error:(NSError **)error;

- (BOOL)deleteMSTForDid:(NSString *)did error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
