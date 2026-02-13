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
#import "Repository/CBOR.h"
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

- (BOOL)parseCarV1Data:(NSData *)data error:(NSError **)error;
- (BOOL)parseLegacyData:(NSData *)data error:(NSError **)error;

@end

@implementation CARReader

static NSUInteger ReadVarint(const uint8_t *bytes, NSUInteger maxLength, uint64_t *value) {
    if (maxLength == 0) {
        return 0;
    }

    uint64_t result = 0;
    NSUInteger shift = 0;
    NSUInteger offset = 0;

    while (offset < maxLength) {
        uint8_t byte = bytes[offset++];
        result |= ((uint64_t)(byte & 0x7F)) << shift;
        shift += 7;

        if ((byte & 0x80) == 0) {
            *value = result;
            return offset;
        }

        if (shift >= 64) {
            return 0;
        }
    }

    return 0;
}

static CID *CIDFromTaggedCBOR(CBORValue *value, NSError **error) {
    if (!value || value.type != CBORTypeTag || !value.tagValue || value.tagValue.type != CBORTypeByteString) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-10
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header roots entry is not a CID tag"}];
        }
        return nil;
    }

    NSData *cidBytes = value.tagValue.byteString;
    if (!cidBytes || cidBytes.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header CID bytes are empty"}];
        }
        return nil;
    }

    CID *cid = [CID cidFromBytes:cidBytes];
    if (!cid && error) {
        *error = [NSError errorWithDomain:@"com.atproto.car"
                                     code:-12
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse root CID"}];
    }
    return cid;
}

static BOOL DecodeCIDFromBlock(const uint8_t *bytes, NSUInteger length, CID **cidOut, NSUInteger *cidLengthOut) {
    if (!bytes || length < 4) {
        return NO;
    }

    NSUInteger offset = 0;

    // Read version varint (should be 1 for CIDv1)
    uint64_t version = 0;
    NSUInteger versionSize = ReadVarint(bytes, length, &version);
    if (versionSize == 0 || version != 1) {
        return NO;
    }
    offset += versionSize;

    // Read codec varint (should be 0x71 for dag-cbor)
    uint64_t codec = 0;
    NSUInteger codecSize = ReadVarint(bytes + offset, length - offset, &codec);
    if (codecSize == 0 || codec > UINT32_MAX) {
        return NO;
    }
    offset += codecSize;

    // Need at least 2 more bytes for hash code (0x12) and hash length (0x20)
    if (offset + 2 > length) {
        return NO;
    }

    // Validate hash code is sha2-256 (0x12)
    if (bytes[offset] != 0x12) {
        return NO;
    }
    offset++;

    // Validate hash length is 32
    if (bytes[offset] != 0x20) {
        return NO;
    }
    offset++;

    // Skip the 32-byte hash digest
    if (offset + 32 > length) {
        return NO;
    }
    offset += 32;

    // Create CID from the full CID bytes
    NSData *cidData = [NSData dataWithBytes:bytes length:offset];
    CID *cid = [CID cidFromBytes:cidData];
    if (!cid) {
        return NO;
    }

    if (cidOut) {
        *cidOut = cid;
    }
    if (cidLengthOut) {
        *cidLengthOut = offset;
    }
    return YES;
}

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
    NSError *v1Error = nil;
    if ([self parseCarV1Data:data error:&v1Error]) {
        return YES;
    }

    if ([self parseLegacyData:data error:error]) {
        return YES;
    }

    if (error && v1Error) {
        *error = v1Error;
    }
    return NO;
}

