// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <XCTest/XCTest.h>
#import "Blob/MimeTypeValidator.h"

@interface MimeTypeValidatorTests : XCTestCase

@property (nonatomic, strong) MimeTypeValidator *validator;

@end

@implementation MimeTypeValidatorTests

- (void)setUp {
    [super setUp];
    self.validator = [MimeTypeValidator sharedValidator];
}

- (void)tearDown {
    [super tearDown];
}

#pragma mark - Format Validation Tests

- (void)testValidJPEG {
    XCTAssertTrue([self.validator isValidMimeType:@"image/jpeg" error:nil], @"image/jpeg should be valid");
}

- (void)testValidPNG {
    XCTAssertTrue([self.validator isValidMimeType:@"image/png" error:nil], @"image/png should be valid");
}

- (void)testValidWithSubtypeIsValid {
    XCTAssertTrue([self.validator isValidMimeType:@"application/pdf" error:nil], @"application/pdf should be valid");
}

- (void)testInvalidNoSlashIsInvalid {
    XCTAssertFalse([self.validator isValidMimeType:@"imagejpeg" error:nil], @"imagejpeg should be invalid");
}

- (void)testInvalidEmptyType {
    XCTAssertFalse([self.validator isValidMimeType:@"/jpeg" error:nil], @"/jpeg should be invalid");
}

- (void)testInvalidEmptySubtypeIsInvalid {
    XCTAssertFalse([self.validator isValidMimeType:@"image/" error:nil], @"image/ should be invalid");
}

- (void)testInvalidNil {
    XCTAssertFalse([self.validator isValidMimeType:nil error:nil], @"nil should be invalid");
}

- (void)testInvalidEmpty {
    XCTAssertFalse([self.validator isValidMimeType:@"" error:nil], @"empty string should be invalid");
}

- (void)testCaseNormalizationIsValid {
    XCTAssertTrue([self.validator isValidMimeType:@"IMAGE/JPEG" error:nil], @"Uppercase should be normalized");
}

- (void)testWhitespaceTrimmingIsValid {
    XCTAssertTrue([self.validator isValidMimeType:@"  image/jpeg  " error:nil], @"Whitespace should be trimmed");
}

#pragma mark - Support Validation Tests

- (void)testSupportedImageJPEG {
    XCTAssertTrue([self.validator isSupportedMimeType:@"image/jpeg" error:nil], @"image/jpeg should be supported");
}

- (void)testSupportedImagePNG {
    XCTAssertTrue([self.validator isSupportedMimeType:@"image/png" error:nil], @"image/png should be supported");
}

- (void)testSupportedVideoMP4 {
    XCTAssertTrue([self.validator isSupportedMimeType:@"video/mp4" error:nil], @"video/mp4 should be supported");
}

- (void)testSupportedAudioMPEG {
    XCTAssertTrue([self.validator isSupportedMimeType:@"audio/mpeg" error:nil], @"audio/mpeg should be supported");
}

- (void)testSupportedTextPlain {
    XCTAssertTrue([self.validator isSupportedMimeType:@"text/plain" error:nil], @"text/plain should be supported");
}

- (void)testSupportedApplicationJSON {
    XCTAssertTrue([self.validator isSupportedMimeType:@"application/json" error:nil], @"application/json should be supported");
}

- (void)testUnsupportedType {
    XCTAssertFalse([self.validator isSupportedMimeType:@"application/x-custom" error:nil], @"Custom type should not be supported");
}

- (void)testUnsupportedImageXIcon {
    XCTAssertFalse([self.validator isSupportedMimeType:@"image/x-icon" error:nil], @"image/x-icon should not be supported");
}

#pragma mark - Category Tests

- (void)testCategoryImage {
    XCTAssertEqual([self.validator categoryForMimeType:@"image/jpeg"], MimeCategoryImage, @"image/jpeg should be image category");
}

- (void)testCategoryVideo {
    XCTAssertEqual([self.validator categoryForMimeType:@"video/mp4"], MimeCategoryVideo, @"video/mp4 should be video category");
}

