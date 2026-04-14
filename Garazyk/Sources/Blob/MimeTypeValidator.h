/*!
 @file MimeTypeValidator.h

 @abstract MIME type validation and categorization for blob storage.

 @discussion Validates MIME types for blob uploads, enforces size limits by
 category, and provides magic number verification to prevent type spoofing.
 Supports ATProto-specific types and standard web formats.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*! Error domain for MIME type validation. */
extern NSString * const MimeTypeErrorDomain;

/*!
 @enum MimeTypeError

 @abstract Error codes for MIME validation.

 @constant MimeTypeErrorInvalidFormat MIME type format is invalid.
 @constant MimeTypeErrorUnsupported MIME type not supported.
 @constant MimeTypeErrorTooLarge File exceeds category size limit.
 @constant MimeTypeErrorMagicNumberMismatch Magic numbers don't match claimed type.
 @constant MimeTypeErrorMalformed MIME type string is malformed.
 */
typedef NS_ENUM(NSInteger, MimeTypeError) {
    MimeTypeErrorInvalidFormat = 1000,
    MimeTypeErrorUnsupported,
    MimeTypeErrorTooLarge,
    MimeTypeErrorMagicNumberMismatch,
    MimeTypeErrorMalformed
};

/*!
 @enum MimeCategory

 @abstract MIME type categories with distinct size limits.

 @constant MimeCategoryImage Image types (PNG, JPEG, GIF, WebP).
 @constant MimeCategoryVideo Video types (MP4, WebM, MOV).
 @constant MimeCategoryAudio Audio types (MP3, AAC, WAV, FLAC).
 @constant MimeCategoryText Text types (plain, HTML, Markdown).
 @constant MimeCategoryFont Font types (WOFF, WOFF2, TTF).
 @constant MimeCategoryModel 3D model types (GLTF, GLB, USDZ).
 @constant MimeCategoryApplication Application types (PDF, JSON).
 @constant MimeCategoryOther Uncategorized types.
 */
typedef NS_ENUM(NSInteger, MimeCategory) {
    MimeCategoryImage,
    MimeCategoryVideo,
    MimeCategoryAudio,
    MimeCategoryText,
    MimeCategoryFont,
    MimeCategoryModel,
    MimeCategoryApplication,
    MimeCategoryOther
};

/*!
 @class MimeTypeValidator

 @abstract Validates MIME types for blob uploads.

 @discussion Enforces ATProto blob type restrictions:
 - Images: 5MB limit (PNG, JPEG, GIF, WebP)
 - Videos: 50MB limit (MP4, WebM, MOV)
 - Audio: 25MB limit (MP3, AAC, WAV, FLAC)
 - Magic number verification prevents type spoofing

 Thread-safety: Immutable configuration, safe for concurrent access.
 */
@interface MimeTypeValidator : NSObject

/*! Get singleton validator instance. */
@property (class, readonly) MimeTypeValidator *sharedValidator;

/*! Size limits by category (bytes). */
@property (nonatomic, readonly) NSDictionary<NSNumber *, NSNumber *> *maxSizesByCategory;

/*! Supported image MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *supportedImageTypes;

/*! Supported video MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *supportedVideoTypes;

/*! Supported audio MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *supportedAudioTypes;

/*! Supported font MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *supportedFontTypes;

/*! Supported 3D model MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *supportedModelTypes;

/*! Supported document MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *supportedDocumentTypes;

/*! ATProto-specific MIME types. */
@property (nonatomic, readonly) NSSet<NSString *> *atprotoSpecificTypes;

/*! Validate MIME type format. */
- (BOOL)isValidMimeType:(NSString *)mimeType error:(NSError **)error;

/*! Check if MIME type is supported. */
- (BOOL)isSupportedMimeType:(NSString *)mimeType error:(NSError **)error;

/*! Get category for MIME type. */
- (MimeCategory)categoryForMimeType:(NSString *)mimeType;

/*! Get string name for category. */
- (NSString *)stringForCategory:(MimeCategory)category;

/*! Validate file size against category limit. */
- (BOOL)validateSize:(NSUInteger)fileSize forMimeType:(NSString *)mimeType error:(NSError **)error;

/*! Get maximum size for MIME type. */
- (NSUInteger)maxSizeForMimeType:(NSString *)mimeType;

/*! Normalize MIME type (lowercase, trim). */
- (nullable NSString *)normalizeMimeType:(NSString *)mimeType;

/*! Get file extension for MIME type. */
- (nullable NSString *)fileExtensionForMimeType:(NSString *)mimeType;

/*! Get MIME type for file extension. */
- (nullable NSString *)mimeTypeForFileExtension:(NSString *)extension;

/*! Check if type is image. */
- (BOOL)isImageMimeType:(NSString *)mimeType;

/*! Check if type is video. */
- (BOOL)isVideoMimeType:(NSString *)mimeType;

/*! Check if type is audio. */
- (BOOL)isAudioMimeType:(NSString *)mimeType;

/*! Check if type is text. */
- (BOOL)isTextMimeType:(NSString *)mimeType;

/*! Get human-readable description. */
- (NSString *)descriptionForMimeType:(NSString *)mimeType;

/*! Validate magic numbers match claimed type. */
- (BOOL)validateMagicNumbers:(NSData *)data forMimeType:(NSString *)claimedMimeType error:(NSError **)error;

/*! Check if MIME type matches Accept header pattern. */
- (BOOL)matchesAccept:(NSString *)accept mimeType:(NSString *)mimeType;

/*! Check if MIME type matches any Accept pattern. */
- (BOOL)matchesAnyAccept:(NSArray<NSString *> *)acceptList mimeType:(NSString *)mimeType;

/*! Detect MIME type from file data magic numbers. */
- (nullable NSString *)sniffMimeTypeFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END