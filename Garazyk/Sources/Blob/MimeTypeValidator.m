// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Blob/MimeTypeValidator.h"

NSString * const MimeTypeErrorDomain = @"com.atproto.mimetype";

static const NSUInteger kMaxImageSize = 5 * 1024 * 1024;
static const NSUInteger kMaxVideoSize = 50 * 1024 * 1024;
static const NSUInteger kMaxAudioSize = 10 * 1024 * 1024;
static const NSUInteger kMaxFontSize = 10 * 1024 * 1024;
static const NSUInteger kMaxModelSize = 100 * 1024 * 1024;
static const NSUInteger kMaxDocumentSize = 10 * 1024 * 1024;
static const NSUInteger kMaxApplicationSize = 5 * 1024 * 1024;
static const NSUInteger kMaxOtherSize = 5 * 1024 * 1024;

@interface MimeTypeValidator ()

@property (nonatomic, strong) NSSet<NSString *> *supportedImageTypes;
@property (nonatomic, strong) NSSet<NSString *> *supportedVideoTypes;
@property (nonatomic, strong) NSSet<NSString *> *supportedAudioTypes;
@property (nonatomic, strong) NSSet<NSString *> *supportedFontTypes;
@property (nonatomic, strong) NSSet<NSString *> *supportedModelTypes;
@property (nonatomic, strong) NSSet<NSString *> *supportedDocumentTypes;
@property (nonatomic, strong) NSSet<NSString *> *atprotoSpecificTypes;

@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *mimeTypeToExtension;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *extensionToMimeType;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *mimeTypeToDescription;

@property (nonatomic, strong) NSDictionary<NSNumber *, NSNumber *> *maxSizesByCategory;

@end

@implementation MimeTypeValidator

+ (instancetype)sharedValidator {
    static MimeTypeValidator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[MimeTypeValidator alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupSupportedTypes];
        [self setupMimeTypeMappings];
        [self setupDescriptions];
        [self setupMaxSizes];
    }
    return self;
}

- (void)setupSupportedTypes {
    _supportedImageTypes = [NSSet setWithArray:@[
        @"image/jpeg",
        @"image/png",
        @"image/gif",
        @"image/webp",
        @"image/tiff",
        @"image/bmp",
        @"image/svg+xml",
        @"image/avif",
        @"image/heic",
        @"image/heif",
    ]];

    _supportedVideoTypes = [NSSet setWithArray:@[
        @"video/mp4",
        @"video/webm",
        @"video/quicktime",
        @"video/mpeg",
        @"video/avi",
        @"video/x-msvideo",
        @"video/x-matroska",
    ]];

    _supportedAudioTypes = [NSSet setWithArray:@[
        @"audio/mpeg",
        @"audio/wav",
        @"audio/ogg",
        @"audio/flac",
        @"audio/aac",
        @"audio/mp4",
        @"audio/webm",
        @"audio/midi",
        @"audio/x-m4a",
    ]];

    _supportedFontTypes = [NSSet setWithArray:@[
        @"font/woff",
        @"font/woff2",
        @"font/ttf",
        @"font/otf",
        @"font/sfnt",
    ]];

    _supportedModelTypes = [NSSet setWithArray:@[
        @"model/gltf-binary",
        @"model/gltf+json",
        @"model/obj",
        @"model/stl",
        @"model/3mf",
    ]];

    _supportedDocumentTypes = [NSSet setWithArray:@[
        @"application/pdf",
        @"application/postscript",
        @"application/msword",
        @"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        @"application/vnd.ms-excel",
        @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        @"application/vnd.ms-powerpoint",
        @"application/vnd.openxmlformats-officedocument.presentationml.presentation",
        @"application/rtf",
        @"application/epub+zip",
        @"application/json",
        @"application/xml",
        @"application/ld+json",
        @"application/octet-stream",
        @"text/plain",
        @"text/html",
        @"text/css",
        @"text/csv",
        @"text/javascript",
        @"application/javascript",
        @"text/markdown",
        @"application/markdown",
    ]];

    _atprotoSpecificTypes = [NSSet setWithArray:@[
        @"application/at+json",
    ]];
}