- (void)testCategoryAudio {
    XCTAssertEqual([self.validator categoryForMimeType:@"audio/mpeg"], MimeCategoryAudio, @"audio/mpeg should be audio category");
}

- (void)testCategoryText {
    XCTAssertEqual([self.validator categoryForMimeType:@"text/plain"], MimeCategoryText, @"text/plain should be text category");
}

- (void)testCategoryFont {
    XCTAssertEqual([self.validator categoryForMimeType:@"font/woff2"], MimeCategoryFont, @"font/woff2 should be font category");
}

- (void)testCategoryModel {
    XCTAssertEqual([self.validator categoryForMimeType:@"model/gltf-binary"], MimeCategoryModel, @"model/gltf-binary should be model category");
}

- (void)testCategoryApplication {
    XCTAssertEqual([self.validator categoryForMimeType:@"application/json"], MimeCategoryApplication, @"application/json should be application category");
}

- (void)testCategoryUnknown {
    XCTAssertEqual([self.validator categoryForMimeType:@"x-custom/type"], MimeCategoryOther, @"Unknown type should be other category");
}

#pragma mark - Size Validation Tests

- (void)testValidSmallSize {
    XCTAssertTrue([self.validator validateSize:1024 forMimeType:@"image/jpeg" error:nil], @"Small size should be valid");
}

- (void)testValidBoundarySize {
    XCTAssertTrue([self.validator validateSize:5 * 1024 * 1024 forMimeType:@"image/jpeg" error:nil], @"Boundary size (5MB) should be valid");
}

- (void)testTooLargeImageExceedsLimit {
    XCTAssertFalse([self.validator validateSize:6 * 1024 * 1024 forMimeType:@"image/jpeg" error:nil], @"6MB should exceed image limit");
}

- (void)testValidLargeVideo {
    XCTAssertTrue([self.validator validateSize:10 * 1024 forMimeType:@"video/mp4 * 1024" error:nil], @"10MB video should be valid");
}

- (void)testTooLargeVideoExceedsLimit {
    XCTAssertFalse([self.validator validateSize:51 * 1024 * 1024 forMimeType:@"video/mp4" error:nil], @"51MB video should exceed limit");
}

#pragma mark - Max Size Tests

- (void)testImageMaxSize {
    XCTAssertEqual([self.validator maxSizeForMimeType:@"image/jpeg"], 5 * 1024 * 1024, @"Image max size should be 5MB");
}

- (void)testVideoMaxSize {
    XCTAssertEqual([self.validator maxSizeForMimeType:@"video/mp4"], 50 * 1024 * 1024, @"Video max size should be 50MB");
}

- (void)testAudioMaxSize {
    XCTAssertEqual([self.validator maxSizeForMimeType:@"audio/mpeg"], 10 * 1024 * 1024, @"Audio max size should be 10MB");
}

- (void)testUnknownMaxSize {
    XCTAssertEqual([self.validator maxSizeForMimeType:@"x-custom/type"], 5 * 1024 * 1024, @"Unknown type default max should be 5MB");
}

#pragma mark - Extension Conversion Tests

- (void)testExtensionForJPEG {
    XCTAssertEqualObjects([self.validator fileExtensionForMimeType:@"image/jpeg"], @"jpg", @"jpeg should map to jpg");
}

- (void)testExtensionForPNG {
    XCTAssertEqualObjects([self.validator fileExtensionForMimeType:@"image/png"], @"png", @"png should map to png");
}

- (void)testExtensionForMP4 {
    XCTAssertEqualObjects([self.validator fileExtensionForMimeType:@"video/mp4"], @"mp4", @"mp4 should map to mp4");
}

- (void)testExtensionForGLB {
    XCTAssertEqualObjects([self.validator fileExtensionForMimeType:@"model/gltf-binary"], @"glb", @"gltf-binary should map to glb");
}

- (void)testMIMETypeForJpg {
    XCTAssertEqualObjects([self.validator mimeTypeForFileExtension:@"jpg"], @"image/jpeg", @"jpg should map to image/jpeg");
}

