/*!
 @file CAR.m

 @abstract CAR (Content Addressable aRchives) file format implementation.

 @discussion This file implements CAR v1 format for ATProto repository
 serialization. CAR archives contain content-addressable blocks with
 CID references, used for MST export and import operations.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Repository/CAR.h"
#import "Repository/MST.h"
#import <Security/Security.h>

#pragma mark - CARBlock Implementation

@implementation CARBlock

+ (instancetype)blockWithCID:(CID *)cid data:(NSData *)data {
    return [[self alloc] initWithCID:cid data:data];
}

- (instancetype)initWithCID:(CID *)cid data:(NSData *)data {
    self = [super init];
    if (self) {
        _cid = cid;
        _data = data;
    }
    return self;
}

@end

#pragma mark - CARReader Implementation

@interface CARReader ()

@property (nonatomic, strong, readwrite) CID *rootCID;
@property (nonatomic, strong, readwrite) NSArray<CARBlock *> *blocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CARBlock *> *blockIndex;

@end

@implementation CARReader

+ (instancetype)readFromData:(NSData *)data error:(NSError **)error {
    CARReader *reader = [[CARReader alloc] init];
    if (![reader parseData:data error:error]) {
        return nil;
    }
    return reader;
}

+ (instancetype)readFromPath:(NSString *)path error:(NSError **)error {
#if defined(__APPLE__)
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
#else
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data && error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    }
#endif
    if (!data) {
        return nil;
    }
    return [self readFromData:data error:error];
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error {
    if (data.length < 8) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Data too short for CAR header"}];
        }
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;

    uint32_t version;
    memcpy(&version, bytes + offset, 4);
    version = OSSwapBigToHostInt32(version);
    offset += 4;

    if (version != 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported CAR version: %u", version]}];
        }
        return NO;
    }

    uint32_t rootCidLength;
    memcpy(&rootCidLength, bytes + offset, 4);
    rootCidLength = OSSwapBigToHostInt32(rootCidLength);
    offset += 4;

    if (offset + rootCidLength > data.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Root CID extends beyond data"}];
        }
        return NO;
    }

    NSData *rootCidData = [data subdataWithRange:NSMakeRange(offset, rootCidLength)];
    offset += rootCidLength;

    CID *rootCID = [CID cidFromBytes:rootCidData];
    if (!rootCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse root CID"}];
        }
        return NO;
    }
    _rootCID = rootCID;

    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];
    NSMutableDictionary<NSString *, CARBlock *> *index = [NSMutableDictionary dictionary];

    while (offset < data.length) {
        if (offset + 4 > data.length) {
            break;
        }

        uint32_t blockLen;
        memcpy(&blockLen, bytes + offset, 4);
        blockLen = OSSwapBigToHostInt32(blockLen);
        offset += 4;

        if (offset + blockLen > data.length) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-6
                                         userInfo:@{NSLocalizedDescriptionKey: @"Block extends beyond data"}];
            }
            return NO;
        }

        NSData *blockData = [data subdataWithRange:NSMakeRange(offset, blockLen)];
        offset += blockLen;

        CID *blockCID = [self computeBlockCID:blockData];
        if (blockCID) {
            CARBlock *block = [CARBlock blockWithCID:blockCID data:blockData];
            [blocks addObject:block];
            index[blockCID.stringValue] = block;
        }
    }

    _blocks = [blocks copy];
    _blockIndex = [index copy];

    return YES;
}

- (CID *)computeBlockCID:(NSData *)blockData {
    NSData *multihash = [CID sha256Digest:blockData];
    return [CID cidWithMultihash:multihash codec:0x71];
}

- (CARBlock *)blockWithCID:(CID *)cid {
    return self.blockIndex[cid.stringValue];
}

@end

#pragma mark - CARWriter Implementation

@interface CARWriter ()

@property (nonatomic, strong, readwrite) CID *rootCID;
@property (nonatomic, strong, readwrite) NSMutableArray<CARBlock *> *blocks;

@end

@implementation CARWriter

+ (instancetype)writerWithRootCID:(CID *)rootCID {
    return [[self alloc] initWithRootCID:rootCID];
}

- (instancetype)initWithRootCID:(CID *)rootCID {
    self = [super init];
    if (self) {
        _rootCID = rootCID;
        _blocks = [NSMutableArray array];
    }
    return self;
}

- (void)addBlock:(CARBlock *)block {
    [self.blocks addObject:block];
}

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    uint32_t version = OSSwapHostToBigInt32(1);
    [data appendBytes:&version length:4];

    NSData *rootCIDBytes = [self.rootCID bytes];
    uint32_t rootLen = OSSwapHostToBigInt32((uint32_t)rootCIDBytes.length);
    [data appendBytes:&rootLen length:4];
    [data appendData:rootCIDBytes];

    for (CARBlock *block in self.blocks) {
        NSData *blockData = block.data;
        uint32_t blockLen = OSSwapHostToBigInt32((uint32_t)blockData.length);
        [data appendBytes:&blockLen length:4];
        [data appendData:blockData];
    }

    return [data copy];
}

- (BOOL)writeToPath:(NSString *)path error:(NSError **)error {
    NSData *data = [self serialize];
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}

@end
