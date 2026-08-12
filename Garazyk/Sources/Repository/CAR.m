// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file CAR.m

 @abstract CAR (Content Addressable aRchives) file format implementation.

 @discussion This file implements CAR v1 format for ATProto repository
 serialization. CAR archives contain content-addressable blocks with
 ATProtoCID references, used for ATProtoMST export and import operations.

 @copyright Copyright (c) 2024 Jack Valinsky
 */

#import "Repository/CAR.h"
#import "Repository/MST.h"
#import "Core/ATProtoDagCBOR.h"
#import "Core/ATProtoMASLDocument.h"
#import "Core/CID+DASL.h"
#import <Security/Security.h>
#include <string.h>

#pragma mark - ATProtoCARBlock Implementation

@implementation ATProtoCARBlock

+ (instancetype)blockWithCID:(ATProtoCID *)cid data:(NSData *)data {
    return [[self alloc] initWithCID:cid data:data];
}

- (instancetype)initWithCID:(ATProtoCID *)cid data:(NSData *)data {
    self = [super init];
    if (self) {
        _cid = cid;
        _data = data;
    }
    return self;
}

@end

#pragma mark - ATProtoCARReader Implementation

@interface ATProtoCARReader ()

@property (nonatomic, copy, readwrite) NSArray<ATProtoCID *> *roots;
@property (nonatomic, copy, readwrite, nullable) NSDictionary *metadata;
@property (nonatomic, strong, readwrite, nullable) ATProtoMASLDocument *maslDocument;
@property (nonatomic, copy, readwrite) NSArray<ATProtoCARBlock *> *blocks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoCARBlock *> *blockIndex;

- (BOOL)parseCarV1Data:(NSData *)data strict:(BOOL)strict error:(NSError **)error;
- (BOOL)parseLegacyData:(NSData *)data error:(NSError **)error;

@end

@implementation ATProtoCARReader

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

static BOOL DecodeCIDFromBlock(const uint8_t *bytes, NSUInteger length, ATProtoCID **cidOut, NSUInteger *cidLengthOut) {
    NSUInteger consumed = 0;
    ATProtoCID *cid = [ATProtoCID cidFromBuffer:bytes length:length consumed:&consumed];
    if (!cid) {
        return NO;
    }
    if (cidOut) *cidOut = cid;
    if (cidLengthOut) *cidLengthOut = consumed;
    return YES;
}

static BOOL CARIsIntegerOne(id value) {
    if (![value isKindOfClass:[NSNumber class]]) return NO;
    const char *type = [(NSNumber *)value objCType];
    if (!type || strlen(type) != 1 || strchr("islqiuILQ", type[0]) == NULL) return NO;
    return [(NSNumber *)value longLongValue] == 1;
}

- (ATProtoCID *)rootCID {
  return self.roots.firstObject;
}

+ (instancetype)readFromData:(NSData *)data error:(NSError **)error {
    return [self readFromData:data strict:NO error:error];
}

+ (instancetype)readFromData:(NSData *)data strict:(BOOL)strict error:(NSError **)error {
    ATProtoCARReader *reader = [[ATProtoCARReader alloc] init];
    if (![reader parseData:data strict:strict error:error]) {
        return nil;
    }
    return reader;
}

+ (instancetype)readFromPath:(NSString *)path error:(NSError **)error {
    return [self readFromPath:path strict:NO error:error];
}

+ (instancetype)readFromPath:(NSString *)path strict:(BOOL)strict error:(NSError **)error {
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
    return [self readFromData:data strict:strict error:error];
}

- (BOOL)parseData:(NSData *)data error:(NSError **)error {
    return [self parseData:data strict:NO error:error];
}

- (BOOL)parseData:(NSData *)data strict:(BOOL)strict error:(NSError **)error {
    NSError *v1Error = nil;
    if ([self parseCarV1Data:data strict:strict error:&v1Error]) {
        return YES;
    }

    // The legacy layout is a fixed-width header this project once wrote; it is
    // not a CAR variant, and it recomputes block CIDs from the payload instead
    // of reading them, which would paper over a malformed v1 archive. Strict
    // callers get the v1 error instead.
    if (!strict && [self parseLegacyData:data error:error]) {
        return YES;
    }

    if (error && v1Error) {
        *error = v1Error;
    }
    return NO;
}