- (void)setupMimeTypeMappings {
    NSMutableDictionary *mimeToExt = [NSMutableDictionary dictionary];
    mimeToExt[@"image/jpeg"] = @"jpg";
    mimeToExt[@"image/png"] = @"png";
    mimeToExt[@"image/gif"] = @"gif";
    mimeToExt[@"image/webp"] = @"webp";
    mimeToExt[@"image/tiff"] = @"tiff";
    mimeToExt[@"image/tif"] = @"tif";
    mimeToExt[@"image/bmp"] = @"bmp";
    mimeToExt[@"image/svg+xml"] = @"svg";
    mimeToExt[@"image/avif"] = @"avif";
    mimeToExt[@"image/heic"] = @"heic";
    mimeToExt[@"image/heif"] = @"heif";
    mimeToExt[@"video/mp4"] = @"mp4";
    mimeToExt[@"video/webm"] = @"webm";
    mimeToExt[@"video/quicktime"] = @"mov";
    mimeToExt[@"video/mpeg"] = @"mpeg";
    mimeToExt[@"video/avi"] = @"avi";
    mimeToExt[@"video/x-matroska"] = @"mkv";
    mimeToExt[@"audio/mpeg"] = @"mp3";
    mimeToExt[@"audio/wav"] = @"wav";
    mimeToExt[@"audio/ogg"] = @"ogg";
    mimeToExt[@"audio/flac"] = @"flac";
    mimeToExt[@"audio/aac"] = @"aac";
    mimeToExt[@"audio/mp4"] = @"m4a";
    mimeToExt[@"audio/webm"] = @"webm";
    mimeToExt[@"audio/midi"] = @"mid";
    mimeToExt[@"audio/x-m4a"] = @"m4a";
    mimeToExt[@"font/woff"] = @"woff";
    mimeToExt[@"font/woff2"] = @"woff2";
    mimeToExt[@"font/ttf"] = @"ttf";
    mimeToExt[@"font/otf"] = @"otf";
    mimeToExt[@"font/sfnt"] = @"sfnt";
    mimeToExt[@"model/gltf-binary"] = @"glb";
    mimeToExt[@"model/gltf+json"] = @"gltf";
    mimeToExt[@"model/obj"] = @"obj";
    mimeToExt[@"model/stl"] = @"stl";
    mimeToExt[@"model/3mf"] = @"3mf";
    mimeToExt[@"application/pdf"] = @"pdf";
    mimeToExt[@"application/postscript"] = @"ai";
    mimeToExt[@"application/msword"] = @"doc";
    mimeToExt[@"application/vnd.openxmlformats-officedocument.wordprocessingml.document"] = @"docx";
    mimeToExt[@"application/vnd.ms-excel"] = @"xls";
    mimeToExt[@"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"] = @"xlsx";
    mimeToExt[@"application/vnd.ms-powerpoint"] = @"ppt";
    mimeToExt[@"application/vnd.openxmlformats-officedocument.presentationml.presentation"] = @"pptx";
    mimeToExt[@"application/rtf"] = @"rtf";
    mimeToExt[@"application/epub+zip"] = @"epub";
    mimeToExt[@"application/json"] = @"json";
    mimeToExt[@"application/xml"] = @"xml";
    mimeToExt[@"application/ld+json"] = @"jsonld";
    mimeToExt[@"text/plain"] = @"txt";
    mimeToExt[@"text/html"] = @"html";
    mimeToExt[@"text/css"] = @"css";
    mimeToExt[@"text/csv"] = @"csv";
    mimeToExt[@"text/javascript"] = @"js";
    mimeToExt[@"application/javascript"] = @"js";
    mimeToExt[@"text/markdown"] = @"md";
    mimeToExt[@"application/markdown"] = @"md";
    _mimeTypeToExtension = [mimeToExt copy];

    NSMutableDictionary *reverse = [NSMutableDictionary dictionary];
    for (NSString *mimeType in _mimeTypeToExtension) {
        NSString *extension = _mimeTypeToExtension[mimeType];
        reverse[extension.lowercaseString] = mimeType;
    }
    _extensionToMimeType = [reverse copy];
}

