package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestMockStubRule_Name(t *testing.T) {
	rule := NewMockStubRule()
	if rule.Name() != "MockStubRule" {
		t.Errorf("Expected rule name 'MockStubRule', got '%s'", rule.Name())
	}
}

func TestMockStubRule_Severity(t *testing.T) {
	rule := NewMockStubRule()
	if rule.Severity() != MEDIUM {
		t.Errorf("Expected severity MEDIUM, got %v", rule.Severity())
	}
}

func TestMockStubRule_Description(t *testing.T) {
	rule := NewMockStubRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

// Test nil method handling

func TestMockStubRule_HandlesNilMethod(t *testing.T) {
	rule := NewMockStubRule()

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/Test.m"},
		TestClass:  &models.TestClass{Name: "Test"},
		TestMethod: nil,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for nil method, got %d", len(findings))
	}
}

// Test OCMock pattern detection

func TestMockStubRule_DetectsOCMockClassMock(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithOCMock",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithOCMock {
    id mockClient = OCMClassMock([HTTPClient class]);
    OCMStub([mockClient fetchData]).andReturn(testData);
    [self.service performRequestWithClient:mockClient];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should detect unverified mock
	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified OCMock, got none")
	}
}

func TestMockStubRule_DetectsOCMockProtocolMock(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithProtocolMock",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithProtocolMock {
    id mockDelegate = OCMProtocolMock(@protocol(ServiceDelegate));
    self.service.delegate = mockDelegate;
    [self.service start];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified OCMProtocolMock, got none")
	}
}

func TestMockStubRule_DetectsOCMockStrictClassMock(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithStrictMock",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithStrictMock {
    id mockParser = OCMStrictClassMock([JSONParser class]);
    OCMExpect([mockParser parseData:testData]);
    [self.service processData:testData withParser:mockParser];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified OCMStrictClassMock, got none")
	}
}

// Test OCMock with verification (should pass)

func TestMockStubRule_AllowsVerifiedOCMock(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithVerifiedMock",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithVerifiedMock {
    id mockClient = OCMClassMock([HTTPClient class]);
    OCMStub([mockClient fetchData]).andReturn(testData);
    [self.service performRequestWithClient:mockClient];
    OCMVerifyAll(mockClient);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			t.Errorf("Should not flag verified OCMock, but got: %s", f.Message)
		}
	}
}

func TestMockStubRule_AllowsOCMVerify(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithOCMVerify",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithOCMVerify {
    id mockClient = OCMClassMock([HTTPClient class]);
    [self.service performRequestWithClient:mockClient];
    OCMVerify([mockClient fetchData]);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			t.Errorf("Should not flag OCMVerify usage, but got: %s", f.Message)
		}
	}
}

// Test custom Mock/Stub/Fake class usage

func TestMockStubRule_DetectsCustomMockClass(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithCustomMock",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithCustomMock {
    MockHTTPClient *mockClient = [[MockHTTPClient alloc] init];
    [self.service performRequestWithClient:mockClient];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified custom mock, got none")
	}
}

func TestMockStubRule_DetectsStubClass(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithStub",
		ClassName:  "StubTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithStub {
    StubDatabase *stubDB = [[StubDatabase alloc] init];
    [self.repo setDatabase:stubDB];
    NSArray *results = [self.repo fetchAll];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/StubTests.m"},
		TestClass:  &models.TestClass{Name: "StubTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified stub, got none")
	}
}

func TestMockStubRule_DetectsFakeClass(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithFake",
		ClassName:  "FakeTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithFake {
    FakeAuthProvider *fakeAuth = [[FakeAuthProvider alloc] init];
    [self.service setAuthProvider:fakeAuth];
    BOOL result = [self.service authenticate];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/FakeTests.m"},
		TestClass:  &models.TestClass{Name: "FakeTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified fake, got none")
	}
}

// Test custom mock with assertion (should pass)

func TestMockStubRule_AllowsCustomMockWithAssertion(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithAssertedMock",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithAssertedMock {
    MockHTTPClient *mockClient = [[MockHTTPClient alloc] init];
    [self.service performRequestWithClient:mockClient];
    XCTAssertTrue(mockClient.wasCalled);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			t.Errorf("Should not flag mock with assertion, but got: %s", f.Message)
		}
	}
}

// Test over-mocking detection (>3 mocks)

func TestMockStubRule_DetectsOverMocking(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithTooManyMocks",
		ClassName:  "OverMockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithTooManyMocks {
    id mockClient = OCMClassMock([HTTPClient class]);
    id mockParser = OCMClassMock([JSONParser class]);
    id mockCache = OCMClassMock([CacheManager class]);
    id mockLogger = OCMClassMock([Logger class]);
    [self.service setClient:mockClient];
    [self.service setParser:mockParser];
    [self.service setCache:mockCache];
    [self.service setLogger:mockLogger];
    [self.service processData];
    OCMVerifyAll(mockClient);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/OverMockTests.m"},
		TestClass:  &models.TestClass{Name: "OverMockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasOverMockFinding := false
	for _, f := range findings {
		if contains(f.Message, "over-mocking") {
			hasOverMockFinding = true
			if f.Severity != HIGH {
				t.Errorf("Expected HIGH severity for over-mocking, got %v", f.Severity)
			}
		}
	}

	if !hasOverMockFinding {
		t.Error("Expected finding for over-mocking (>3 mocks), got none")
	}
}

func TestMockStubRule_AllowsThreeOrFewerMocks(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testWithFewMocks",
		ClassName:  "MockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWithFewMocks {
    id mockClient = OCMClassMock([HTTPClient class]);
    id mockParser = OCMClassMock([JSONParser class]);
    id mockCache = OCMClassMock([CacheManager class]);
    [self.service setClient:mockClient];
    OCMVerifyAll(mockClient);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockTests.m"},
		TestClass:  &models.TestClass{Name: "MockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if contains(f.Message, "over-mocking") {
			t.Errorf("Should not flag 3 or fewer mocks, but got: %s", f.Message)
		}
	}
}