- (BOOL)parseCarV1Data:(NSData *)data error:(NSError **)error {
    if (data.length < 2) {
        return NO;
    }

    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    uint64_t headerLength = 0;
    NSUInteger headerSize = ReadVarint(bytes + offset, data.length - offset, &headerLength);
    if (headerSize == 0 || headerLength == 0) {
        return NO;
    }
    offset += headerSize;

    if (offset + headerLength > data.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header extends beyond data"}];
        }
        return NO;
    }

    NSData *headerData = [data subdataWithRange:NSMakeRange(offset, headerLength)];
    offset += headerLength;

    CBORValue *header = [CBORValue decode:headerData];
    if (!header || header.type != CBORTypeMap) {
        return NO;
    }

    CBORValue *rootsValue = header.map[[CBORValue textString:@"roots"]];
    if (!rootsValue || rootsValue.type != CBORTypeArray || rootsValue.array.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header missing roots"}];
        }
        return NO;
    }

    NSError *rootError = nil;
    CID *rootCID = CIDFromTaggedCBOR(rootsValue.array.firstObject, &rootError);
    if (!rootCID) {
        if (error) {
            *error = rootError;
        }
        return NO;
    }

    CBORValue *versionValue = header.map[[CBORValue textString:@"version"]];
    if (!versionValue || versionValue.type != CBORTypeUnsignedInteger || versionValue.unsignedInteger.unsignedIntegerValue != 1) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported CAR version"}];
        }
        return NO;
    }

    NSMutableArray<CARBlock *> *blocks = [NSMutableArray array];
    NSMutableDictionary<NSString *, CARBlock *> *index = [NSMutableDictionary dictionary];

    while (offset < data.length) {
        uint64_t blockLen = 0;
        NSUInteger blockSize = ReadVarint(bytes + offset, data.length - offset, &blockLen);
        if (blockSize == 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR block length"}];
            }
            return NO;
        }
        offset += blockSize;

        if (offset + blockLen > data.length) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-5
                                         userInfo:@{NSLocalizedDescriptionKey: @"CAR block extends beyond data"}];
            }
            return NO;
        }

        NSData *blockBytes = [data subdataWithRange:NSMakeRange(offset, (NSUInteger)blockLen)];
        offset += (NSUInteger)blockLen;

        CID *blockCID = nil;
        NSUInteger cidLength = 0;
        if (!DecodeCIDFromBlock(blockBytes.bytes, blockBytes.length, &blockCID, &cidLength)) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-6
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse CID from CAR block"}];
            }
            return NO;
        }

        NSData *blockData = [blockBytes subdataWithRange:NSMakeRange(cidLength, blockBytes.length - cidLength)];
        CARBlock *block = [CARBlock blockWithCID:blockCID data:blockData];
        [blocks addObject:block];
        index[blockCID.stringValue] = block;
    }

    _rootCID = rootCID;
    _blocks = [blocks copy];
    _blockIndex = [index copy];
    return YES;
}

- (BOOL)parseLegacyData:(NSData *)data error:(NSError **)error {
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
    NSData *digest = [CID sha256Digest:blockData];
    return [CID cidWithDigest:digest codec:0x71];
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

static NSUInteger WriteVarint(uint64_t value, uint8_t *buffer) {
    NSUInteger bytesWritten = 0;
    while (value > 0x7F) {
        buffer[bytesWritten++] = (uint8_t)((value & 0x7F) | 0x80);
        value >>= 7;
    }
    buffer[bytesWritten++] = (uint8_t)(value & 0x7F);
    return bytesWritten;
}

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    CBORValue *rootsArray = [CBORValue array:@[
        [CBORValue tag:42 value:[CBORValue byteString:[self.rootCID bytes]]]
    ]];

    CBORValue *headerMap = [CBORValue map:@{
        [CBORValue textString:@"roots"]: rootsArray,
        [CBORValue textString:@"version"]: [CBORValue unsignedInteger:1]
    }];

    NSData *headerCBOR = [headerMap encode];
    uint8_t headerLenBuffer[16];
    NSUInteger headerLenSize = WriteVarint(headerCBOR.length, headerLenBuffer);
    [data appendBytes:headerLenBuffer length:headerLenSize];
    [data appendData:headerCBOR];

    for (CARBlock *block in self.blocks) {
        NSData *cidBytes = [block.cid bytes];
        NSUInteger totalLength = cidBytes.length + block.data.length;

        uint8_t blockLenBuffer[16];
        NSUInteger blockLenSize = WriteVarint(totalLength, blockLenBuffer);
        [data appendBytes:blockLenBuffer length:blockLenSize];
        [data appendData:cidBytes];
        [data appendData:block.data];
    }

    return [data copy];
}

- (BOOL)writeToPath:(NSString *)path error:(NSError **)error {
    if (![[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to create CAR output file"}];
        }
        return NO;
    }

    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain
                                         code:errno
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to open CAR output file"}];
        }
        return NO;
    }

    @try {
        CBORValue *rootsArray = [CBORValue array:@[
            [CBORValue tag:42 value:[CBORValue byteString:[self.rootCID bytes]]]
        ]];
        CBORValue *headerMap = [CBORValue map:@{
            [CBORValue textString:@"roots"]: rootsArray,
            [CBORValue textString:@"version"]: [CBORValue unsignedInteger:1]
        }];
        NSData *headerCBOR = [headerMap encode];

        uint8_t headerLenBuffer[16];
        NSUInteger headerLenSize = WriteVarint(headerCBOR.length, headerLenBuffer);
        [fileHandle writeData:[NSData dataWithBytes:headerLenBuffer length:headerLenSize]];
        [fileHandle writeData:headerCBOR];

        for (CARBlock *block in self.blocks) {
            NSData *cidBytes = [block.cid bytes];
            NSUInteger totalLength = cidBytes.length + block.data.length;

            uint8_t blockLenBuffer[16];
            NSUInteger blockLenSize = WriteVarint(totalLength, blockLenBuffer);
            [fileHandle writeData:[NSData dataWithBytes:blockLenBuffer length:blockLenSize]];
            [fileHandle writeData:cidBytes];
            [fileHandle writeData:block.data];
        }

        [fileHandle closeFile];
        return YES;
    } @catch (NSException *exception) {
        [fileHandle closeFile];
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-20
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to stream CAR to file"}];
        }
        return NO;
    }
}

@end
