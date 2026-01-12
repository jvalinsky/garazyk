#import <XCTest/XCTest.h>
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
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
    
    NSMutableData *carData = [NSMutableData data];
    uint32_t version = OSSwapHostToBigInt32(1);
    [carData appendBytes:&version length:4];
    
    NSData *cidBytes = [rootCID bytes];
    uint32_t cidLen = OSSwapHostToBigInt32((uint32_t)cidBytes.length);
    [carData appendBytes:&cidLen length:4];
    [carData appendData:cidBytes];
    
    NSMutableData *block1Data = [NSMutableData dataWithBytes:"block1" length:6];
    CID *block1CID = [CID cidWithMultihash:[CID sha256Digest:block1Data] codec:0x71];
    uint32_t block1Len = OSSwapHostToBigInt32((uint32_t)block1Data.length);
    [carData appendBytes:&block1Len length:4];
    [carData appendData:block1Data];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR data");
    XCTAssertNil(error, @"There should be no error");
    
    CARWriter *writer = [CARWriter writerWithRootCID:reader.rootCID];
    for (CARBlock *block in reader.blocks) {
        [writer addBlock:block];
    }
    
    NSData *serialized = [writer serialize];
    XCTAssertNotNil(serialized, @"Serialized data should not be nil");
    XCTAssertEqual(serialized.length, carData.length, @"Serialized data should have same length as original");
    
    CARReader *reReader = [CARReader readFromData:serialized error:&error];
    XCTAssertNotNil(reReader, @"Re-reading serialized CAR should succeed");
    XCTAssertEqualObjects(reReader.rootCID, reader.rootCID, @"Root CID should match after round-trip");
    XCTAssertEqual(reReader.blocks.count, reader.blocks.count, @"Block count should match after round-trip");
    
    for (NSUInteger i = 0; i < reader.blocks.count; i++) {
        CARBlock *original = reader.blocks[i];
        CARBlock *roundTripped = reReader.blocks[i];
        XCTAssertEqualObjects(original.cid, roundTripped.cid, @"Block CID %lu should match", (unsigned long)i);
        XCTAssertEqualObjects(original.data, roundTripped.data, @"Block data %lu should match", (unsigned long)i);
    }
}

- (void)testCARv1WriterSerialization {
    CID *rootCID = [CID cidFromString:@"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu"];
    CARWriter *writer = [CARWriter writerWithRootCID:rootCID];
    
    NSData *blockData = [@"hello world" dataUsingEncoding:NSUTF8StringEncoding];
    CID *blockCID = [CID cidWithMultihash:[CID sha256Digest:blockData] codec:0x71];
    CARBlock *block = [CARBlock blockWithCID:blockCID data:blockData];
    [writer addBlock:block];
    
    NSData *serialized = [writer serialize];
    XCTAssertNotNil(serialized, @"Serialized data should not be nil");
    XCTAssertGreaterThanOrEqual(serialized.length, (NSUInteger)8, @"Serialized data should have header");
    
    const uint8_t *bytes = serialized.bytes;
    uint32_t version;
    memcpy(&version, bytes, 4);
    version = OSSwapBigToHostInt32(version);
    XCTAssertEqual(version, 1, @"Version should be 1");
    
    uint32_t rootLen;
    memcpy(&rootLen, bytes + 4, 4);
    rootLen = OSSwapBigToHostInt32(rootLen);
    XCTAssertGreaterThan(rootLen, (uint32_t)0, @"Root CID length should be positive");
    
    NSUInteger offset = 8 + rootLen;
    XCTAssertLessThanOrEqual(offset, serialized.length, @"Root CID should be within bounds");
    
    uint32_t blockLen;
    memcpy(&blockLen, bytes + offset, 4);
    blockLen = OSSwapBigToHostInt32(blockLen);
    XCTAssertEqual(blockLen, (uint32_t)blockData.length, @"Block length should match");
}

- (void)testCARv1BlockLookup {
    NSString *cidStr = @"bafyreieovfuizojpw3zresz7sx3nk4trm2by23pt5rxbey3jme4uo5ogiu";
    CID *rootCID = [CID cidFromString:cidStr];
    
    NSMutableData *carData = [NSMutableData data];
    uint32_t version = OSSwapHostToBigInt32(1);
    [carData appendBytes:&version length:4];
    
    NSData *cidBytes = [rootCID bytes];
    uint32_t cidLen = OSSwapHostToBigInt32((uint32_t)cidBytes.length);
    [carData appendBytes:&cidLen length:4];
    [carData appendData:cidBytes];
    
    NSMutableData *block1Data = [NSMutableData dataWithBytes:"block1" length:6];
    CID *block1CID = [CID cidWithMultihash:[CID sha256Digest:block1Data] codec:0x71];
    uint32_t block1Len = OSSwapHostToBigInt32((uint32_t)block1Data.length);
    [carData appendBytes:&block1Len length:4];
    [carData appendData:block1Data];
    
    NSMutableData *block2Data = [NSMutableData dataWithBytes:"block2" length:6];
    CID *block2CID = [CID cidWithMultihash:[CID sha256Digest:block2Data] codec:0x71];
    uint32_t block2Len = OSSwapHostToBigInt32((uint32_t)block2Data.length);
    [carData appendBytes:&block2Len length:4];
    [carData appendData:block2Data];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR data");
    
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
    
    NSMutableData *carData = [NSMutableData data];
    uint32_t version = OSSwapHostToBigInt32(1);
    [carData appendBytes:&version length:4];
    
    NSData *cidBytes = [rootCID bytes];
    uint32_t cidLen = OSSwapHostToBigInt32((uint32_t)cidBytes.length);
    [carData appendBytes:&cidLen length:4];
    [carData appendData:cidBytes];
    
    NSData *blockData = [@"test block data for CID consistency" dataUsingEncoding:NSUTF8StringEncoding];
    CID *expectedBlockCID = [CID cidWithMultihash:[CID sha256Digest:blockData] codec:0x71];
    uint32_t blockLen = OSSwapHostToBigInt32((uint32_t)blockData.length);
    [carData appendBytes:&blockLen length:4];
    [carData appendData:blockData];
    
    NSError *error = nil;
    CARReader *reader = [CARReader readFromData:carData error:&error];
    XCTAssertNotNil(reader, @"CARReader should parse valid CAR data");
    XCTAssertEqual(reader.blocks.count, 1, @"Should have exactly one block");
    
    CARBlock *block = reader.blocks.firstObject;
    XCTAssertEqualObjects(block.cid, expectedBlockCID, @"Block CID should match computed CID");
}

@end