- (BOOL)parseCarV1Data:(NSData *)data strict:(BOOL)strict error:(NSError **)error {
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

    if (headerLength > data.length - offset) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header extends beyond data"}];
        }
        return NO;
    }

    NSData *headerData = [data subdataWithRange:NSMakeRange(offset, headerLength)];
    offset += headerLength;

    // The CAR header is a DRISL object. Decoding it with the DAG-CBOR decoder
    // rather than the generic one gets canonical-form enforcement (minimal
    // lengths, sorted string keys, no trailing bytes, tag 42 only) and hands
    // back ATProtoCID objects directly.
    NSError *headerError = nil;
    id header = [ATProtoDagCBOR decodeData:headerData
                                    profile:ATProtoDRISLProfileDRISL
                                      error:&headerError];
    if (![header isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = headerError ?: [NSError errorWithDomain:@"com.atproto.car"
                                                        code:-10
                                                    userInfo:@{NSLocalizedDescriptionKey: @"CAR header is not a DRISL map"}];
        }
        return NO;
    }
    NSDictionary *headerMap = (NSDictionary *)header;

    id rootsValue = headerMap[@"roots"];
    if (![rootsValue isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header missing roots"}];
        }
        return NO;
    }

    NSArray *rootEntries = (NSArray *)rootsValue;
    NSMutableArray<ATProtoCID *> *parsedRoots = [NSMutableArray arrayWithCapacity:rootEntries.count];
    for (id rootEntry in rootEntries) {
        if (![rootEntry isKindOfClass:[ATProtoCID class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-10
                                         userInfo:@{NSLocalizedDescriptionKey: @"CAR header roots entry is not a CID tag"}];
            }
            return NO;
        }
        ATProtoCID *rootCID = (ATProtoCID *)rootEntry;
        if (strict && !rootCID.isDASLConformant) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-12
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR root %@ is not a DASL CID", rootCID.stringValue]}];
            }
            return NO;
        }
        [parsedRoots addObject:rootCID];
    }

    id versionValue = headerMap[@"version"];
    if (!CARIsIntegerOne(versionValue)) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported CAR version"}];
        }
        return NO;
    }

    _metadata = [headerMap copy];
    NSError *maslError = nil;
    ATProtoMASLDocument *maslDocument =
        [ATProtoMASLDocument documentWithObject:headerMap error:&maslError];
    if (maslDocument) {
        NSError *compatibilityError = nil;
        if (![maslDocument validateForCARWithError:&compatibilityError]) {
            if (error) *error = compatibilityError;
            return NO;
        }
        _maslDocument = maslDocument;
    }

    NSMutableArray<ATProtoCARBlock *> *blocks = [NSMutableArray array];
    NSMutableDictionary<NSString *, ATProtoCARBlock *> *index = [NSMutableDictionary dictionary];

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

        if (blockLen > data.length - offset) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-5
                                         userInfo:@{NSLocalizedDescriptionKey: @"CAR block extends beyond data"}];
            }
            return NO;
        }

        NSData *blockBytes = [data subdataWithRange:NSMakeRange(offset, (NSUInteger)blockLen)];
        offset += (NSUInteger)blockLen;

        ATProtoCID *blockCID = nil;
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

        if (strict) {
            if (!blockCID.isDASLConformant) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.car"
                                                 code:-7
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR block CID %@ is not a DASL CID", blockCID.stringValue]}];
                }
                return NO;
            }
            // Without this the ATProtoCID is just a label: a peer can ship any bytes
            // under any ATProtoCID and every downstream lookup silently trusts it.
            NSData *actualDigest = [ATProtoCID sha256Digest:blockData];
            NSData *statedDigest = [blockCID.multihash subdataWithRange:NSMakeRange(2, blockCID.multihash.length - 2)];
            if (![actualDigest isEqualToData:statedDigest]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.car"
                                                 code:-8
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR block %@ does not hash to its stated CID", blockCID.stringValue]}];
                }
                return NO;
            }
        }

        ATProtoCARBlock *block = [ATProtoCARBlock blockWithCID:blockCID data:blockData];
        [blocks addObject:block];
        index[blockCID.stringValue] = block;
    }

    if (strict) {
        // The spec allows verifying roots after the body has been read, which
        // is what this does — the body has to be indexed before the check can
        // be made at all.
        for (ATProtoCID *rootCID in parsedRoots) {
            if (!index[rootCID.stringValue]) {
                if (error) {
                    *error = [NSError errorWithDomain:@"com.atproto.car"
                                                 code:-9
                                             userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR root %@ is not present in the body", rootCID.stringValue]}];
                }
                return NO;
            }
        }
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

    ATProtoCID *rootCID = [ATProtoCID cidFromBytes:rootCidData];
    if (!rootCID) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse root CID"}];
        }
        return NO;
    }
    _roots = @[rootCID];

    NSMutableArray<ATProtoCARBlock *> *blocks = [NSMutableArray array];
    NSMutableDictionary<NSString *, ATProtoCARBlock *> *index = [NSMutableDictionary dictionary];

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

        ATProtoCID *blockCID = [self computeBlockCID:blockData];
        if (blockCID) {
            ATProtoCARBlock *block = [ATProtoCARBlock blockWithCID:blockCID data:blockData];
            [blocks addObject:block];
            index[blockCID.stringValue] = block;
        }
    }

    _blocks = [blocks copy];
    _blockIndex = [index copy];

    return YES;
}