// Test under-mocking detection (network without mocks)

func TestMockStubRule_DetectsUnmockedNetworkDependency(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testNetworkWithoutMock",
		ClassName:  "UnderMockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testNetworkWithoutMock {
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSData *data = [session dataTaskWithRequest:request];
    XCTAssertNotNil(data);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/UnderMockTests.m"},
		TestClass:  &models.TestClass{Name: "UnderMockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasUnderMockFinding := false
	for _, f := range findings {
		if contains(f.Message, "not mocked") {
			hasUnderMockFinding = true
			if f.Severity != MEDIUM {
				t.Errorf("Expected MEDIUM severity for under-mocking, got %v", f.Severity)
			}
			if !contains(f.Message, "network") {
				t.Errorf("Expected message to mention 'network', got: %s", f.Message)
			}
		}
	}

	if !hasUnderMockFinding {
		t.Error("Expected finding for unmocked network dependency, got none")
	}
}

func TestMockStubRule_DetectsUnmockedDatabaseDependency(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testDatabaseWithoutMock",
		ClassName:  "UnderMockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testDatabaseWithoutMock {
    sqlite3 *db;
    sqlite3_open("/var/db/production.db", &db);
    sqlite3_exec(db, "SELECT * FROM users", NULL, NULL, NULL);
    XCTAssertNotNil(db);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/UnderMockTests.m"},
		TestClass:  &models.TestClass{Name: "UnderMockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasUnderMockFinding := false
	for _, f := range findings {
		if contains(f.Message, "not mocked") {
			hasUnderMockFinding = true
			if !contains(f.Message, "database") {
				t.Errorf("Expected message to mention 'database', got: %s", f.Message)
			}
		}
	}

	if !hasUnderMockFinding {
		t.Error("Expected finding for unmocked database dependency, got none")
	}
}

func TestMockStubRule_AllowsMockedNetworkDependency(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testNetworkWithMock",
		ClassName:  "MockedTests",
		LineNumber: 10,
		SourceCode: `
- (void)testNetworkWithMock {
    MockURLSession *mockSession = [[MockURLSession alloc] init];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSData *data = [mockSession dataTaskWithRequest:request];
    XCTAssertNotNil(data);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/MockedTests.m"},
		TestClass:  &models.TestClass{Name: "MockedTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	for _, f := range findings {
		if contains(f.Message, "not mocked") {
			t.Errorf("Should not flag mocked network dependency, but got: %s", f.Message)
		}
	}
}

// Test that tests without any mocks don't produce over-mocking findings

func TestMockStubRule_NoMocksNoOverMocking(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testSimpleLogic",
		ClassName:  "SimpleTests",
		LineNumber: 10,
		SourceCode: `
- (void)testSimpleLogic {
    NSString *result = [self.calculator add:@"1" to:@"2"];
    XCTAssertEqualObjects(result, @"3");
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/SimpleTests.m"},
		TestClass:  &models.TestClass{Name: "SimpleTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for test without mocks, got %d: %v", len(findings), findings)
	}
}

// Test proper mock usage (should produce no findings)

func TestMockStubRule_ProperMockUsageNoFindings(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testProperMockUsage",
		ClassName:  "GoodMockTests",
		LineNumber: 10,
		SourceCode: `
- (void)testProperMockUsage {
    id mockClient = OCMClassMock([HTTPClient class]);
    OCMStub([mockClient fetchData]).andReturn(testData);
    [self.service performRequestWithClient:mockClient];
    OCMVerifyAll(mockClient);
    XCTAssertEqual(self.service.lastStatus, 200);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/GoodMockTests.m"},
		TestClass:  &models.TestClass{Name: "GoodMockTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) != 0 {
		t.Errorf("Expected no findings for proper mock usage, got %d", len(findings))
		for _, f := range findings {
			t.Logf("  Finding: %s", f.Message)
		}
	}
}

// Test mock verification detection

func TestMockStubRule_DetectsUnverifiedMockInteraction(t *testing.T) {
	rule := NewMockStubRule()

	method := &models.TestMethod{
		Name:       "testUnverifiedMock",
		ClassName:  "VerificationTests",
		LineNumber: 10,
		SourceCode: `
- (void)testUnverifiedMock {
    id mockDelegate = OCMProtocolMock(@protocol(ServiceDelegate));
    self.service.delegate = mockDelegate;
    [self.service start];
    // No OCMVerify or assertion on mock
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/VerificationTests.m"},
		TestClass:  &models.TestClass{Name: "VerificationTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	hasVerificationFinding := false
	for _, f := range findings {
		if contains(f.Message, "does not verify mock interactions") {
			hasVerificationFinding = true
			if f.Severity != MEDIUM {
				t.Errorf("Expected MEDIUM severity for unverified mock, got %v", f.Severity)
			}
		}
	}

	if !hasVerificationFinding {
		t.Error("Expected finding for unverified mock interaction, got none")
	}
}
