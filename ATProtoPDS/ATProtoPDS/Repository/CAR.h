#import <Foundation/Foundation.h>
#import "../CID.h"
#import "CBOR.h"

NS_ASSUME_NONNULL_BEGIN

@interface CARBlock : NSObject

@property (nonatomic, strong, readonly) CID *cid;
@property (nonatomic, strong, readonly) NSData *data;

+ (instancetype)blockWithCID:(CID *)cid data:(NSData *)data;
- (instancetype)initWithCID:(CID *)cid data:(NSData *)data;

@end

@interface CARReader : NSObject

@property (nonatomic, strong, readonly, nullable) CID *rootCID;
@property (nonatomic, strong, readonly) NSArray<CARBlock *> *blocks;

+ (nullable instancetype)readFromData:(NSData *)data error:(NSError **)error;
+ (nullable instancetype)readFromPath:(NSString *)path error:(NSError **)error;

- (nullable CARBlock *)blockWithCID:(CID *)cid;

@end

@interface CARWriter : NSObject

@property (nonatomic, strong, readonly) CID *rootCID;
@property (nonatomic, strong, readonly) NSMutableArray<CARBlock *> *blocks;

+ (instancetype)writerWithRootCID:(CID *)rootCID;
- (void)addBlock:(CARBlock *)block;
- (NSData *)serialize;
- (BOOL)writeToPath:(NSString *)path error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