- (ATProtoCID *)computeBlockCID:(NSData *)blockData {
    NSData *digest = [ATProtoCID sha256Digest:blockData];
    return [ATProtoCID cidWithDigest:digest codec:0x71];
}

- (ATProtoCARBlock *)blockWithCID:(ATProtoCID *)cid {
    return self.blockIndex[cid.stringValue];
}

- (ATProtoCARBlock *)blockForMASLPath:(NSString *)path error:(NSError **)error {
    if (!self.maslDocument || !self.maslDocument.isBundle) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-30
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"CAR header does not contain a MASL bundle"}];
        }
        return nil;
    }

    NSError *resourceError = nil;
    ATProtoCID *resourceCID = [self.maslDocument resourceCIDForPath:path
                                                                 error:&resourceError];
    if (!resourceCID) {
        if (error) *error = resourceError;
        return nil;
    }

    ATProtoCARBlock *block = [self blockWithCID:resourceCID];
    if (!block && error) {
        *error = [NSError errorWithDomain:@"com.atproto.car"
                                     code:-31
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:
                                                    @"MASL resource %@ references a CID absent from the CAR body",
                                                    path ?: @"(null)"]}];
    }
    return block;
}

@end

#pragma mark - ATProtoCARStreamReader Implementation

@interface ATProtoCARStreamReader ()

@property (nonatomic, copy, readwrite, nullable) NSArray<ATProtoCID *> *roots;
@property (nonatomic, copy, readwrite, nullable) NSDictionary *metadata;
@property (nonatomic, strong, readwrite, nullable) ATProtoMASLDocument *maslDocument;
@property (nonatomic, strong, nullable) NSData *data;
@property (nonatomic, assign) NSUInteger bodyOffset;
@property (nonatomic, assign) NSUInteger offset;
@property (nonatomic, assign) BOOL strict;
@property (nonatomic, assign, readwrite) BOOL isFinished;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ATProtoCARBlock *> *blockIndex;

- (BOOL)parseHeaderWithError:(NSError **)error;
- (BOOL)verifyRootsPresentWithError:(NSError **)error;

@end

@implementation ATProtoCARStreamReader

- (nullable instancetype)initWithData:(NSData *)data
                               strict:(BOOL)strict
                                error:(NSError **)error {
    self = [super init];
    if (self) {
        _data = data;
        _strict = strict;
        _offset = 0;
        _isFinished = NO;
        _blockIndex = [NSMutableDictionary dictionary];
        if (![self parseHeaderWithError:error]) {
            return nil;
        }
    }
    return self;
}

- (ATProtoCID *)rootCID {
    return self.roots.firstObject;
}