- (void)setupDescriptions {
    _mimeTypeToDescription = @{
        @"image/jpeg": @"JPEG Image",
        @"image/png": @"PNG Image",
        @"image/gif": @"GIF Image",
        @"image/webp": @"WebP Image",
        @"image/tiff": @"TIFF Image",
        @"image/bmp": @"Bitmap Image",
        @"image/svg+xml": @"SVG Image",
        @"image/avif": @"AVIF Image",
        @"image/heic": @"HEIC Image",
        @"image/heif": @"HEIF Image",
        @"video/mp4": @"MP4 Video",
        @"video/webm": @"WebM Video",
        @"video/quicktime": @"QuickTime Video",
        @"video/mpeg": @"MPEG Video",
        @"video/avi": @"AVI Video",
        @"video/x-matroska": @"Matroska Video",
        @"audio/mpeg": @"MP3 Audio",
        @"audio/wav": @"WAV Audio",
        @"audio/ogg": @"OGG Audio",
        @"audio/flac": @"FLAC Audio",
        @"audio/aac": @"AAC Audio",
        @"audio/mp4": @"M4A Audio",
        @"audio/webm": @"WebM Audio",
        @"audio/midi": @"MIDI Audio",
        @"font/woff": @"WOFF Font",
        @"font/woff2": @"WOFF2 Font",
        @"font/ttf": @"TTF Font",
        @"font/otf": @"OTF Font",
        @"application/pdf": @"PDF Document",
        @"application/postscript": @"Adobe Illustrator",
        @"application/msword": @"Word Document",
        @"application/vnd.openxmlformats-officedocument.wordprocessingml.document": @"Word Document",
        @"application/vnd.ms-excel": @"Excel Spreadsheet",
        @"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": @"Excel Spreadsheet",
        @"application/vnd.ms-powerpoint": @"PowerPoint Presentation",
        @"application/vnd.openxmlformats-officedocument.presentationml.presentation": @"PowerPoint Presentation",
        @"application/rtf": @"Rich Text Document",
        @"application/epub+zip": @"EPUB Book",
        @"application/json": @"JSON Data",
        @"application/xml": @"XML Data",
        @"application/ld+json": @"JSON-LD Data",
        @"text/plain": @"Plain Text",
        @"text/html": @"HTML Document",
        @"text/css": @"CSS Stylesheet",
        @"text/csv": @"CSV Data",
        @"text/markdown": @"Markdown Document",
        @"application/at+json": @"ATProto JSON",
    };
}

- (void)setupMaxSizes {
    _maxSizesByCategory = @{
        @(MimeCategoryImage): @(kMaxImageSize),
        @(MimeCategoryVideo): @(kMaxVideoSize),
        @(MimeCategoryAudio): @(kMaxAudioSize),
        @(MimeCategoryFont): @(kMaxFontSize),
        @(MimeCategoryModel): @(kMaxModelSize),
        @(MimeCategoryApplication): @(kMaxApplicationSize),
        @(MimeCategoryOther): @(kMaxOtherSize),
    };
}

#pragma mark - Public Validation Methods

