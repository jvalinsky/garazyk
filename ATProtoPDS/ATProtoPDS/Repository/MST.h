#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CID;
@class MSTNode;
@class MSTEntry;

typedef NS_ENUM(NSUInteger, MSTNodeKind) {
    MSTNodeKindLeaf,
    MSTNodeKindNonLeaf
};

@interface MSTEntry : NSObject <NSCopying>

@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, strong, readonly) CID *valueCID;
@property (nonatomic, copy, readonly, nullable) NSString *subKey;

+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID;
+ (instancetype)entryWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

- (instancetype)initWithKey:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

- (NSData *)keyBytes;
- (NSUInteger)keyLength;
- (NSData *)serialize;

@end

@interface MSTNodeEntry : NSObject

@property (nonatomic, assign) NSUInteger prefixLen;
@property (nonatomic, copy) NSData *keySuffix;
@property (nonatomic, strong) CID *value;
@property (nonatomic, strong, nullable) CID *tree;

+ (instancetype)entryWithPrefixLen:(NSUInteger)prefixLen
                         keySuffix:(NSData *)keySuffix
                             value:(CID *)value
                             tree:(nullable CID *)tree;

- (NSData *)serialize;

@end

@interface MSTNode : NSObject

@property (nonatomic, assign, readonly) MSTNodeKind kind;
@property (nonatomic, strong, readonly, nullable) CID *nodeHash;
@property (nonatomic, copy, readonly) NSArray<MSTNodeEntry *> *entries;
@property (nonatomic, strong, readonly, nullable) CID *left;

+ (instancetype)leafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries;
+ (instancetype)nonLeafNodeWithEntries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

- (instancetype)initWithKind:(MSTNodeKind)kind entries:(NSArray<MSTNodeEntry *> *)entries left:(nullable CID *)left;

- (NSData *)serialize;
- (NSData *)computeHash;
- (void)setNodeHash:(CID *)hash;

- (NSArray<MSTEntry *> *)fullEntries;

@end

@interface MST : NSObject

@property (nonatomic, strong, readonly, nullable) CID *rootCID;
@property (nonatomic, strong, readonly) NSData *emptyTreeHash;

- (instancetype)initWithRootCID:(nullable CID *)rootCID;

- (nullable CID *)get:(NSString *)key;
- (nullable CID *)get:(NSString *)key subKey:(nullable NSString *)subKey;

- (void)put:(NSString *)key valueCID:(CID *)valueCID;
- (void)put:(NSString *)key valueCID:(CID *)valueCID subKey:(nullable NSString *)subKey;

- (void)delete:(NSString *)key;
- (void)delete:(NSString *)key subKey:(nullable NSString *)subKey;

- (NSArray<MSTEntry *> *)allEntries;
- (NSArray<MSTEntry *> *)entriesWithPrefix:(NSString *)prefix;

- (NSData *)exportCAR;

- (NSData *)serializeToCBOR;
+ (nullable instancetype)deserializeFromCBOR:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