- (BOOL)parseHeaderWithError:(NSError **)error {
    if (self.data.length < 2) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Data too short for CAR header"}];
        }
        return NO;
    }

    const uint8_t *bytes = self.data.bytes;
    NSUInteger offset = 0;
    uint64_t headerLength = 0;
    NSUInteger headerSize = ReadVarint(bytes + offset, self.data.length - offset, &headerLength);
    if (headerSize == 0 || headerLength == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR block length"}];
        }
        return NO;
    }
    offset += headerSize;

    if (headerLength > self.data.length - offset) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header extends beyond data"}];
        }
        return NO;
    }

    NSData *headerData = [self.data subdataWithRange:NSMakeRange(offset, (NSUInteger)headerLength)];
    offset += (NSUInteger)headerLength;

    NSError *headerError = nil;
    id header = [ATProtoDagCBOR decodeData:headerData
                                    profile:ATProtoDRISLProfileDRISL
                                      error:&headerError];
    if (![header isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = headerError ?: [NSError errorWithDomain:@"com.atproto.car"
                                                        code:-10
                                                    userInfo:@{NSLocalizedDescriptionKey: @"CAR header is not a DRISL map"}];
        }
        return NO;
    }
    NSDictionary *headerMap = (NSDictionary *)header;

    id rootsValue = headerMap[@"roots"];
    if (![rootsValue isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR header missing roots"}];
        }
        return NO;
    }

    NSArray *rootEntries = (NSArray *)rootsValue;
    NSMutableArray<ATProtoCID *> *parsedRoots = [NSMutableArray arrayWithCapacity:rootEntries.count];
    for (id rootEntry in rootEntries) {
        if (![rootEntry isKindOfClass:[ATProtoCID class]]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-10
                                         userInfo:@{NSLocalizedDescriptionKey: @"CAR header roots entry is not a CID tag"}];
            }
            return NO;
        }
        ATProtoCID *rootCID = (ATProtoCID *)rootEntry;
        if (self.strict && !rootCID.isDASLConformant) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-12
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR root %@ is not a DASL CID", rootCID.stringValue]}];
            }
            return NO;
        }
        [parsedRoots addObject:rootCID];
    }

    id versionValue = headerMap[@"version"];
    if (!CARIsIntegerOne(versionValue)) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported CAR version"}];
        }
        return NO;
    }

    _metadata = [headerMap copy];
    NSError *maslError = nil;
    ATProtoMASLDocument *maslDocument =
        [ATProtoMASLDocument documentWithObject:headerMap error:&maslError];
    if (maslDocument) {
        NSError *compatibilityError = nil;
        if (![maslDocument validateForCARWithError:&compatibilityError]) {
            if (error) *error = compatibilityError;
            return NO;
        }
        _maslDocument = maslDocument;
    }

    _roots = [parsedRoots copy];
    _bodyOffset = offset;
    _offset = offset;
    return YES;
}

- (BOOL)verifyRootsPresentWithError:(NSError **)error {
    for (ATProtoCID *rootCID in self.roots) {
        if (!self.blockIndex[rootCID.stringValue]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-9
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR root %@ is not present in the body", rootCID.stringValue]}];
            }
            return NO;
        }
    }
    return YES;
}

- (nullable ATProtoCARBlock *)nextBlockWithError:(NSError **)error {
    if (self.isFinished) {
        return nil;
    }

    NSUInteger offset = self.offset;
    if (offset >= self.data.length) {
        self.isFinished = YES;
        if (self.strict && ![self verifyRootsPresentWithError:error]) {
            return nil;
        }
        return nil;
    }

    const uint8_t *bytes = self.data.bytes;
    uint64_t blockLen = 0;
    NSUInteger blockSize = ReadVarint(bytes + offset, self.data.length - offset, &blockLen);
    if (blockSize == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-4
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid CAR block length"}];
        }
        return nil;
    }
    offset += blockSize;

    if (blockLen > self.data.length - offset) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-5
                                     userInfo:@{NSLocalizedDescriptionKey: @"CAR block extends beyond data"}];
        }
        return nil;
    }

    NSData *blockBytes = [self.data subdataWithRange:NSMakeRange(offset, (NSUInteger)blockLen)];
    offset += (NSUInteger)blockLen;

    ATProtoCID *blockCID = nil;
    NSUInteger cidLength = 0;
    if (!DecodeCIDFromBlock(blockBytes.bytes, blockBytes.length, &blockCID, &cidLength)) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-6
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse CID from CAR block"}];
        }
        return nil;
    }

    NSData *blockData = [blockBytes subdataWithRange:NSMakeRange(cidLength, blockBytes.length - cidLength)];

    if (self.strict) {
        if (!blockCID.isDASLConformant) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-7
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR block CID %@ is not a DASL CID", blockCID.stringValue]}];
            }
            return nil;
        }
        // Without this the ATProtoCID is just a label: a peer can ship any bytes
        // under any ATProtoCID and every downstream lookup silently trusts it.
        NSData *actualDigest = [ATProtoCID sha256Digest:blockData];
        NSData *statedDigest = [blockCID.multihash subdataWithRange:NSMakeRange(2, blockCID.multihash.length - 2)];
        if (![actualDigest isEqualToData:statedDigest]) {
            if (error) {
                *error = [NSError errorWithDomain:@"com.atproto.car"
                                             code:-8
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"CAR block %@ does not hash to its stated CID", blockCID.stringValue]}];
            }
            return nil;
        }
    }

    self.offset = offset;
    ATProtoCARBlock *block = [ATProtoCARBlock blockWithCID:blockCID data:blockData];
    self.blockIndex[blockCID.stringValue] = block;
    return block;
}