- (void)testMIMETypeForJpeg {
    XCTAssertNil([self.validator mimeTypeForFileExtension:@"jpeg"], @"jpeg should not have a direct mapping");
}

- (void)testMIMETypeForPdf {
    XCTAssertEqualObjects([self.validator mimeTypeForFileExtension:@"pdf"], @"application/pdf", @"pdf should map to application/pdf");
}

- (void)testMIMETypeForDotExtension {
    XCTAssertEqualObjects([self.validator mimeTypeForFileExtension:@".jpg"], @"image/jpeg", @".jpg should map to image/jpeg");
}

- (void)testInvalidExtension {
    XCTAssertNil([self.validator mimeTypeForFileExtension:@"xyzxyz"], @"Invalid extension should return nil");
}

#pragma mark - Type Checking Tests

- (void)testIsImage {
    XCTAssertTrue([self.validator isImageMimeType:@"image/jpeg"], @"image/jpeg should be image type");
}

- (void)testIsNotVideoAsImage {
    XCTAssertFalse([self.validator isImageMimeType:@"video/mp4"], @"video/mp4 should not be image type");
}

- (void)testIsVideo {
    XCTAssertTrue([self.validator isVideoMimeType:@"video/mp4"], @"video/mp4 should be video type");
}

- (void)testIsAudio {
    XCTAssertTrue([self.validator isAudioMimeType:@"audio/mpeg"], @"audio/mpeg should be audio type");
}

- (void)testIsTextPlain {
    XCTAssertTrue([self.validator isTextMimeType:@"text/plain"], @"text/plain should be text type");
}

- (void)testIsTextCSS {
    XCTAssertTrue([self.validator isTextMimeType:@"text/css"], @"text/css should be text type");
}

- (void)testIsNotTextJSON {
    XCTAssertFalse([self.validator isTextMimeType:@"application/json"], @"application/json should not be text type");
}

#pragma mark - Description Tests

- (void)testDescriptionJPEG {
    XCTAssertEqualObjects([self.validator descriptionForMimeType:@"image/jpeg"], @"JPEG Image", @"jpeg should have correct description");
}

- (void)testDescriptionPDF {
    XCTAssertEqualObjects([self.validator descriptionForMimeType:@"application/pdf"], @"PDF Document", @"pdf should have correct description");
}

- (void)testDescriptionUnknownImage {
    XCTAssertEqualObjects([self.validator descriptionForMimeType:@"image/unknown"], @"Image File", @"Unknown image should have generic description");
}

#pragma mark - Accept List Matching Tests

- (void)testAcceptStarMatchesJPEG {
    XCTAssertTrue([self.validator matchesAccept:@"*/*" mimeType:@"image/jpeg"], @"*/* should match image/jpeg");
}

- (void)testAcceptStarMatchesVideo {
    XCTAssertTrue([self.validator matchesAccept:@"*/*" mimeType:@"video/mp4"], @"*/* should match video/mp4");
}

- (void)testAcceptImageMatchesJPEG {
    XCTAssertTrue([self.validator matchesAccept:@"image/*" mimeType:@"image/jpeg"], @"image/* should match image/jpeg");
}

- (void)testAcceptImageMatchesPNG {
    XCTAssertTrue([self.validator matchesAccept:@"image/*" mimeType:@"image/png"], @"image/* should match image/png");
}

- (void)testAcceptImageDoesNotMatchVideo {
    XCTAssertFalse([self.validator matchesAccept:@"image/*" mimeType:@"video/mp4"], @"image/* should not match video/mp4");
}

- (void)testAcceptExactMatch {
    XCTAssertTrue([self.validator matchesAccept:@"image/jpeg" mimeType:@"image/jpeg"], @"Exact match should work");
}

- (void)testAcceptDoesNotMatch {
    XCTAssertFalse([self.validator matchesAccept:@"image/png" mimeType:@"image/jpeg"], @"Different types should not match");
}