- (BOOL)isValidMimeType:(NSString *)mimeType error:(NSError **)error {
    if (!mimeType || mimeType.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"MIME type is nil or empty"}];
        }
        return NO;
    }

    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid MIME type format"}];
        }
        return NO;
    }

    NSRange slashRange = [normalized rangeOfString:@"/"];
    if (slashRange.location == NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"MIME type must contain a '/' character"}];
        }
        return NO;
    }

    NSString *type = [normalized substringToIndex:slashRange.location];
    NSString *subtype = [normalized substringFromIndex:slashRange.location + 1];

    if (type.length == 0 || subtype.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"MIME type missing type or subtype"}];
        }
        return NO;
    }

    NSCharacterSet *validChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789!#$&+-^."];
    NSCharacterSet *typeChars = [NSCharacterSet characterSetWithCharactersInString:type.lowercaseString];
    NSCharacterSet *subtypeChars = [NSCharacterSet characterSetWithCharactersInString:subtype.lowercaseString];

    NSCharacterSet *invalidTypeChars = [typeChars invertedSet];
    NSCharacterSet *invalidSubtypeChars = [subtypeChars invertedSet];

    if ([type rangeOfCharacterFromSet:invalidTypeChars].location != NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"MIME type contains invalid characters"}];
        }
        return NO;
    }

    if ([subtype rangeOfCharacterFromSet:invalidSubtypeChars].location != NSNotFound) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"MIME subtype contains invalid characters"}];
        }
        return NO;
    }

    return YES;
}

- (BOOL)isSupportedMimeType:(NSString *)mimeType error:(NSError **)error {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid MIME type format"}];
        }
        return NO;
    }

    if ([_supportedImageTypes containsObject:normalized]) return YES;
    if ([_supportedVideoTypes containsObject:normalized]) return YES;
    if ([_supportedAudioTypes containsObject:normalized]) return YES;
    if ([_supportedFontTypes containsObject:normalized]) return YES;
    if ([_supportedModelTypes containsObject:normalized]) return YES;
    if ([_supportedDocumentTypes containsObject:normalized]) return YES;
    if ([_atprotoSpecificTypes containsObject:normalized]) return YES;

    if (error) {
        NSString *category = [self stringForCategory:[self categoryForMimeType:normalized]];
        *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                     code:MimeTypeErrorUnsupported
                                 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsupported MIME type: %@ (%@)", normalized, category]}];
    }
    return NO;
}

#pragma mark - Category Methods

- (MimeCategory)categoryForMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return MimeCategoryOther;

    if ([normalized hasPrefix:@"image/"]) return MimeCategoryImage;
    if ([normalized hasPrefix:@"video/"]) return MimeCategoryVideo;
    if ([normalized hasPrefix:@"audio/"]) return MimeCategoryAudio;
    if ([normalized hasPrefix:@"font/"]) return MimeCategoryFont;
    if ([normalized hasPrefix:@"model/"]) return MimeCategoryModel;
    if ([normalized hasPrefix:@"text/"]) return MimeCategoryText;
    if ([normalized hasPrefix:@"application/"]) return MimeCategoryApplication;

    return MimeCategoryOther;
}

- (NSString *)stringForCategory:(MimeCategory)category {
    switch (category) {
        case MimeCategoryImage: return @"Image";
        case MimeCategoryVideo: return @"Video";
        case MimeCategoryAudio: return @"Audio";
        case MimeCategoryText: return @"Text";
        case MimeCategoryFont: return @"Font";
        case MimeCategoryModel: return @"3D Model";
        case MimeCategoryApplication: return @"Application";
        case MimeCategoryOther: return @"Other";
    }
}

#pragma mark - Size Validation

- (BOOL)validateSize:(NSUInteger)fileSize forMimeType:(NSString *)mimeType error:(NSError **)error {
    NSUInteger maxSize = [self maxSizeForMimeType:mimeType];

    if (fileSize > maxSize) {
        if (error) {
            NSString *category = [self stringForCategory:[self categoryForMimeType:mimeType]];
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorTooLarge
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File size %lu bytes exceeds maximum for %@ (%lu bytes)", (unsigned long)fileSize, category, (unsigned long)maxSize],
                @"maxSize": @(maxSize),
                @"actualSize": @(fileSize)
            }];
        }
        return NO;
    }

    return YES;
}

- (NSUInteger)maxSizeForMimeType:(NSString *)mimeType {
    MimeCategory category = [self categoryForMimeType:mimeType];
    NSNumber *maxSize = _maxSizesByCategory[@(category)];
    return maxSize ? maxSize.unsignedIntegerValue : kMaxOtherSize;
}

