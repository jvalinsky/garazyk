// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
/*!
 @file ATProtoMASLDocument.h

 @abstract Validated MASL metadata documents.

 @discussion MASL (https://dasl.ing/masl.html) places a DRISL object between
 a content ATProtoCID and its resource. This model validates the structural fields
 that have defined meaning while retaining arbitrary application metadata in
 the original object. It deliberately does not make HTTP-header projection
 implicit: callers must request the filtered, path-aware allow-list view.
 */

#import <Foundation/Foundation.h>

@class ATProtoCID;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ATProtoMASLErrorDomain;

typedef NS_ENUM(NSInteger, ATProtoMASLErrorCode) {
    ATProtoMASLErrorInvalidDocument = 1,
    ATProtoMASLErrorInvalidField = 2,
    ATProtoMASLErrorInvalidResourcePath = 3,
    ATProtoMASLErrorInvalidResource = 4,
    ATProtoMASLErrorInvalidReference = 5,
    ATProtoMASLErrorNotCARCompatible = 6,
};

/**
 A validated MASL metadata object.

 `object` contains the complete decoded DRISL map, including application
 namespaces and fields this model does not interpret. In bundle mode,
 `resources` contains the original per-path metadata objects.
 */
@interface ATProtoMASLDocument : NSObject

/** The complete MASL object, copied at construction. */
@property (nonatomic, copy, readonly) NSDictionary *object;
/** YES when the document has a `resources` map. */
@property (nonatomic, assign, readonly, getter=isBundle) BOOL bundle;
/** The root `src` ATProtoCID, when present. In bundle mode MASL processing ignores it. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *src;
/** The root `prev` ATProtoCID, when present. */
@property (nonatomic, strong, readonly, nullable) ATProtoCID *prev;
/** The original bundle resource metadata, or nil in single mode. */
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, NSDictionary *> *resources;

/** Validates and constructs a document from a decoded DRISL object. */
+ (nullable instancetype)documentWithObject:(id)object error:(NSError **)error;

/** Decodes, validates, and constructs a document from DRISL bytes. */
+ (nullable instancetype)documentWithDRISLData:(NSData *)data error:(NSError **)error;

/** Encodes the complete object with the DRISL profile. */
- (nullable NSData *)DRISLDataWithError:(NSError **)error;

/**
 Returns the resource CID for an exact bundle path.

 Query strings and fragments are ignored when resolving a bundle path, as
 required by MASL. Single-mode documents do not expose a bundle resource map.
 */
- (nullable ATProtoCID *)resourceCIDForPath:(NSString *)path error:(NSError **)error;

/**
 Validates the optional CAR compatibility fields.

 A MASL document used as CAR header metadata must contain `version` equal to
 integer 1 and `roots` as an array containing only ATProtoCID links. Generic MASL
 documents may omit both fields.
 */
- (BOOL)validateForCARWithError:(NSError **)error;

/**
 Returns the safe HTTP headers for a resource.

 In single mode, `path` is ignored and headers are read from the root object.
 In bundle mode, headers are read only from the exact resource path; root-level
 HTTP fields are ignored. Only MASL's lower-case allow-list is returned.
 `sourcemap` and `speculation-rules` are returned only when they name an exact
 path present in the bundle. Unknown and differently-cased fields are omitted.
 */
- (nullable NSDictionary<NSString *, NSString *> *)httpHeadersForPath:(nullable NSString *)path
                                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
