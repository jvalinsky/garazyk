#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const MimeTypeErrorDomain;

typedef NS_ENUM(NSInteger, MimeTypeError) {
    MimeTypeErrorInvalidFormat = 1000,
    MimeTypeErrorUnsupported,
    MimeTypeErrorTooLarge,
    MimeTypeErrorMagicNumberMismatch,
    MimeTypeErrorMalformed
};

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

@interface MimeTypeValidator : NSObject

@property (class, readonly) MimeTypeValidator *sharedValidator;

@property (nonatomic, readonly) NSDictionary<NSNumber *, NSNumber *> *maxSizesByCategory;

@property (nonatomic, readonly) NSSet<NSString *> *supportedImageTypes;
@property (nonatomic, readonly) NSSet<NSString *> *supportedVideoTypes;
@property (nonatomic, readonly) NSSet<NSString *> *supportedAudioTypes;
@property (nonatomic, readonly) NSSet<NSString *> *supportedFontTypes;
@property (nonatomic, readonly) NSSet<NSString *> *supportedModelTypes;
@property (nonatomic, readonly) NSSet<NSString *> *supportedDocumentTypes;
@property (nonatomic, readonly) NSSet<NSString *> *atprotoSpecificTypes;

- (BOOL)isValidMimeType:(NSString *)mimeType error:(NSError **)error;
- (BOOL)isSupportedMimeType:(NSString *)mimeType error:(NSError **)error;
- (MimeCategory)categoryForMimeType:(NSString *)mimeType;
- (NSString *)stringForCategory:(MimeCategory)category;
- (BOOL)validateSize:(NSUInteger)fileSize forMimeType:(NSString *)mimeType error:(NSError **)error;
- (NSUInteger)maxSizeForMimeType:(NSString *)mimeType;
- (nullable NSString *)normalizeMimeType:(NSString *)mimeType;
- (nullable NSString *)fileExtensionForMimeType:(NSString *)mimeType;
- (nullable NSString *)mimeTypeForFileExtension:(NSString *)extension;
- (BOOL)isImageMimeType:(NSString *)mimeType;
- (BOOL)isVideoMimeType:(NSString *)mimeType;
- (BOOL)isAudioMimeType:(NSString *)mimeType;
- (BOOL)isTextMimeType:(NSString *)mimeType;
- (NSString *)descriptionForMimeType:(NSString *)mimeType;
- (BOOL)validateMagicNumbers:(NSData *)data forMimeType:(NSString *)claimedMimeType error:(NSError **)error;

- (BOOL)matchesAccept:(NSString *)accept mimeType:(NSString *)mimeType;
- (BOOL)matchesAnyAccept:(NSArray<NSString *> *)acceptList mimeType:(NSString *)mimeType;

- (nullable NSString *)sniffMimeTypeFromData:(NSData *)data;

@end

NS_ASSUME_NONNULL_END