- (BOOL)enumerateBlocksWithError:(NSError **)error
                         handler:(BOOL (^)(ATProtoCARBlock *block, NSError **stopError))handler {
    while (YES) {
        NSError *blockError = nil;
        ATProtoCARBlock *block = [self nextBlockWithError:&blockError];
        if (blockError) {
            if (error) *error = blockError;
            return NO;
        }
        if (!block) {
            // Exhausted; in strict mode nextBlockWithError already verified
            // that every declared root is present in the body.
            return YES;
        }
        NSError *stopError = nil;
        BOOL continueStreaming = handler(block, &stopError);
        if (!continueStreaming) {
            if (stopError) {
                if (error) *error = stopError;
                return NO;
            }
            return YES;
        }
    }
}

- (ATProtoCARBlock *)blockWithCID:(ATProtoCID *)cid {
    return self.blockIndex[cid.stringValue];
}

- (void)reset {
    self.offset = self.bodyOffset;
    self.isFinished = NO;
    [self.blockIndex removeAllObjects];
}

@end

#pragma mark - ATProtoCARWriter Implementation

@interface ATProtoCARWriter ()

@property (nonatomic, strong, readwrite, nullable) ATProtoCID *rootCID;
@property (nonatomic, strong, readwrite, nullable) ATProtoMASLDocument *maslDocument;
@property (nonatomic, strong, readwrite) NSMutableArray<ATProtoCARBlock *> *blocks;

@end

@implementation ATProtoCARWriter

+ (instancetype)writerWithRootCID:(ATProtoCID *)rootCID {
    return [[self alloc] initWithRootCID:rootCID];
}

+ (nullable instancetype)writerWithMASLDocument:(ATProtoMASLDocument *)document
                                           error:(NSError **)error {
    if (!document) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-27
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"A MASL document is required for CAR metadata"}];
        }
        return nil;
    }

    NSError *compatibilityError = nil;
    id version = document.object[@"version"];
    id roots = document.object[@"roots"];
    if (!version || !roots || ![document validateForCARWithError:&compatibilityError]) {
        if (error) {
            *error = compatibilityError ?: [NSError errorWithDomain:@"com.atproto.car"
                                                                     code:-28
                                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                                                @"MASL CAR metadata requires version 1 and a roots array"}];
        }
        return nil;
    }

    ATProtoCID *rootCID = [document.object[@"roots"] firstObject];
    ATProtoCARWriter *writer = [[self alloc] initWithRootCID:rootCID];
    writer.maslDocument = document;
    return writer;
}

- (instancetype)init {
    return [self initWithRootCID:nil];
}

- (instancetype)initWithRootCID:(ATProtoCID * _Nullable)rootCID {
    self = [super init];
    if (self) {
        _rootCID = rootCID;
        _blocks = [NSMutableArray array];
    }
    return self;
}

