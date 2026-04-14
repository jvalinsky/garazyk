#import "PDSDatabaseIntegrationTestUtilities.h"
#import "PDSSchemaValidationTestFixture.h"
#import "Database/PDSDatabase.h"
#import "Database/Schema.h"
#import "Database/Pool/DatabasePool.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Migration/PDSMigrationManager.h"
#import <sqlite3.h>
#import <CommonCrypto/CommonCrypto.h>

NSString * const PDSDatabaseIntegrationTestErrorDomain = @"com.atproto.pds.integrationtest";

@implementation PDSDatabaseIntegrationTestUtilities

+ (nullable PDSDatabase *)createInMemoryDatabaseWithError:(NSError **)error {
    PDSDatabase *database = [PDSDatabase databaseAtURL:[NSURL fileURLWithPath:@":memory:"]];
    if (![database openWithError:error]) {
        return nil;
    }
    return database;
}

+ (BOOL)verifySchemaInDatabase:(PDSDatabase *)database error:(NSError **)error {
    PDSSchemaValidationTestFixture *fixture = [[PDSSchemaValidationTestFixture alloc] initWithTestName:@"SchemaValidation"];
    fixture.database = database;
    return [fixture validateSchemaWithError:error];
}

+ (PDSDatabaseAccount *)createTestAccountWithDID:(NSString *)did handle:(NSString *)handle {
    PDSDatabaseAccount *account = [[PDSDatabaseAccount alloc] init];
    account.did = did;
    account.handle = handle;
    account.email = [NSString stringWithFormat:@"%@@example.com", handle];
    account.createdAt = [[NSDate date] timeIntervalSince1970];
    account.updatedAt = account.createdAt;
    // Generate realistic dummy hash data using a simple hash of the handle
    NSString *hashInput = [NSString stringWithFormat:@"password:%@", handle];
    NSData *inputData = [hashInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t hashBytes[32];
    CC_SHA256(inputData.bytes, (CC_LONG)inputData.length, hashBytes);
    account.passwordHash = [NSData dataWithBytes:hashBytes length:32];

    // Generate salt using a hash of DID + handle
    NSString *saltInput = [NSString stringWithFormat:@"salt:%@:%@", did, handle];
    NSData *saltInputData = [saltInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t saltBytes[16];
    CC_MD5(saltInputData.bytes, (CC_LONG)saltInputData.length, saltBytes);
    account.passwordSalt = [NSData dataWithBytes:saltBytes length:16];
    return account;
}

+ (PDSDatabaseRepo *)createTestRepoWithOwnerDID:(NSString *)ownerDid {
    PDSDatabaseRepo *repo = [[PDSDatabaseRepo alloc] init];
    repo.ownerDid = ownerDid;
    // Generate a realistic CID-like hash based on the owner DID
    NSString *cidInput = [NSString stringWithFormat:@"root:%@", ownerDid];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    repo.rootCid = [NSData dataWithBytes:cidBytes length:32];
    repo.createdAt = [NSDate date];
    repo.updatedAt = [NSDate date];
    return repo;
}

+ (PDSDatabaseRecord *)createTestRecordWithDID:(NSString *)did collection:(NSString *)collection rkey:(NSString *)rkey {
    PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
    record.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, collection, rkey];
    record.did = did;
    record.collection = collection;
    record.rkey = rkey;
    // Generate a realistic CID-like string based on the record data
    NSString *cidInput = [NSString stringWithFormat:@"record:%@:%@:%@", did, collection, rkey];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    NSMutableString *cidString = [NSMutableString stringWithString:@"bafyre"];
    for (int i = 0; i < 8; i++) {
        [cidString appendFormat:@"%02x", cidBytes[i]];
    }
    record.cid = cidString;
    record.createdAt = [NSDate date];
    return record;
}

+ (PDSDatabaseBlock *)createTestBlockWithRepoDID:(NSString *)repoDid {
    PDSDatabaseBlock *block = [[PDSDatabaseBlock alloc] init];
    // Generate realistic CID based on repo DID and content
    NSString *cidInput = [NSString stringWithFormat:@"block:%@:test block data", repoDid];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    block.cid = [NSData dataWithBytes:cidBytes length:32];
    block.repoDid = repoDid;
    block.blockData = [@"test block data" dataUsingEncoding:NSUTF8StringEncoding];
    block.size = block.blockData.length;
    block.createdAt = [NSDate date];
    return block;
}

+ (PDSDatabaseBlob *)createTestBlobWithDID:(NSString *)did {
    PDSDatabaseBlob *blob = [[PDSDatabaseBlob alloc] init];
    // Generate realistic CID based on DID and blob content
    NSString *cidInput = [NSString stringWithFormat:@"blob:%@:application/octet-stream:1024", did];
    NSData *cidInputData = [cidInput dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t cidBytes[32];
    CC_SHA256(cidInputData.bytes, (CC_LONG)cidInputData.length, cidBytes);
    blob.cid = [NSData dataWithBytes:cidBytes length:32];
    blob.did = did;
    blob.mimeType = @"application/octet-stream";
    blob.size = 1024;
    blob.createdAt = [NSDate date];
    return blob;
}

@end