- (void)testAcceptVideoMatchesMP4 {
    XCTAssertTrue([self.validator matchesAccept:@"video/*" mimeType:@"video/mp4"], @"video/* should match video/mp4");
}

#pragma mark - Accept List Tests

- (void)testAcceptListMatchesImage {
    NSArray *imageAccept = @[@"image/*", @"video/mp4"];
    XCTAssertTrue([self.validator matchesAnyAccept:imageAccept mimeType:@"image/jpeg"], @"image/* in list should match jpeg");
}

- (void)testAcceptListMatchesExact {
    NSArray *imageAccept = @[@"image/*", @"video/mp4"];
    XCTAssertTrue([self.validator matchesAnyAccept:imageAccept mimeType:@"video/mp4"], @"Exact match in list should work");
}

- (void)testAcceptListDoesNotMatch {
    NSArray *imageAccept = @[@"image/*", @"video/mp4"];
    XCTAssertFalse([self.validator matchesAnyAccept:imageAccept mimeType:@"audio/mpeg"], @"Non-matching type should fail");
}

- (void)testEmptyAcceptList {
    XCTAssertFalse([self.validator matchesAnyAccept:@[] mimeType:@"image/jpeg"], @"Empty list should not match");
}

#pragma mark - Magic Number Detection Tests

- (void)testDetectPNGMagic {
    uint8_t pngHeader[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D};
    NSData *pngData = [NSData dataWithBytes:pngHeader length:sizeof(pngHeader)];
    NSString *pngSniffed = [self.validator sniffMimeTypeFromData:pngData];

    XCTAssertNotNil(pngSniffed, @"PNG magic number should be detected");
    XCTAssertEqualObjects(pngSniffed, @"image/png", @"Should identify as image/png");
}

- (void)testDetectJPEGMagic {
    uint8_t jpegHeader[] = {0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01};
    NSData *jpegData = [NSData dataWithBytes:jpegHeader length:sizeof(jpegHeader)];
    NSString *jpegSniffed = [self.validator sniffMimeTypeFromData:jpegData];

    XCTAssertNotNil(jpegSniffed, @"JPEG magic number should be detected");
    XCTAssertEqualObjects(jpegSniffed, @"image/jpeg", @"Should identify as image/jpeg");
}

- (void)testDetectPDFMagic {
    uint8_t pdfHeader[] = {'%', 'P', 'D', 'F', 0x31, 0x2E, 0x30, 0x0A, 0x25, 0x25, 0xE0, 0x0A};
    NSData *pdfData = [NSData dataWithBytes:pdfHeader length:sizeof(pdfHeader)];
    NSString *pdfSniffed = [self.validator sniffMimeTypeFromData:pdfData];

    XCTAssertNotNil(pdfSniffed, @"PDF magic number should be detected");
    XCTAssertEqualObjects(pdfSniffed, @"application/pdf", @"Should identify as application/pdf");
}

- (void)testSmallDataReturnsNil {
    uint8_t smallData[] = {0x01, 0x02, 0x03};
    NSData *small = [NSData dataWithBytes:smallData length:sizeof(smallData)];

    XCTAssertNil([self.validator sniffMimeTypeFromData:small], @"Small data should not be identified");
}

#pragma mark - Magic Number Validation Tests

- (void)testValidPNGMagic {
    uint8_t pngHeader[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D};
    NSData *pngData = [NSData dataWithBytes:pngHeader length:sizeof(pngHeader)];
    NSError *magicError = nil;

    XCTAssertTrue([self.validator validateMagicNumbers:pngData forMimeType:@"image/png" error:&magicError], @"Valid PNG magic should pass");
}

- (void)testCategoryMatchAllowedPNGvsJPEG {
    uint8_t pngHeader[] = {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D};
    NSData *pngData = [NSData dataWithBytes:pngHeader length:sizeof(pngHeader)];
    NSError *magicError = nil;

    XCTAssertTrue([self.validator validateMagicNumbers:pngData forMimeType:@"image/jpeg" error:&magicError], @"Category match should be allowed");
}

@end