#pragma mark - Normalization and Conversion

- (nullable NSString *)normalizeMimeType:(NSString *)mimeType {
    if (!mimeType || ![mimeType isKindOfClass:[NSString class]]) return nil;

    NSString *trimmed = [mimeType stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return nil;

    return trimmed.lowercaseString;
}

- (nullable NSString *)fileExtensionForMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return nil;

    return _mimeTypeToExtension[normalized];
}

- (nullable NSString *)mimeTypeForFileExtension:(NSString *)extension {
    if (!extension || extension.length == 0) return nil;

    NSString *normalized = extension.lowercaseString;
    if ([normalized hasPrefix:@"."]) {
        normalized = [normalized substringFromIndex:1];
    }

    return _extensionToMimeType[normalized];
}

#pragma mark - Type Checking

- (BOOL)isImageMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return NO;
    return [normalized hasPrefix:@"image/"];
}

- (BOOL)isVideoMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return NO;
    return [normalized hasPrefix:@"video/"];
}

- (BOOL)isAudioMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return NO;
    return [normalized hasPrefix:@"audio/"];
}

- (BOOL)isTextMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return NO;

    if ([normalized isEqualToString:@"text/plain"]) return YES;
    if ([normalized hasPrefix:@"text/"]) return YES;

    return NO;
}

#pragma mark - Descriptions

- (NSString *)descriptionForMimeType:(NSString *)mimeType {
    NSString *normalized = [self normalizeMimeType:mimeType];
    if (!normalized) return @"Unknown";

    NSString *desc = _mimeTypeToDescription[normalized];
    if (desc) return desc;

    MimeCategory category = [self categoryForMimeType:mimeType];
    return [NSString stringWithFormat:@"%@ File", [self stringForCategory:category]];
}

#pragma mark - Magic Number Validation

- (BOOL)validateMagicNumbers:(NSData *)data forMimeType:(NSString *)claimedMimeType error:(NSError **)error {
    if (!data || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorMalformed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty data cannot be validated"}];
        }
        return NO;
    }

    NSString *normalized = [self normalizeMimeType:claimedMimeType];
    if (!normalized) {
        if (error) {
            *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                         code:MimeTypeErrorInvalidFormat
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid MIME type format"}];
        }
        return NO;
    }

    NSString *sniffed = [self sniffMimeTypeFromData:data];

    if (!sniffed) {
        // If it's a type we should definitely be able to sniff, but couldn't, it's a mismatch.
        if ([normalized isEqualToString:@"image/jpeg"] ||
            [normalized isEqualToString:@"image/png"] ||
            [normalized isEqualToString:@"image/gif"] ||
            [normalized isEqualToString:@"application/pdf"]) {
            if (error) {
                *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                             code:MimeTypeErrorMagicNumberMismatch
                                         userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Magic number mismatch: claimed %@ but could not detect valid header", normalized]
                }];
            }
            return NO;
        }
        return YES;
    }

    if (![sniffed isEqualToString:normalized]) {
        BOOL matchesCategory = NO;
        if ([normalized hasPrefix:@"image/"] && [sniffed hasPrefix:@"image/"]) matchesCategory = YES;
        else if ([normalized hasPrefix:@"video/"] && [sniffed hasPrefix:@"video/"]) matchesCategory = YES;
        else if ([normalized hasPrefix:@"audio/"] && [sniffed hasPrefix:@"audio/"]) matchesCategory = YES;
        else if ([normalized hasPrefix:@"font/"] && [sniffed hasPrefix:@"font/"]) matchesCategory = YES;

        if (!matchesCategory) {
            if (error) {
                *error = [NSError errorWithDomain:MimeTypeErrorDomain
                                             code:MimeTypeErrorMagicNumberMismatch
                                         userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Magic number mismatch: claimed %@ but detected %@", normalized, sniffed],
                    @"claimedMimeType": normalized,
                    @"detectedMimeType": sniffed
                }];
            }
            return NO;
        }
    }

    return YES;
}

