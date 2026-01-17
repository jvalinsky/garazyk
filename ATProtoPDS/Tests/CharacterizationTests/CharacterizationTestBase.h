#import <XCTest/XCTest.h>
#import "Database/PDSDatabase.h"
#import "Database/ActorStore/ActorStore.h"

@interface CharacterizationTestBase : XCTestCase

@property (nonatomic, strong) PDSDatabase *testDatabase;
@property (nonatomic, strong) PDSActorStore *testActorStore;
@property (nonatomic, strong) NSString *testDatabasePath;

- (void)setupTestData;
- (void)cleanupTestData;

@end
