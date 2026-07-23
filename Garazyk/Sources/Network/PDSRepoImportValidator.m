// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import "Network/PDSRepoImportValidator.h"
#import "Network/XrpcRepoPack_Internal.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"
#import "Repository/RepoCommit.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/DID.h"
#import "Core/CID.h"
#import "Database/PDSDatabase.h"
#import "Database/PDSDatabaseAccount.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"

static const NSUInteger kPDSImportRepoMaxBodyBytes = 16 * 1024 * 1024;
static const NSUInteger kPDSImportRepoMaxCARBlocks = 100000;
static const NSUInteger kPDSImportRepoMaxMSTNodes = 100000;
static const NSUInteger kPDSImportRepoMaxRecords = 100000;
static const NSUInteger kPDSImportRepoMaxMSTDepth = 512;

static CID *cidFromTaggedCBORValue(CBORValue *value) {
    if (!value) {
        return nil;
    }

    if (value.type == CBORTypeSimpleOrFloat &&
        value.simpleValue &&
        value.simpleValue.unsignedIntegerValue == 22) {
        return nil;
    }

    if (value.type != CBORTypeTag || !value.tagValue || value.tagValue.type != CBORTypeByteString) {
        return nil;
    }

    NSData *bytes = value.tagValue.byteString;
    if (!bytes || bytes.length <= 1) {
        return nil;
    }

    NSData *cidBytes = [bytes subdataWithRange:NSMakeRange(1, bytes.length - 1)];
    return [CID cidFromBytes:cidBytes];
}

static NSData *publicKeyFromDIDKeyString(NSString *didKey) {
    NSString *multibase = didKey;
    if ([didKey hasPrefix:@"did:key:"]) {
        multibase = [didKey substringFromIndex:8];
    }
    if (![multibase hasPrefix:@"z"]) {
        return nil;
    }
    NSData *decoded = [CID base58btcDecode:[multibase substringFromIndex:1]];
    if (decoded.length != 35) {
        return nil;
    }
    const uint8_t *bytes = decoded.bytes;
    if (bytes[0] != 0xe7 || bytes[1] != 0x01) {
        return nil;
    }
    return [decoded subdataWithRange:NSMakeRange(2, 33)];
}

static NSData *atprotoSigningKeyFromDIDDocument(DIDDocument *document) {
    NSDictionary *json = document.jsonDictionary;
    id verificationMethods = json[@"verificationMethods"];
    if ([verificationMethods isKindOfClass:[NSDictionary class]]) {
        NSData *key = publicKeyFromDIDKeyString(((NSDictionary *)verificationMethods)[@"atproto"]);
        if (key) return key;
    }

    id verificationMethod = json[@"verificationMethod"];
    if ([verificationMethod isKindOfClass:[NSArray class]]) {
        for (id entry in (NSArray *)verificationMethod) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *method = (NSDictionary *)entry;
            NSString *methodID = [method[@"id"] isKindOfClass:[NSString class]] ? method[@"id"] : @"";
            if (![methodID hasSuffix:@"#atproto"]) continue;
            NSData *key = publicKeyFromDIDKeyString(method[@"publicKeyMultibase"]);
            if (key) return key;
        }
    }
    return nil;
}

@implementation PDSRepoImportValidator

+ (BOOL)validateCommitSignature:(RepoCommit *)commit did:(NSString *)did databasePool:(PDSDatabasePool *)databasePool allowLocalKeyFallback:(BOOL)allowLocalKeyFallback error:(NSError **)error {
    NSError *resolveError = nil;
    DIDDocument *document = [[DIDResolver sharedResolver] resolveDIDSync:did error:&resolveError];
    NSMutableArray<NSData *> *candidateKeys = [NSMutableArray array];
    NSData *didDocKey = atprotoSigningKeyFromDIDDocument(document);
    if (didDocKey) {
        [candidateKeys addObject:didDocKey];
    }

    if (allowLocalKeyFallback) {
        NSError *storeError = nil;
        PDSActorStore *store = [databasePool storeForDid:did error:&storeError];
        NSData *localPublicKey = [store publicSigningKeyWithError:nil];
        if (localPublicKey) {
            [candidateKeys addObject:localPublicKey];
        }
    }

    for (NSData *publicKey in candidateKeys) {
        if ([commit verifySignatureWithPublicKey:publicKey error:nil]) {
            return YES;
        }
    }

    if (error) {
        NSString *message = resolveError
            ? [NSString stringWithFormat:@"Commit signature verification failed and DID document could not be resolved: %@", resolveError.localizedDescription]
            : @"Commit signature did not verify against the DID atproto signing key";
        *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, message);
    }
    return NO;
}

