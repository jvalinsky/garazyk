#import <XCTest/XCTest.h>
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Repository/MST.h"
#import "Core/CID.h"

@interface CARInteropTests : XCTestCase

@end

@implementation CARInteropTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown {
    [super tearDown];
}

static NSData *HexToNSData(NSString *hex) {
    NSMutableData *data = [NSMutableData data];
    unsigned char whole_byte;
    char byte_chars[3] = {'\0','\0','\0'};
    for (NSUInteger i = 0; i < hex.length / 2; i++) {
        byte_chars[0] = [hex characterAtIndex:i * 2];
        byte_chars[1] = [hex characterAtIndex:i * 2 + 1];
        whole_byte = strtol(byte_chars, NULL, 16);
        [data appendBytes:&whole_byte length:1];
    }
    return [data copy];
}

- (void)testHexConversion {
    NSString *hex = @"01020304";
    NSData *data = HexToNSData(hex);
    XCTAssertEqual(data.length, 4, @"Should have 4 bytes");
    const uint8_t *bytes = data.bytes;
    XCTAssertEqual(bytes[0], 0x01, @"First byte should be 0x01");
    XCTAssertEqual(bytes[1], 0x02, @"Second byte should be 0x02");
    XCTAssertEqual(bytes[2], 0x03, @"Third byte should be 0x03");
    XCTAssertEqual(bytes[3], 0x04, @"Fourth byte should be 0x04");
}

- (void)testCARv1FormatUnderstanding {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *cid = [CID cidFromString:cidStr];
    XCTAssertNotNil(cid, @"CID should be created from string");
    
    NSData *cidBytes = [cid bytes];
    XCTAssertNotNil(cidBytes, @"CID bytes should not be nil");
    fprintf(stderr, "CID bytes length: %lu\n", (unsigned long)cidBytes.length);
    
    NSMutableData *carHeader = [NSMutableData data];
    uint32_t version = OSSwapHostToBigInt32(1);
    [carHeader appendBytes:&version length:4];
    
    uint32_t cidLen = OSSwapHostToBigInt32((uint32_t)cidBytes.length);
    [carHeader appendBytes:&cidLen length:4];
    [carHeader appendData:cidBytes];
    
    XCTAssertEqual(carHeader.length, 8 + cidBytes.length, @"CAR header should have correct length");
    
    const uint8_t *bytes = carHeader.bytes;
    uint32_t parsedVersion;
    memcpy(&parsedVersion, bytes, 4);
    parsedVersion = OSSwapBigToHostInt32(parsedVersion);
    XCTAssertEqual(parsedVersion, 1, @"Version should be 1");
    
    uint32_t parsedLen;
    memcpy(&parsedLen, bytes + 4, 4);
    parsedLen = OSSwapBigToHostInt32(parsedLen);
    XCTAssertEqual(parsedLen, (uint32_t)cidBytes.length, @"Root CID length should match");
    
    NSData *parsedCidData = [carHeader subdataWithRange:NSMakeRange(8, cidBytes.length)];
    XCTAssertEqualObjects(parsedCidData, cidBytes, @"Parsed CID should match original");
}

- (void)testCARv1HeaderParsing {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *cid = [CID cidFromString:cidStr];
    XCTAssertNotNil(cid, @"CID should be created from string");
    
    NSMutableData *carData = [NSMutableData data];
    uint32_t version = OSSwapHostToBigInt32(1);
    [carData appendBytes:&version length:4];
    
    NSData *cidBytes = [cid bytes];
    uint32_t cidLen = OSSwapHostToBigInt32((uint32_t)cidBytes.length);
    [carData appendBytes:&cidLen length:4];
    [carData appendData:cidBytes];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR data");
    XCTAssertNil(error, @"There should be no error");
    XCTAssertNotNil(reader.rootCID, @"Root CID should be set");
    XCTAssertEqualObjects(reader.rootCID.stringValue, cidStr);
}

