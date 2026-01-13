#import "Repository/CARv1Builder.h"
#import "Repository/CBOR.h"
#import "Core/CID.h"

@interface CARv1Builder ()

@property (nonatomic, strong, readwrite) NSArray<CID *> *roots;
@property (nonatomic, strong) NSMutableArray<NSData *> *blockData;

@end

@implementation CARv1Builder

+ (instancetype)builderWithRoot:(CID *)root {
    return [self builderWithRoots:@[root]];
}

+ (instancetype)builderWithRoots:(NSArray<CID *> *)roots {
    CARv1Builder *builder = [[CARv1Builder alloc] init];
    builder.roots = [roots copy];
    builder.blockData = [NSMutableArray array];
    return builder;
}

- (void)addBlockWithCID:(CID *)cid data:(NSData *)data {
    // Each block is: CID bytes + data
    // The CID includes the multicodec prefix
    NSData *cidBytes = [cid bytes];
    
    NSMutableData *block = [NSMutableData data];
    [block appendData:cidBytes];
    [block appendData:data];
    
    [self.blockData addObject:[block copy]];
}

- (NSData *)build {
    NSMutableData *car = [NSMutableData data];
    
    // Build header: {version: 1, roots: [cid1, ...]}
    NSData *header = [self buildHeader];
    
    // Write header with varint length prefix
    NSData *headerLenVarint = [CARv1Builder encodeVarint:header.length];
    [car appendData:headerLenVarint];
    [car appendData:header];
    
    // Write each block with varint length prefix
    for (NSData *block in self.blockData) {
        NSData *blockLenVarint = [CARv1Builder encodeVarint:block.length];
        [car appendData:blockLenVarint];
        [car appendData:block];
    }
    
    return [car copy];
}

- (NSData *)buildHeader {
    // Build roots array as CBOR
    NSMutableArray<CBORValue *> *rootsCBOR = [NSMutableArray array];
    
    for (CID *root in self.roots) {
        // CIDs in CAR headers are CBOR tag 42 with null byte prefix
        NSMutableData *cidWithPrefix = [NSMutableData dataWithBytes:"\x00" length:1];
        [cidWithPrefix appendData:[root bytes]];
        
        CBORValue *cidValue = [CBORValue tag:42 value:[CBORValue byteString:cidWithPrefix]];
        [rootsCBOR addObject:cidValue];
    }
    
    // Build header map: {roots: [...], version: 1}
    // Keys must be in sorted order for DAG-CBOR
    NSDictionary<CBORValue *, CBORValue *> *headerDict = @{
        [CBORValue textString:@"roots"]: [CBORValue array:rootsCBOR],
        [CBORValue textString:@"version"]: [CBORValue unsignedInteger:1]
    };
    
    CBORValue *headerValue = [CBORValue map:headerDict];
    return [headerValue encode];
}

#pragma mark - Varint Encoding/Decoding

+ (NSData *)encodeVarint:(uint64_t)value {
    NSMutableData *result = [NSMutableData data];
    
    while (value >= 0x80) {
        uint8_t byte = (value & 0x7F) | 0x80;
        [result appendBytes:&byte length:1];
        value >>= 7;
    }
    
    uint8_t finalByte = (uint8_t)value;
    [result appendBytes:&finalByte length:1];
    
    return [result copy];
}

+ (uint64_t)decodeVarint:(NSData *)data bytesConsumed:(NSUInteger *)consumed {
    const uint8_t *bytes = data.bytes;
    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger i = 0;
    
    while (i < data.length) {
        uint8_t byte = bytes[i++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        
        if ((byte & 0x80) == 0) {
            break;
        }
        
        shift += 7;
        
        // Protect against overflow (max 10 bytes for 64-bit varint)
        if (shift >= 70) {
            break;
        }
    }
    
    if (consumed) {
        *consumed = i;
    }
    
    return result;
}

@end
