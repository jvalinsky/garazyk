#import <XCTest/XCTest.h>
#import "Database/Monitoring/PDSHealthCheck.h"
#import "Database/Service/ServiceDatabases.h"
#import <objc/runtime.h>

static PDSServiceDatabases *gTestServiceDatabases = nil;

@interface PDSServiceDatabases (Testing)
+ (instancetype)test_sharedInstance;
@end

@implementation PDSServiceDatabases (Testing)
+ (instancetype)test_sharedInstance {
    return gTestServiceDatabases;
}
@end

@interface PDSHealthCheckTests : XCTestCase
@property (nonatomic, copy) NSString *tempDir;
@end

@implementation PDSHealthCheckTests

- (void)setUp {
    [super setUp];
    
    // Create temp directory
    NSString *uuid = [[NSUUID UUID] UUIDString];
    self.tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"pds-health-test-%@", uuid]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    // Create test service database instance
    gTestServiceDatabases = [[PDSServiceDatabases alloc] initWithDirectory:self.tempDir
                                                            serviceMaxSize:5
                                                          didCacheMaxSize:5
                                                        sequencerMaxSize:5];
    
    // Swizzle sharedInstance to return our test instance
    [self swizzleSharedInstance];
}

- (void)tearDown {
    // Unswizzle first
    [self swizzleSharedInstance]; // Swizzling again swaps back
    gTestServiceDatabases = nil;
    
    // Cleanup files
    [[NSFileManager defaultManager] removeItemAtPath:self.tempDir error:nil];
    
    [super tearDown];
}

- (void)swizzleSharedInstance {
    Method original = class_getClassMethod([PDSServiceDatabases class], @selector(sharedInstance));
    Method swizzled = class_getClassMethod([PDSServiceDatabases class], @selector(test_sharedInstance));
    method_exchangeImplementations(original, swizzled);
}

- (void)testHealthCheckHealthy {
    PDSHealthCheck *healthCheck = [[PDSHealthCheck alloc] initWithServiceDatabases:gTestServiceDatabases];
    NSDictionary *result = [healthCheck performHealthCheck];
    
    XCTAssertEqualObjects(result[@"status"], @"healthy");
    XCTAssertEqual([result[@"database_integrity"] integerValue], (NSInteger)PDSHealthStatusHealthy);
    XCTAssertEqualObjects(result[@"errors"], @[]);
    XCTAssertEqualObjects(result[@"warnings"], @[]);
}

- (void)testHealthCheckCorruptDatabase {
    // Close the pool to release file locks
    [gTestServiceDatabases closeAll];
    
    // Corrupt the service database file
    NSString *dbPath = [[self.tempDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
    const char *garbage = "INVALID_SQLITE_HEADER_GARBAGE_DATA";
    NSData *data = [NSData dataWithBytes:garbage length:strlen(garbage)];
    [data writeToFile:dbPath atomically:YES];
    
    // Re-initialize databases to pick up the corrupted file
    // Note: We can't just re-init the existing object easily, but we can try to open it via the health check which calls sqlite3_open
    // Actually, PDSServiceDatabases uses a pool. We closed the pool, so next access should try to open a new connection.
    
    PDSHealthCheck *healthCheck = [[PDSHealthCheck alloc] initWithServiceDatabases:gTestServiceDatabases];
    NSDictionary *result = [healthCheck performHealthCheck];
    
    // Should be critical or warning depending on how SQLite fails to open a garbage file
    // Usually "file is not a database" error
    XCTAssertNotEqualObjects(result[@"status"], @"healthy");
    XCTAssertEqual([result[@"database_integrity"] integerValue], (NSInteger)PDSHealthStatusCritical);
    XCTAssertTrue([result[@"errors"] count] > 0);
    if ([result[@"errors"] count] > 0) {
        NSString *errorMsg = result[@"errors"][0];
        NSLog(@"Corruption error: %@", errorMsg);
    }
}

- (void)testHealthCheckMissingDatabase {
    [gTestServiceDatabases closeAll];
    
    // Delete the database file
    NSString *dbPath = [[self.tempDir stringByAppendingPathComponent:@"service"] stringByAppendingPathComponent:@"service.db"];
    [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];
    
    PDSHealthCheck *healthCheck = [[PDSHealthCheck alloc] initWithServiceDatabases:gTestServiceDatabases];
    NSDictionary *result = [healthCheck performHealthCheck];
    
    // If DB is missing, it might try to create it? 
    // PDSDatabase openWithError usually creates it.
    // So this might actually report healthy if it just creates a fresh empty DB.
    // Let's verify that behavior.
    
    XCTAssertEqualObjects(result[@"status"], @"healthy");
}

@end