- (void)testCARv1RoundTrip {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *rootCID = [CID cidFromString:cidStr];
    XCTAssertNotNil(rootCID, @"Root CID should be created");

    NSMutableData *block1Data = [NSMutableData dataWithBytes:"block1" length:6];
    CID *block1CID = [CID cidWithDigest:[CID sha256Digest:block1Data] codec:0x71];
    CARBlock *block1 = [CARBlock blockWithCID:block1CID data:block1Data];

    // Debug: print block CID bytes
    NSData *blockCIDBytes = [block1CID bytes];
    NSMutableString *cidHex = [NSMutableString string];
    for (NSUInteger i = 0; i < blockCIDBytes.length; i++) {
        [cidHex appendFormat:@"%02x ", ((uint8_t*)blockCIDBytes.bytes)[i]];
    }
    NSLog(@"Block CID bytes (%lu): %@", (unsigned long)blockCIDBytes.length, cidHex);

    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
    [writer addBlock:block1];

    NSData *carData = [writer serialize];
    XCTAssertNotNil(carData, @"Serialized data should not be nil");

    // Debug: print first 100 bytes
    const uint8_t *bytes = carData.bytes;
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < MIN(100, carData.length); i++) {
        [hex appendFormat:@"%02x ", bytes[i]];
    }
    NSLog(@"CAR v1 data (first %lu bytes): %@", (unsigned long)MIN(100, carData.length), hex);

    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    if (!reader) {
        NSLog(@"CARReader error: %@", error);
    }
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR v1 data");
    XCTAssertNil(error, @"There should be no error");
    XCTAssertEqualObjects(reader.rootCID, rootCID, @"Root CID should match");
    XCTAssertEqual(reader.blocks.count, 1, @"Should have exactly one block");

    CARBlock *roundTripped = reader.blocks.firstObject;
    XCTAssertEqualObjects(block1.cid, roundTripped.cid, @"Block CID should match");
    XCTAssertEqualObjects(block1.data, roundTripped.data, @"Block data should match");

    CARBlock *foundBlock = [reader blockWithCID:block1CID];
    XCTAssertNotNil(foundBlock, @"Should be able to lookup block by CID");
    XCTAssertEqualObjects(foundBlock.data, block1Data, @"Found block data should match");
}

- (void)testCARv1WriterSerialization {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *rootCID = [CID cidFromString:cidStr];
    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];

    NSData *blockData = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    CID *blockCID = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
    CARBlock *block = [CARBlock blockWithCID:blockCID data:blockData];
    [writer addBlock:block];

    NSData *serialized = [writer serialize];
    XCTAssertNotNil(serialized, @"Serialized data should not be nil");

    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:serialized error:&error];
    XCTAssertNotNil(reader, @"CARReader should parse CAR v1 data");
    XCTAssertNil(error, @"There should be no error parsing CAR v1");
    XCTAssertEqualObjects(reader.rootCID, rootCID, @"Root CID should match");
    XCTAssertEqual(reader.blocks.count, 1, @"Should have one block");
    XCTAssertEqualObjects(reader.blocks.firstObject.data, blockData, @"Block data should match");
}

- (void)testCARv1BlockLookup {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *rootCID = [CID cidFromString:cidStr];

    NSMutableData *block1Data = [NSMutableData dataWithBytes:"block1" length:6];
    CID *block1CID = [CID cidWithDigest:[CID sha256Digest:block1Data] codec:0x71];
    CARBlock *block1 = [CARBlock blockWithCID:block1CID data:block1Data];

    NSMutableData *block2Data = [NSMutableData dataWithBytes:"block2" length:6];
    CID *block2CID = [CID cidWithDigest:[CID sha256Digest:block2Data] codec:0x71];
    CARBlock *block2 = [CARBlock blockWithCID:block2CID data:block2Data];

    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
    [writer addBlock:block1];
    [writer addBlock:block2];

    NSData *carData = [writer serialize];
    XCTAssertNotNil(carData, @"Serialized data should not be nil");

    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR v1 data");
    XCTAssertNil(error, @"There should be no error");
    XCTAssertEqual(reader.blocks.count, 2, @"Should have two blocks");

    CARBlock *foundBlock1 = [reader blockWithCID:block1CID];
    XCTAssertNotNil(foundBlock1, @"Should be able to lookup block by CID");
    XCTAssertEqualObjects(foundBlock1.data, block1Data, @"Found block data should match");

    CARBlock *foundBlock2 = [reader blockWithCID:block2CID];
    XCTAssertNotNil(foundBlock2, @"Should be able to lookup block by CID");
    XCTAssertEqualObjects(foundBlock2.data, block2Data, @"Found block data should match");

    CID *nonexistentCID = [CID cidFromString:@"bafyreie5cvv4h45feadgeuwhbcutmh6t2ceseocckahdoe6uat64zmz454"];
    CARBlock *notFound = [reader blockWithCID:nonexistentCID];
    XCTAssertNil(notFound, @"Should not find nonexistent CID");
}

