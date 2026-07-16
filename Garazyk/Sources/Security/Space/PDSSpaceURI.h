// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const PDSSpaceURIErrorDomain;

typedef NS_ENUM(NSInteger, PDSSpaceURIError) {
  PDSSpaceURIErrorInvalidFormat = 1,
  PDSSpaceURIErrorInvalidIdentifier,
};

/** Structured form of an experimental permissioned-space URI. */
@interface PDSSpaceURI : NSObject

@property(nonatomic, readonly, copy) NSString *authorityDID;
@property(nonatomic, readonly, copy) NSString *spaceType;
@property(nonatomic, readonly, copy) NSString *skey;
@property(nonatomic, readonly, copy, nullable) NSString *authorDID;
@property(nonatomic, readonly, copy, nullable) NSString *collection;
@property(nonatomic, readonly, copy, nullable) NSString *rkey;
@property(nonatomic, readonly, copy) NSString *spaceURI;
@property(nonatomic, readonly, copy) NSString *URIString;
@property(nonatomic, readonly, getter=isRecordURI) BOOL recordURI;

+ (nullable instancetype)URIWithString:(NSString *)URIString error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
