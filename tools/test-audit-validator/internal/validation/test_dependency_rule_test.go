package validation

import (
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestTestDependencyRule_Name(t *testing.T) {
	rule := NewTestDependencyRule()
	if rule.Name() != "TestDependencyRule" {
		t.Errorf("Expected rule name 'TestDependencyRule', got '%s'", rule.Name())
	}
}

func TestTestDependencyRule_Severity(t *testing.T) {
	rule := NewTestDependencyRule()
	if rule.Severity() != HIGH {
		t.Errorf("Expected severity HIGH, got %v", rule.Severity())
	}
}

func TestTestDependencyRule_Description(t *testing.T) {
	rule := NewTestDependencyRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

// Test external dependency detection

func TestTestDependencyRule_DetectsNetworkDependency(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testFetchFromAPI",
		ClassName:  "NetworkTests",
		LineNumber: 10,
		SourceCode: `
- (void)testFetchFromAPI {
    NSURL *url = [NSURL URLWithString:@"https://api.example.com/data"];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    NSData *data = [NSURLSession.sharedSession dataTaskWithRequest:request];
    XCTAssertNotNil(data);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/NetworkTests.m"},
		TestClass:  &models.TestClass{Name: "NetworkTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for network dependency, got none")
	}

	if len(findings) > 0 {
		if findings[0].Severity != MEDIUM {
			t.Errorf("Expected MEDIUM severity, got %v", findings[0].Severity)
		}
		if !contains(findings[0].Message, "network") {
			t.Errorf("Expected message to mention 'network', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_AllowsMockedNetwork(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testFetchFromMockServer",
		ClassName:  "NetworkTests",
		LineNumber: 10,
		SourceCode: `
- (void)testFetchFromMockServer {
    NSURL *url = [NSURL URLWithString:@"http://localhost:8080/test"];
    MockServer *mockServer = [[MockServer alloc] init];
    NSData *data = [mockServer fetchData:url];
    XCTAssertNotNil(data);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/NetworkTests.m"},
		TestClass:  &models.TestClass{Name: "NetworkTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not flag mocked network calls
	if len(findings) > 0 {
		for _, f := range findings {
			if contains(f.Message, "network") {
				t.Errorf("Should not flag mocked network calls, but got: %s", f.Message)
			}
		}
	}
}

func TestTestDependencyRule_DetectsFilesystemDependency(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testWriteToFile",
		ClassName:  "FileTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWriteToFile {
    NSString *path = @"/var/data/test.txt";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:path contents:data attributes:nil];
    XCTAssertTrue([fm fileExistsAtPath:path]);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/FileTests.m"},
		TestClass:  &models.TestClass{Name: "FileTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for filesystem dependency, got none")
	}

	if len(findings) > 0 {
		if !contains(findings[0].Message, "filesystem") {
			t.Errorf("Expected message to mention 'filesystem', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_AllowsTemporaryDirectory(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testWriteToTempFile",
		ClassName:  "FileTests",
		LineNumber: 10,
		SourceCode: `
- (void)testWriteToTempFile {
    NSString *tempDir = NSTemporaryDirectory();
    NSString *path = [tempDir stringByAppendingPathComponent:@"test.txt"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:path contents:data attributes:nil];
    XCTAssertTrue([fm fileExistsAtPath:path]);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/FileTests.m"},
		TestClass:  &models.TestClass{Name: "FileTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not flag temporary directory usage
	if len(findings) > 0 {
		for _, f := range findings {
			if contains(f.Message, "filesystem") {
				t.Errorf("Should not flag temporary directory usage, but got: %s", f.Message)
			}
		}
	}
}

func TestTestDependencyRule_DetectsDatabaseDependency(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testDatabaseQuery",
		ClassName:  "DatabaseTests",
		LineNumber: 10,
		SourceCode: `
- (void)testDatabaseQuery {
    sqlite3 *db;
    sqlite3_open("/var/db/production.db", &db);
    sqlite3_exec(db, "SELECT * FROM users", NULL, NULL, NULL);
    XCTAssertNotNil(db);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/DatabaseTests.m"},
		TestClass:  &models.TestClass{Name: "DatabaseTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for database dependency, got none")
	}

	if len(findings) > 0 {
		if !contains(findings[0].Message, "database") {
			t.Errorf("Expected message to mention 'database', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_AllowsInMemoryDatabase(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testInMemoryDatabase",
		ClassName:  "DatabaseTests",
		LineNumber: 10,
		SourceCode: `
- (void)testInMemoryDatabase {
    sqlite3 *db;
    sqlite3_open(":memory:", &db);
    sqlite3_exec(db, "CREATE TABLE test (id INTEGER)", NULL, NULL, NULL);
    XCTAssertNotNil(db);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/DatabaseTests.m"},
		TestClass:  &models.TestClass{Name: "DatabaseTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not flag in-memory database
	if len(findings) > 0 {
		for _, f := range findings {
			if contains(f.Message, "database") {
				t.Errorf("Should not flag in-memory database, but got: %s", f.Message)
			}
		}
	}
}

// Test execution order dependency detection

func TestTestDependencyRule_DetectsExecutionOrderDependency_Comment(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testSecondStep",
		ClassName:  "OrderTests",
		LineNumber: 10,
		SourceCode: `
- (void)testSecondStep {
    // This test must run after testFirstStep
    NSString *result = [self getResult];
    XCTAssertNotNil(result);
}
`,
		Comments: []string{"This test must run after testFirstStep"},
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/OrderTests.m"},
		TestClass:  &models.TestClass{Name: "OrderTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for execution order dependency, got none")
	}

	if len(findings) > 0 {
		if findings[0].Severity != CRITICAL {
			t.Errorf("Expected CRITICAL severity, got %v", findings[0].Severity)
		}
		if !contains(findings[0].Message, "execution order") {
			t.Errorf("Expected message to mention 'execution order', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_DoesNotFlagGenericFirstComment(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testTransactionIsolation",
		ClassName:  "DatabaseTests",
		LineNumber: 10,
		SourceCode: `
- (void)testTransactionIsolation {
    // Create account first, then insert record and verify visibility.
    XCTAssertTrue(YES);
}
`,
		Comments: []string{"Create account first, then insert record and verify visibility."},
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/DatabaseTests.m"},
		TestClass:  &models.TestClass{Name: "DatabaseTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)
	for _, f := range findings {
		if f.Severity == CRITICAL && contains(f.Message, "execution order") {
			t.Fatalf("unexpected execution-order critical finding: %s", f.Message)
		}
	}
}

func TestTestDependencyRule_DetectsExecutionOrderDependency_SharedResult(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testUsingPreviousResult",
		ClassName:  "OrderTests",
		LineNumber: 10,
		SourceCode: `
- (void)testUsingPreviousResult {
    NSString *result = self.sharedResult;
    XCTAssertEqual(result, @"expected");
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/OrderTests.m"},
		TestClass:  &models.TestClass{Name: "OrderTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for execution order dependency, got none")
	}

	if len(findings) > 0 {
		if findings[0].Severity != CRITICAL {
			t.Errorf("Expected CRITICAL severity, got %v", findings[0].Severity)
		}
	}
}

// Test shared mutable state detection

func TestTestDependencyRule_DetectsStaticVariableModification(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testModifyStatic",
		ClassName:  "StateTests",
		LineNumber: 10,
		SourceCode: `
- (void)testModifyStatic {
    static NSString *sharedValue = @"initial";
    sharedValue = @"modified";
    XCTAssertEqual(sharedValue, @"modified");
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/StateTests.m"},
		TestClass:  &models.TestClass{Name: "StateTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for static variable modification, got none")
	}

	if len(findings) > 0 {
		if findings[0].Severity != HIGH {
			t.Errorf("Expected HIGH severity, got %v", findings[0].Severity)
		}
		if !contains(findings[0].Message, "static") {
			t.Errorf("Expected message to mention 'static', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_DetectsSingletonModification(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testModifySingleton",
		ClassName:  "StateTests",
		LineNumber: 10,
		SourceCode: `
- (void)testModifySingleton {
    MyService *service = [MyService sharedInstance];
    [service setValue:@"test"];
    XCTAssertEqual(service.value, @"test");
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/StateTests.m"},
		TestClass:  &models.TestClass{Name: "StateTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for singleton modification, got none")
	}

	if len(findings) > 0 {
		if !contains(findings[0].Message, "singleton") || !contains(findings[0].Message, "global") {
			t.Errorf("Expected message to mention 'singleton' or 'global', got: %s", findings[0].Message)
		}
	}
}

// Test isolation validation

func TestTestDependencyRule_DetectsLackOfCleanup_Files(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testCreateFileNoCleanup",
		ClassName:  "IsolationTests",
		LineNumber: 10,
		SourceCode: `
- (void)testCreateFileNoCleanup {
    NSString *path = @"/tmp/test.txt";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:path contents:data attributes:nil];
    XCTAssertTrue([fm fileExistsAtPath:path]);
    // No cleanup!
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/IsolationTests.m"},
		TestClass:  &models.TestClass{Name: "IsolationTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for lack of cleanup, got none")
	}

	if len(findings) > 0 {
		if !contains(findings[0].Message, "files") {
			t.Errorf("Expected message to mention 'files', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_AllowsProperCleanup(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testCreateFileWithCleanup",
		ClassName:  "IsolationTests",
		LineNumber: 10,
		SourceCode: `
- (void)testCreateFileWithCleanup {
    NSString *path = @"/tmp/test.txt";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createFileAtPath:path contents:data attributes:nil];
    XCTAssertTrue([fm fileExistsAtPath:path]);
    [fm removeFileAtPath:path error:nil];
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/IsolationTests.m"},
		TestClass:  &models.TestClass{Name: "IsolationTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not flag tests with proper cleanup
	hasCleanupFinding := false
	for _, f := range findings {
		if contains(f.Message, "clean up") {
			hasCleanupFinding = true
		}
	}

	if hasCleanupFinding {
		t.Error("Should not flag tests with proper cleanup")
	}
}

func TestTestDependencyRule_DetectsLackOfCleanup_Database(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testDatabaseNoCleanup",
		ClassName:  "IsolationTests",
		LineNumber: 10,
		SourceCode: `
- (void)testDatabaseNoCleanup {
    sqlite3 *db;
    sqlite3_open("test.db", &db);
    sqlite3_exec(db, "CREATE TABLE test (id INTEGER)", NULL, NULL, NULL);
    XCTAssertNotNil(db);
    // No close!
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/IsolationTests.m"},
		TestClass:  &models.TestClass{Name: "IsolationTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for database cleanup, got none")
	}

	if len(findings) > 0 {
		if !contains(findings[0].Message, "database") {
			t.Errorf("Expected message to mention 'database', got: %s", findings[0].Message)
		}
	}
}

// Test side effect dependency detection

func TestTestDependencyRule_DetectsSideEffectDependency_Comment(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testAssumesExistingData",
		ClassName:  "SideEffectTests",
		LineNumber: 10,
		SourceCode: `
- (void)testAssumesExistingData {
    // Assumes user already exists from previous test
    User *user = [self findUser:@"test"];
    XCTAssertNotNil(user);
}
`,
		Comments: []string{"Assumes user already exists from previous test"},
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/SideEffectTests.m"},
		TestClass:  &models.TestClass{Name: "SideEffectTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for side effect dependency, got none")
	}

	if len(findings) > 0 {
		if findings[0].Severity != HIGH {
			t.Errorf("Expected HIGH severity, got %v", findings[0].Severity)
		}
		if !contains(findings[0].Message, "side effect") {
			t.Errorf("Expected message to mention 'side effect', got: %s", findings[0].Message)
		}
	}
}

func TestTestDependencyRule_DetectsReadWithoutSetup(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testReadWithoutSetup",
		ClassName:  "SideEffectTests",
		LineNumber: 10,
		SourceCode: `
- (void)testReadWithoutSetup {
    NSString *value = [self getExistingValue];
    XCTAssertEqual(value, @"expected");
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/SideEffectTests.m"},
		TestClass:  &models.TestClass{Name: "SideEffectTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected finding for reading without setup, got none")
	}

	if len(findings) > 0 {
		if findings[0].Severity != MEDIUM {
			t.Errorf("Expected MEDIUM severity, got %v", findings[0].Severity)
		}
	}
}

func TestTestDependencyRule_AllowsFixtureReading(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testReadFromFixture",
		ClassName:  "SideEffectTests",
		LineNumber: 10,
		SourceCode: `
- (void)testReadFromFixture {
    NSData *fixtureData = [self loadFixture:@"test.json"];
    NSDictionary *data = [NSJSONSerialization JSONObjectWithData:fixtureData];
    XCTAssertNotNil(data);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/SideEffectTests.m"},
		TestClass:  &models.TestClass{Name: "SideEffectTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should not flag fixture reading
	hasSideEffectFinding := false
	for _, f := range findings {
		if contains(f.Message, "side effect") {
			hasSideEffectFinding = true
		}
	}

	if hasSideEffectFinding {
		t.Error("Should not flag fixture reading as side effect dependency")
	}
}

// Test nil context handling

func TestTestDependencyRule_HandlesNilMethod(t *testing.T) {
	rule := NewTestDependencyRule()

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

// Test multiple dependencies

func TestTestDependencyRule_DetectsMultipleDependencies(t *testing.T) {
	rule := NewTestDependencyRule()

	method := &models.TestMethod{
		Name:       "testMultipleDependencies",
		ClassName:  "ComplexTests",
		LineNumber: 10,
		SourceCode: `
- (void)testMultipleDependencies {
    // Network dependency
    NSURL *url = [NSURL URLWithString:@"https://api.example.com"];
    NSData *data = [NSURLSession.sharedSession dataTaskWithRequest:url];
    
    // Filesystem dependency
    NSString *path = @"/var/data/test.txt";
    [NSFileManager.defaultManager createFileAtPath:path contents:data];
    
    // Database dependency
    sqlite3 *db;
    sqlite3_open("/var/db/test.db", &db);
    
    XCTAssertNotNil(data);
}
`,
	}

	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Tests/ComplexTests.m"},
		TestClass:  &models.TestClass{Name: "ComplexTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	if len(findings) == 0 {
		t.Error("Expected findings for multiple dependencies, got none")
	}

	// Should detect multiple dependency types
	if len(findings) > 0 {
		message := findings[0].Message
		if !contains(message, "network") && !contains(message, "filesystem") && !contains(message, "database") {
			t.Errorf("Expected message to mention dependency types, got: %s", message)
		}
	}
}

// Helper function - uses strings.Contains for simplicity
func contains(s, substr string) bool {
	return len(s) > 0 && len(substr) > 0 &&
		(s == substr || (len(s) > len(substr) && containsSubstring(s, substr)))
}

func containsSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