- (void)addBlock:(ATProtoCARBlock *)block {
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

static NSData *CARHeaderDataForRootCID(ATProtoCID *rootCID) {
    if (!rootCID) {
        return nil;
    }

    NSMutableData *taggedCIDBytes = [NSMutableData dataWithCapacity:1 + rootCID.bytes.length];
    uint8_t marker = 0x00;
    [taggedCIDBytes appendBytes:&marker length:1];
    [taggedCIDBytes appendData:rootCID.bytes];

    ATProtoCBORValue *rootsArray = [ATProtoCBORValue array:@[
        [ATProtoCBORValue tag:42 value:[ATProtoCBORValue byteString:taggedCIDBytes]]
    ]];

    ATProtoCBORValue *headerMap = [ATProtoCBORValue map:@{
        [ATProtoCBORValue textString:@"roots"]: rootsArray,
        [ATProtoCBORValue textString:@"version"]: [ATProtoCBORValue unsignedInteger:1]
    }];

    NSData *headerCBOR = [headerMap encode];
    uint8_t headerLenBuffer[16];
    NSUInteger headerLenSize = WriteVarint(headerCBOR.length, headerLenBuffer);

    NSMutableData *encodedHeader = [NSMutableData dataWithCapacity:headerLenSize + headerCBOR.length];
    [encodedHeader appendBytes:headerLenBuffer length:headerLenSize];
    [encodedHeader appendData:headerCBOR];
    return [encodedHeader copy];
}

static NSData *CARHeaderDataForMASLDocument(ATProtoMASLDocument *document,
                                            NSError **error) {
    if (!document) return nil;

    NSError *compatibilityError = nil;
    id version = document.object[@"version"];
    id roots = document.object[@"roots"];
    if (!version || !roots || ![document validateForCARWithError:&compatibilityError]) {
        if (error) {
            *error = compatibilityError ?: [NSError errorWithDomain:@"com.atproto.car"
                                                                     code:-28
                                                                 userInfo:@{NSLocalizedDescriptionKey:
                                                                                @"MASL CAR metadata requires version 1 and a roots array"}];
        }
        return nil;
    }

    NSError *encodeError = nil;
    NSData *headerCBOR = [document DRISLDataWithError:&encodeError];
    if (!headerCBOR) {
        if (error) *error = encodeError;
        return nil;
    }

    uint8_t headerLenBuffer[16];
    NSUInteger headerLenSize = WriteVarint(headerCBOR.length, headerLenBuffer);
    NSMutableData *encodedHeader = [NSMutableData dataWithCapacity:headerLenSize + headerCBOR.length];
    [encodedHeader appendBytes:headerLenBuffer length:headerLenSize];
    [encodedHeader appendData:headerCBOR];
    return [encodedHeader copy];
}

static NSData *CARBlockEntryData(ATProtoCARBlock *block) {
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

    NSData *headerData = self.maslDocument
        ? CARHeaderDataForMASLDocument(self.maslDocument, nil)
        : CARHeaderDataForRootCID(self.rootCID);
    if (!headerData) {
        return nil;
    }
    [data appendData:headerData];

    for (ATProtoCARBlock *block in self.blocks) {
        NSData *entry = CARBlockEntryData(block);
        if (!entry) {
            continue;
        }
        [data appendData:entry];
    }

    return [data copy];
}

+ (nullable NSData *)encodedHeaderWithRootCID:(ATProtoCID *)rootCID error:(NSError **)error {
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

+ (nullable NSData *)encodedHeaderWithMASLDocument:(ATProtoMASLDocument *)document
                                              error:(NSError **)error {
    return CARHeaderDataForMASLDocument(document, error);
}

+ (nullable NSData *)encodedBlock:(ATProtoCARBlock *)block error:(NSError **)error {
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

+ (BOOL)writeHeaderWithRootCID:(ATProtoCID *)rootCID
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

+ (BOOL)writeHeaderWithMASLDocument:(ATProtoMASLDocument *)document
                       toFileHandle:(NSFileHandle *)fileHandle
                              error:(NSError **)error {
    NSData *headerData = [[self class] encodedHeaderWithMASLDocument:document error:error];
    if (!headerData || !fileHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"com.atproto.car"
                                         code:-21
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Invalid CAR MASL header write parameters"}];
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
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    exception.reason ?: @"Failed to write CAR MASL header"}];
        }
        return NO;
    }
}

+ (BOOL)writeBlock:(ATProtoCARBlock *)block
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
        BOOL wroteHeader = self.maslDocument
            ? [[self class] writeHeaderWithMASLDocument:self.maslDocument toFileHandle:fileHandle error:&writeError]
            : [[self class] writeHeaderWithRootCID:self.rootCID toFileHandle:fileHandle error:&writeError];
        if (!wroteHeader) {
            if (error) *error = writeError;
            [fileHandle closeFile];
            return NO;
        }

        for (ATProtoCARBlock *block in self.blocks) {
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
