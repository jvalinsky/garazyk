// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
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

@property (nonatomic, copy, readwrite) NSArray<CID *> *roots;
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

    NSData *taggedCIDBytes = value.tagValue.byteString;
    if (!taggedCIDBytes || taggedCIDBytes.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-11
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header CID bytes are empty"}];
        }
        return nil;
    }

    // Dag-CBOR CID tag (42) is encoded as a byte string with a leading 0x00 marker,
    // followed by the raw CID bytes.
    NSData *cidBytes = taggedCIDBytes;
    const uint8_t *bytes = cidBytes.bytes;
    if (cidBytes.length > 0 && bytes[0] == 0x00) {
        cidBytes = [cidBytes subdataWithRange:NSMakeRange(1, cidBytes.length - 1)];
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
    NSUInteger consumed = 0;
    CID *cid = [CID cidFromBuffer:bytes length:length consumed:&consumed];
    if (!cid) {
        return NO;
    }
    if (cidOut) *cidOut = cid;
    if (cidLengthOut) *cidLengthOut = consumed;
    return YES;
}

- (CID *)rootCID {
  return self.roots.firstObject;
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

    NSMutableArray<CID *> *parsedRoots = [NSMutableArray arrayWithCapacity:rootsValue.array.count];
    for (CBORValue *rootEntry in rootsValue.array) {
      NSError *rootError = nil;
      CID *rootCID = CIDFromTaggedCBOR(rootEntry, &rootError);
      if (!rootCID) {
        if (error) *error = rootError;
        return NO;
      }
      [parsedRoots addObject:rootCID];
    }
    if (parsedRoots.count == 0) {
      if (error) {
        *error = [NSError errorWithDomain:@"com.atproto.car"
                                     code:-2
                                 userInfo:@{NSLocalizedDescriptionKey: @"CAR header missing roots"}];
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

    _roots = [parsedRoots copy];
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
    _roots = @[rootCID];

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

static NSData *CARHeaderDataForRootCID(CID *rootCID) {
    if (!rootCID) {
        return nil;
    }

    NSMutableData *taggedCIDBytes = [NSMutableData dataWithCapacity:1 + rootCID.bytes.length];
    uint8_t marker = 0x00;
    [taggedCIDBytes appendBytes:&marker length:1];
    [taggedCIDBytes appendData:rootCID.bytes];

    CBORValue *rootsArray = [CBORValue array:@[
        [CBORValue tag:42 value:[CBORValue byteString:taggedCIDBytes]]
    ]];

    CBORValue *headerMap = [CBORValue map:@{
        [CBORValue textString:@"roots"]: rootsArray,
        [CBORValue textString:@"version"]: [CBORValue unsignedInteger:1]
    }];

    NSData *headerCBOR = [headerMap encode];
    uint8_t headerLenBuffer[16];
    NSUInteger headerLenSize = WriteVarint(headerCBOR.length, headerLenBuffer);

    NSMutableData *encodedHeader = [NSMutableData dataWithCapacity:headerLenSize + headerCBOR.length];
    [encodedHeader appendBytes:headerLenBuffer length:headerLenSize];
    [encodedHeader appendData:headerCBOR];
    return [encodedHeader copy];
}

static NSData *CARBlockEntryData(CARBlock *block) {
    if (!block || !block.cid || !block.data) {
        return nil;
    }

    NSData *cidBytes = [block.cid bytes];
    NSUInteger totalLength = cidBytes.length + block.data.length;

    uint8_t blockLenBuffer[16];
    NSUInteger blockLenSize = WriteVarint(totalLength, blockLenBuffer);

    NSMutableData *entry = [NSMutableData dataWithCapacity:blockLenSize + totalLength];
    [entry appendBytes:blockLenBuffer length:blockLenSize];
    [entry appendData:cidBytes];
    [entry appendData:block.data];
    return [entry copy];
}

- (NSData *)serialize {
    NSMutableData *data = [NSMutableData data];

    NSData *headerData = CARHeaderDataForRootCID(self.rootCID);
    if (!headerData) {
        return nil;
    }
    [data appendData:headerData];

    for (CARBlock *block in self.blocks) {
        NSData *entry = CARBlockEntryData(block);
        if (!entry) {
            continue;
        }
        [data appendData:entry];
    }

    return [data copy];
}

+ (nullable NSData *)encodedHeaderWithRootCID:(CID *)rootCID error:(NSError **)error {
    NSData *headerData = CARHeaderDataForRootCID(rootCID);
    if (!headerData) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-25
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR header parameters"}];
        }
        return nil;
    }
    return headerData;
}

+ (nullable NSData *)encodedBlock:(CARBlock *)block error:(NSError **)error {
    NSData *entryData = CARBlockEntryData(block);
    if (!entryData) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-26
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR block parameters"}];
        }
        return nil;
    }
    return entryData;
}

+ (BOOL)writeHeaderWithRootCID:(CID *)rootCID
                 toFileHandle:(NSFileHandle *)fileHandle
                        error:(NSError **)error {
    NSData *headerData = [[self class] encodedHeaderWithRootCID:rootCID error:error];
    if (!headerData || !fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-21
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR header write parameters"}];
        }
        return NO;
    }

    @try {
        [fileHandle writeData:headerData];
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-22
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to write CAR header"}];
        }
        return NO;
    }
}

+ (BOOL)writeBlock:(CARBlock *)block
      toFileHandle:(NSFileHandle *)fileHandle
             error:(NSError **)error {
    NSData *entryData = [[self class] encodedBlock:block error:error];
    if (!entryData || !fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-23
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR block write parameters"}];
        }
        return NO;
    }

    @try {
        [fileHandle writeData:entryData];
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-24
                                     userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Failed to write CAR block"}];
        }
        return NO;
    }
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
        NSError *writeError = nil;
        if (![[self class] writeHeaderWithRootCID:self.rootCID toFileHandle:fileHandle error:&writeError]) {
            if (error) *error = writeError;
            [fileHandle closeFile];
            return NO;
        }

        for (CARBlock *block in self.blocks) {
            if (![[self class] writeBlock:block toFileHandle:fileHandle error:&writeError]) {
                if (error) *error = writeError;
                [fileHandle closeFile];
                return NO;
            }
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