- (nullable NSString *)sniffMimeTypeFromData:(NSData *)data {
    if (!data || data.length == 0) {
        return nil;
    }

    const uint8_t *bytes = data.bytes;

    if (data.length >= 2) {
        if (bytes[0] == 0x42 && bytes[1] == 0x4D) return @"image/bmp";
    }

    if (data.length >= 4) {
        uint32_t magic = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];

        if (magic == 0x89504E47) return @"image/png";
        if (magic == 0xFFD8FFDB || magic == 0xFFD8FFE0 || magic == 0xFFD8FFE1) return @"image/jpeg";
        if (magic == 0x47494638) return @"image/gif";
        if (magic == 0x49492A00 || magic == 0x4D4D002A) return @"image/tiff";
        if (magic == 0x52494646) { // "RIFF"
             // Handled below with more data
        }
        if (magic == 0x4F676753) return @"audio/ogg";
        if (magic == 0x664C6143) return @"audio/flac";
        if (magic == 0x1A45DFA3) return @"video/webm";
        if (magic == 0x25504446) return @"application/pdf"; // "%PDF"
    }

    if (data.length >= 8) {
        uint64_t magic64 = ((uint64_t)bytes[0] << 56) | ((uint64_t)bytes[1] << 48) |
                           ((uint64_t)bytes[2] << 40) | ((uint64_t)bytes[3] << 32) |
                           ((uint64_t)bytes[4] << 24) | ((uint64_t)bytes[5] << 16) |
                           ((uint64_t)bytes[6] << 8) | bytes[7];

        if (magic64 == 0x6674797069736F6D) return @"video/mp4";
        if (magic64 == 0x667479706D703432) return @"video/mp4";
        if (magic64 == 0x4D534346) return @"application/font-woff";
        if (magic64 == 0x774F4646) return @"font/woff";
    }

    if (data.length >= 12) {
        if (bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x01 && bytes[3] == 0x00) {
            return @"image/x-icon";
        }
        if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
            return @"audio/mpeg";
        }
        if (memcmp(bytes, "RIFF", 4) == 0) {
            if (memcmp(bytes + 8, "WEBP", 4) == 0) return @"image/webp";
            if (memcmp(bytes + 8, "AVI ", 4) == 0) return @"video/avi";
            if (memcmp(bytes + 8, "WAVE", 4) == 0) return @"audio/wav";
        }
    }
    
    if (data.length >= 1) {
        if (bytes[0] == '{') {
             // Basic JSON check
             return @"application/json";
        }
    }

    return nil;
}

#pragma mark - Accept List Matching (ATProto Style)

- (BOOL)matchesAccept:(NSString *)accept mimeType:(NSString *)mimeType {
    if (![self isValidMimeType:mimeType error:nil]) {
        return NO;
    }

    NSString *normalizedAccept = [self normalizeMimeType:accept];
    NSString *normalizedMime = [self normalizeMimeType:mimeType];

    if (!normalizedAccept) {
        return NO;
    }

    if ([normalizedAccept isEqualToString:@"*/*"]) {
        return YES;
    }

    if ([normalizedAccept isEqualToString:normalizedMime]) {
        return YES;
    }

    if ([normalizedAccept hasSuffix:@"/*"] && normalizedAccept.length > 2) {
        NSString *prefix = [normalizedAccept substringToIndex:normalizedAccept.length - 1];
        if ([normalizedMime hasPrefix:prefix]) {
            return YES;
        }
    }

    return NO;
}

- (BOOL)matchesAnyAccept:(NSArray<NSString *> *)acceptList mimeType:(NSString *)mimeType {
    if (!acceptList || acceptList.count == 0) {
        return NO;
    }

    for (NSString *accept in acceptList) {
        if ([self matchesAccept:accept mimeType:mimeType]) {
            return YES;
        }
    }

    return NO;
}

@end