- (void)testCARv1BlockCIDConsistency {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *rootCID = [CID cidFromString:cidStr];

    NSData *blockData = [@"test block data for CID consistency" dataUsingEncoding:NSUTF8StringEncoding];
    CID *expectedBlockCID = [CID cidWithDigest:[CID sha256Digest:blockData] codec:0x71];
    CARBlock *block = [CARBlock blockWithCID:expectedBlockCID data:blockData];

    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
    [writer addBlock:block];

    NSData *carData = [writer serialize];
    XCTAssertNotNil(carData, @"Serialized data should not be nil");

    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR v1 data");
    XCTAssertNil(error, @"There should be no error");
    XCTAssertEqual(reader.blocks.count, 1, @"Should have exactly one block");

    CARBlock *parsedBlock = reader.blocks.firstObject;
    XCTAssertEqualObjects(parsedBlock.cid, expectedBlockCID, @"Block CID should match computed CID");
}

- (void)testMSTEnumerateNodeBlocksMatchesExportCAR {
    MST *mst = [[MST alloc] init];

    NSData *value1 = [@"record-1" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *value2 = [@"record-2" dataUsingEncoding:NSUTF8StringEncoding];
    CID *cid1 = [CID cidWithDigest:[CID sha256Digest:value1] codec:0x71];
    CID *cid2 = [CID cidWithDigest:[CID sha256Digest:value2] codec:0x71];
    XCTAssertNotNil(cid1);
    XCTAssertNotNil(cid2);

    [mst put:@"app.bsky.feed.post/enum-1" valueCID:cid1];
    [mst put:@"app.bsky.feed.post/enum-2" valueCID:cid2];

    NSMutableDictionary<NSString *, NSData *> *enumeratedBlocks = [NSMutableDictionary dictionary];
    NSError *enumerationError = nil;
    BOOL enumerated = [mst enumerateNodeCARBlocksUsingBlock:^BOOL(CID *cid, NSData *data, NSError **error) {
        (void)error;
        NSString *cidString = cid.stringValue ?: @"";
        if (cidString.length == 0) {
            return YES;
        }
        enumeratedBlocks[cidString] = data;
        return YES;
    } error:&enumerationError];
    XCTAssertTrue(enumerated);
    XCTAssertNil(enumerationError);
    XCTAssertTrue(enumeratedBlocks.count > 0);

    NSData *carData = [mst exportCAR];
    XCTAssertNotNil(carData);

    NSError *carError = nil;
    CARReader *reader = [CARReader readFromData:carData error:&carError];
    XCTAssertNotNil(reader);
    XCTAssertNil(carError);

    NSMutableDictionary<NSString *, NSData *> *exportedBlocks = [NSMutableDictionary dictionary];
    for (CARBlock *block in reader.blocks) {
        NSString *cidString = block.cid.stringValue ?: @"";
        if (cidString.length == 0) {
            continue;
        }
        exportedBlocks[cidString] = block.data;
    }

    XCTAssertEqual(enumeratedBlocks.count, exportedBlocks.count);
    for (NSString *cidString in exportedBlocks) {
        NSData *enumeratedData = enumeratedBlocks[cidString];
        XCTAssertNotNil(enumeratedData, @"Expected enumerated block for CID %@", cidString);
        XCTAssertEqualObjects(enumeratedData, exportedBlocks[cidString], @"Block data mismatch for CID %@", cidString);
    }
}

@end
