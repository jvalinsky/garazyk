#import <XCTest/XCTest.h>
#import "ATProtoPDS/ATProtoPDS/Repository/MST.h"
#import "ATProtoPDS/ATProtoPDS/Core/CID.h"

NS_ASSUME_NONNULL_BEGIN

@interface MSTTests : XCTestCase

@property (nonatomic, strong) MST *emptyMST;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CID *> *testData;
@property (nonatomic, strong) NSMutableArray<NSString *> *testKeys;

@end

NS_ASSUME_NONNULL_END