+ (nullable NSArray<PDSDatabaseRecord *> *)extractRecordsFromMSTRoot:(CID *)rootCID
                                                                 did:(NSString *)did
                                                              reader:(CARReader *)reader
                                                                 rev:(NSString *)rev
                                                               error:(NSError **)error {
    if (!rootCID) {
        return @[];
    }

    NSMutableArray<PDSDatabaseRecord *> *records = [NSMutableArray array];
    NSMutableSet<NSString *> *visitedCIDs = [NSMutableSet set];
    NSMutableArray<NSDictionary *> *stack = [NSMutableArray arrayWithObject:@{
        @"cid": rootCID,
        @"prevKey": @"",
        @"depth": @0,
    }];
    NSUInteger nodeCount = 0;

    while (stack.count > 0) {
        NSDictionary *frame = stack.lastObject;
        [stack removeLastObject];

        CID *nodeCID = frame[@"cid"];
        NSString *prevKey = frame[@"prevKey"] ?: @"";
        NSUInteger depth = [frame[@"depth"] unsignedIntegerValue];
        if (depth > kPDSImportRepoMaxMSTDepth) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Imported MST exceeds maximum depth");
            return nil;
        }

        NSString *nodeKey = nodeCID.stringValue ?: @"";
        if ([visitedCIDs containsObject:nodeKey]) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST contains a cycle");
            return nil;
        }
        [visitedCIDs addObject:nodeKey];

        nodeCount += 1;
        if (nodeCount > kPDSImportRepoMaxMSTNodes) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Imported MST has too many nodes");
            return nil;
        }

        CARBlock *block = [reader blockWithCID:nodeCID];
        if (!block) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST references a missing block");
            return nil;
        }

        CBORValue *nodeValue = [CBORValue decode:block.data];
        if (!nodeValue || nodeValue.type != CBORTypeMap) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST node is invalid");
            return nil;
        }

        NSMutableArray<NSDictionary *> *childFrames = [NSMutableArray array];
        CBORValue *leftTag = nodeValue.map[[CBORValue textString:@"l"]];
        CID *leftCID = cidFromTaggedCBORValue(leftTag);
        if (leftCID) {
            [childFrames addObject:@{@"cid": leftCID, @"prevKey": prevKey, @"depth": @(depth + 1)}];
        }

        CBORValue *entriesValue = nodeValue.map[[CBORValue textString:@"e"]];
        NSArray<CBORValue *> *entriesArray = (entriesValue && entriesValue.type == CBORTypeArray) ? entriesValue.array : @[];
        NSString *currentPrevKey = prevKey;

        for (CBORValue *entryMap in entriesArray) {
            if (entryMap.type != CBORTypeMap) continue;

            NSData *suffixData = entryMap.map[[CBORValue textString:@"k"]].byteString ?: [NSData data];
            CBORValue *prefixValue = entryMap.map[[CBORValue textString:@"p"]];
            NSUInteger prefixLen = prefixValue.unsignedInteger.unsignedIntegerValue;
            NSUInteger safePrefixLen = MIN(prefixLen, currentPrevKey.length);
            NSString *prefix = [currentPrevKey substringToIndex:safePrefixLen];
            NSString *suffix = [[NSString alloc] initWithData:suffixData encoding:NSUTF8StringEncoding] ?: @"";
            NSString *fullKey = [prefix stringByAppendingString:suffix];

            CID *valueCID = cidFromTaggedCBORValue(entryMap.map[[CBORValue textString:@"v"]]);
            if (valueCID) {
                CARBlock *valueBlock = [reader blockWithCID:valueCID];
                if (!valueBlock) {
                    if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Imported MST references a missing record block");
                    return nil;
                }

                PDSDatabaseRecord *record = [[PDSDatabaseRecord alloc] init];
                record.did = did;
                record.cid = valueCID.stringValue;
                record.rev = rev;
                record.createdAt = [NSDate date];

                NSRange slashRange = [fullKey rangeOfString:@"/"];
                if (slashRange.location != NSNotFound) {
                    record.collection = [fullKey substringToIndex:slashRange.location];
                    record.rkey = [fullKey substringFromIndex:slashRange.location + 1];
                } else {
                    record.collection = @"unknown";
                    record.rkey = fullKey;
                }
                record.uri = [NSString stringWithFormat:@"at://%@/%@/%@", did, record.collection, record.rkey];

                id jsonObj = [ATProtoCBORSerialization JSONObjectWithData:valueBlock.data error:nil];
                if (jsonObj) {
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:jsonObj options:0 error:nil];
                    if (jsonData) {
                        record.value = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
                    }
                }

                [records addObject:record];
                if (records.count > kPDSImportRepoMaxRecords) {
                    if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Imported repository has too many records");
                    return nil;
                }
            }

            CID *treeCID = cidFromTaggedCBORValue(entryMap.map[[CBORValue textString:@"t"]]);
            if (treeCID) {
                [childFrames addObject:@{@"cid": treeCID, @"prevKey": fullKey, @"depth": @(depth + 1)}];
            }

            currentPrevKey = fullKey;
        }

        for (NSDictionary *childFrame in [childFrames reverseObjectEnumerator]) {
            [stack addObject:childFrame];
        }
    }

    return [records copy];
}

