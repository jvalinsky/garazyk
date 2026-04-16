#import <XCTest/XCTest.h>
#import "Sync/Relay/RelayEventValidator.h"

@interface RelayEventValidatorTests : XCTestCase

@end

@implementation RelayEventValidatorTests

- (void)testLenientModeForwardsAll {
    RelayEventValidator *validator = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeLenient];
    
    RelayValidationOutcome *validOutcome = [RelayValidationOutcome validOutcome];
    XCTAssertTrue([validator shouldForwardEvent:validOutcome]);
    
    RelayValidationOutcome *invalidOutcome = [RelayValidationOutcome invalidOutcome:@"MST proof failed"];
    XCTAssertTrue([validator shouldForwardEvent:invalidOutcome]);
}

- (void)testStrictModeDropsInvalid {
    RelayEventValidator *validator = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeStrict];
    
    RelayValidationOutcome *validOutcome = [RelayValidationOutcome validOutcome];
    XCTAssertTrue([validator shouldForwardEvent:validOutcome]);
    
    RelayValidationOutcome *invalidOutcome = [RelayValidationOutcome invalidOutcome:@"Signature invalid"];
    XCTAssertFalse([validator shouldForwardEvent:invalidOutcome]);
}

- (void)testLogOnlyModeForwardsAllButLogs {
    RelayEventValidator *validator = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeLogOnly];
    
    RelayValidationOutcome *validOutcome = [RelayValidationOutcome validOutcome];
    XCTAssertTrue([validator shouldForwardEvent:validOutcome]);
    
    RelayValidationOutcome *invalidOutcome = [RelayValidationOutcome invalidOutcome:@"Invalid"];
    XCTAssertTrue([validator shouldForwardEvent:invalidOutcome]); // Still forwards
}

- (void)testValidationModesWork {
    // Test lenient
    RelayEventValidator *lenient = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeLenient];
    XCTAssertEqual(lenient.validationMode, RelayValidationModeLenient);
    
    // Test strict
    RelayEventValidator *strict = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeStrict];
    XCTAssertEqual(strict.validationMode, RelayValidationModeStrict);
    
    // Test logOnly
    RelayEventValidator *logOnly = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeLogOnly];
    XCTAssertEqual(logOnly.validationMode, RelayValidationModeLogOnly);
}

- (void)testValidOutcomeCreation {
    RelayValidationOutcome *outcome = [RelayValidationOutcome validOutcome];
    XCTAssertEqual(outcome.result, RelayValidationResultValid);
    XCTAssertNil(outcome.errorMessage);
}

- (void)testInvalidOutcomeCreation {
    RelayValidationOutcome *outcome = [RelayValidationOutcome invalidOutcome:@"Test error"];
    XCTAssertEqual(outcome.result, RelayValidationResultInvalidMST);
    XCTAssertNotNil(outcome.errorMessage);
}

- (void)testErrorOutcomeCreation {
    RelayValidationOutcome *outcome = [RelayValidationOutcome errorOutcome:@"System error"];
    XCTAssertEqual(outcome.result, RelayValidationResultError);
    XCTAssertNotNil(outcome.errorMessage);
}

- (void)testChangeValidationMode {
    RelayEventValidator *validator = [[RelayEventValidator alloc] initWithValidationMode:RelayValidationModeLenient];
    XCTAssertEqual(validator.validationMode, RelayValidationModeLenient);
    
    validator.validationMode = RelayValidationModeStrict;
    XCTAssertEqual(validator.validationMode, RelayValidationModeStrict);
    
    validator.validationMode = RelayValidationModeLogOnly;
    XCTAssertEqual(validator.validationMode, RelayValidationModeLogOnly);
}

@end