+ (nullable PDSRepoImportValidationResult *)validateCARData:(NSData *)carData
                                                     reader:(CARReader *)reader
                                                     commit:(RepoCommit *)commit
                                                        did:(NSString *)did
                                              databasePool:(PDSDatabasePool *)databasePool
                                     allowLocalKeyFallback:(BOOL)allowLocalKeyFallback
                                                      error:(NSError **)error {
    if (carData.length > kPDSImportRepoMaxBodyBytes) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Repository import body too large");
        return nil;
    }
    if (reader.blocks.count > kPDSImportRepoMaxCARBlocks) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorPayloadTooLarge, @"Repository import has too many CAR blocks");
        return nil;
    }

    CID *computedCommitCID = [commit computeCID];
    if (!computedCommitCID || ![computedCommitCID isEqualToCID:reader.rootCID]) {
        if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"Commit CID does not match CAR root");
        return nil;
    }

    for (CARBlock *block in reader.blocks) {
        CID *computed = [CID cidWithDigest:[CID sha256Digest:block.data] codec:block.cid.codec];
        if (!computed || ![computed isEqualToCID:block.cid]) {
            if (error) *error = repoPackValidationError(PDSRepoPackValidationErrorInvalidRequest, @"CAR block CID does not match block data");
            return nil;
        }
    }

    if (![self validateCommitSignature:commit did:did databasePool:databasePool allowLocalKeyFallback:allowLocalKeyFallback error:error]) {
        return nil;
    }

    NSArray<PDSDatabaseRecord *> *records = [self extractRecordsFromMSTRoot:commit.dataCID
                                                                        did:did
                                                                     reader:reader
                                                                        rev:commit.rev ?: @""
                                                                      error:error];
    if (!records) {
        return nil;
    }

    NSMutableArray<PDSDatabaseBlock *> *blocks = [NSMutableArray arrayWithCapacity:reader.blocks.count];
    for (CARBlock *block in reader.blocks) {
        PDSDatabaseBlock *dbBlock = [[PDSDatabaseBlock alloc] init];
        dbBlock.cid = block.cid.bytes;
        dbBlock.blockData = block.data;
        dbBlock.size = (NSInteger)block.data.length;
        dbBlock.rev = commit.rev ?: @"";
        [blocks addObject:dbBlock];
    }

    PDSRepoImportValidationResult *result = [[PDSRepoImportValidationResult alloc] init];
    result.blocks = [blocks copy];
    result.records = records;
    return result;
}

@end
