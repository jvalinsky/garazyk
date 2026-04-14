package validation

import (
	"strings"
	"testing"

	"github.com/september-pds/test-audit-validator/internal/models"
)

func TestIntegrationTestRule_Name(t *testing.T) {
	rule := NewIntegrationTestRule()
	if rule.Name() != "IntegrationTestRule" {
		t.Errorf("Expected rule name 'IntegrationTestRule', got '%s'", rule.Name())
	}
}

func TestIntegrationTestRule_Severity(t *testing.T) {
	rule := NewIntegrationTestRule()
	if rule.Severity() != MEDIUM {
		t.Errorf("Expected severity MEDIUM, got %v", rule.Severity())
	}
}

func TestIntegrationTestRule_Description(t *testing.T) {
	rule := NewIntegrationTestRule()
	desc := rule.Description()
	if desc == "" {
		t.Error("Expected non-empty description")
	}
}

func TestIntegrationTestRule_IsIntegrationTest(t *testing.T) {
	rule := NewIntegrationTestRule()

	tests := []struct {
		name     string
		method   *models.TestMethod
		class    *models.TestClass
		file     *models.TestFile
		expected bool
	}{
		{
			name: "integration in file path",
			method: &models.TestMethod{
				Name: "testSomething",
			},
			class: &models.TestClass{
				Name: "SomeTests",
			},
			file: &models.TestFile{
				Path: "Garazyk/Tests/Integration/SomeTests.m",
			},
			expected: true,
		},
		{
			name: "integration in class name",
			method: &models.TestMethod{
				Name: "testSomething",
			},
			class: &models.TestClass{
				Name: "IntegrationTests",
			},
			file: &models.TestFile{
				Path: "Garazyk/Tests/SomeTests.m",
			},
			expected: true,
		},
		{
			name: "integration in method name",
			method: &models.TestMethod{
				Name: "testIntegrationWorkflow",
			},
			class: &models.TestClass{
				Name: "SomeTests",
			},
			file: &models.TestFile{
				Path: "Garazyk/Tests/SomeTests.m",
			},
			expected: true,
		},
		{
			name: "e2e in class name",
			method: &models.TestMethod{
				Name: "testSomething",
			},
			class: &models.TestClass{
				Name: "E2ETests",
			},
			file: &models.TestFile{
				Path: "Garazyk/Tests/SomeTests.m",
			},
			expected: true,
		},
		{
			name: "integration in comments",
			method: &models.TestMethod{
				Name:     "testSomething",
				Comments: []string{"This is an integration test"},
			},
			class: &models.TestClass{
				Name: "SomeTests",
			},
			file: &models.TestFile{
				Path: "Garazyk/Tests/SomeTests.m",
			},
			expected: true,
		},
		{
			name: "not an integration test",
			method: &models.TestMethod{
				Name: "testUnitFunction",
			},
			class: &models.TestClass{
				Name: "UnitTests",
			},
			file: &models.TestFile{
				Path: "Garazyk/Tests/Core/UnitTests.m",
			},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := rule.isIntegrationTest(tt.method, tt.class, tt.file)
			if result != tt.expected {
				t.Errorf("Expected %v, got %v", tt.expected, result)
			}
		})
	}
}

func TestIntegrationTestRule_CheckMultipleComponents(t *testing.T) {
	rule := NewIntegrationTestRule()

	tests := []struct {
		name          string
		sourceCode    string
		expectFinding bool
	}{
		{
			name: "multiple components - database and network",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				HttpRequest *request = [HttpRequest new];
				[request send];
				[db query:@"SELECT * FROM users"];
			`,
			expectFinding: false,
		},
		{
			name: "multiple components - auth and service",
			sourceCode: `
				OAuthHandler *auth = [OAuthHandler new];
				PDSAccountService *service = [PDSAccountService new];
				[auth validateToken:token];
				[service createAccount:account];
			`,
			expectFinding: false,
		},
		{
			name: "single component - only database",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				[db query:@"SELECT * FROM users"];
				[db insert:@"INSERT INTO users VALUES (1, 'test')"];
			`,
			expectFinding: true,
		},
		{
			name: "single component - only network",
			sourceCode: `
				HttpRequest *request = [HttpRequest new];
				[request send];
				HttpResponse *response = [request getResponse];
			`,
			expectFinding: true,
		},
		{
			name: "multiple components - repository and storage",
			sourceCode: `
				PDSRepository *repo = [PDSRepository new];
				BlobStorage *storage = [BlobStorage new];
				[repo commit:data];
				[storage uploadBlob:blob];
			`,
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method := &models.TestMethod{
				Name:       "testIntegration",
				ClassName:  "IntegrationTests",
				SourceCode: tt.sourceCode,
			}
			ctx := ValidationContext{
				TestFile: &models.TestFile{
					Path: "Garazyk/Tests/Integration/IntegrationTests.m",
				},
				TestClass:  &models.TestClass{Name: "IntegrationTests"},
				TestMethod: method,
			}

			finding := rule.checkMultipleComponents(method, ctx)
			hasFinding := finding != nil

			if hasFinding != tt.expectFinding {
				t.Errorf("Expected finding=%v, got finding=%v", tt.expectFinding, hasFinding)
			}

			if hasFinding && finding.Severity != MEDIUM {
				t.Errorf("Expected MEDIUM severity, got %v", finding.Severity)
			}
		})
	}
}

func TestIntegrationTestRule_CheckRealisticEnvironment(t *testing.T) {
	rule := NewIntegrationTestRule()

	tests := []struct {
		name          string
		sourceCode    string
		expectFinding bool
	}{
		{
			name: "realistic setup with PDSApplication",
			sourceCode: `
				PDSConfiguration *config = [PDSConfiguration new];
				PDSApplication *app = [[PDSApplication alloc] initWithConfiguration:config];
				[app start];
			`,
			expectFinding: false,
		},
		{
			name: "realistic setup with test server",
			sourceCode: `
				HttpServer *server = [self createTestServer];
				[server start];
			`,
			expectFinding: false,
		},
		{
			name: "heavy mocking without realistic setup",
			sourceCode: `
				id mockDB = [OCMockObject mockForClass:[PDSDatabase class]];
				id mockAuth = [OCMockObject mockForClass:[OAuthHandler class]];
				id mockService = [OCMockObject mockForClass:[PDSAccountService class]];
				id mockStorage = [OCMockObject mockForClass:[BlobStorage class]];
			`,
			expectFinding: true,
		},
		{
			name: "realistic setup with database",
			sourceCode: `
				PDSDatabase *db = [self createTestDatabase];
				[db initialize];
			`,
			expectFinding: false,
		},
		{
			name: "minimal mocking with realistic setup",
			sourceCode: `
				PDSApplication *app = [self setupEnvironment];
				id mockExternal = [OCMockObject mockForClass:[ExternalService class]];
			`,
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method := &models.TestMethod{
				Name:       "testIntegration",
				ClassName:  "IntegrationTests",
				SourceCode: tt.sourceCode,
			}
			ctx := ValidationContext{
				TestFile: &models.TestFile{
					Path: "Garazyk/Tests/Integration/IntegrationTests.m",
				},
				TestClass:  &models.TestClass{Name: "IntegrationTests"},
				TestMethod: method,
			}

			finding := rule.checkRealisticEnvironment(method, ctx)
			hasFinding := finding != nil

			if hasFinding != tt.expectFinding {
				t.Errorf("Expected finding=%v, got finding=%v", tt.expectFinding, hasFinding)
			}

			if hasFinding && finding.Severity != LOW {
				t.Errorf("Expected LOW severity, got %v", finding.Severity)
			}
		})
	}
}

func TestIntegrationTestRule_CheckResourceCleanup(t *testing.T) {
	rule := NewIntegrationTestRule()

	tests := []struct {
		name          string
		sourceCode    string
		expectFinding bool
	}{
		{
			name: "database with cleanup",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				[db query:@"SELECT * FROM users"];
				[db close];
			`,
			expectFinding: false,
		},
		{
			name: "database without cleanup",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				[db query:@"SELECT * FROM users"];
			`,
			expectFinding: true,
		},
		{
			name: "file with cleanup",
			sourceCode: `
				NSString *tempFile = [self createTempFile];
				[self writeToFile:tempFile];
				[self deleteFile:tempFile];
			`,
			expectFinding: false,
		},
		{
			name: "file without cleanup",
			sourceCode: `
				NSString *tempFile = [self createTempFile];
				[self writeToFile:tempFile];
			`,
			expectFinding: true,
		},
		{
			name: "server with cleanup",
			sourceCode: `
				HttpServer *server = [HttpServer new];
				[server start];
				[server stop];
			`,
			expectFinding: false,
		},
		{
			name: "server without cleanup",
			sourceCode: `
				HttpServer *server = [HttpServer new];
				[server start];
			`,
			expectFinding: true,
		},
		{
			name: "connection with cleanup",
			sourceCode: `
				WebSocket *socket = [WebSocket new];
				[socket connect];
				[socket close];
			`,
			expectFinding: false,
		},
		{
			name: "multiple resources with partial cleanup",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				HttpServer *server = [HttpServer new];
				[server start];
				[db close];
			`,
			expectFinding: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method := &models.TestMethod{
				Name:       "testIntegration",
				ClassName:  "IntegrationTests",
				SourceCode: tt.sourceCode,
			}
			ctx := ValidationContext{
				TestFile: &models.TestFile{
					Path: "Garazyk/Tests/Integration/IntegrationTests.m",
				},
				TestClass:  &models.TestClass{Name: "IntegrationTests"},
				TestMethod: method,
			}

			finding := rule.checkResourceCleanup(method, ctx)
			hasFinding := finding != nil

			if hasFinding != tt.expectFinding {
				t.Errorf("Expected finding=%v, got finding=%v", tt.expectFinding, hasFinding)
			}

			if hasFinding && finding.Severity != MEDIUM {
				t.Errorf("Expected MEDIUM severity, got %v", finding.Severity)
			}
		})
	}
}

func TestIntegrationTestRule_CheckResourceCleanup_DeterministicResourceOrder(t *testing.T) {
	rule := NewIntegrationTestRule()
	method := &models.TestMethod{
		Name:      "testIntegration",
		ClassName: "IntegrationTests",
		SourceCode: `
			PDSDatabase *db = [PDSDatabase new];
			HttpServer *server = [HttpServer new];
			[server start];
			[db query:@"SELECT * FROM users"];
		`,
	}
	ctx := ValidationContext{
		TestFile:   &models.TestFile{Path: "Garazyk/Tests/Integration/IntegrationTests.m"},
		TestClass:  &models.TestClass{Name: "IntegrationTests"},
		TestMethod: method,
	}

	finding := rule.checkResourceCleanup(method, ctx)
	if finding == nil {
		t.Fatal("expected cleanup finding")
	}
	if !strings.Contains(finding.Message, "database, network") {
		t.Fatalf("expected deterministic resource order in message, got: %s", finding.Message)
	}
}

func TestIntegrationTestRule_CheckFinalOutcomeAssertions(t *testing.T) {
	rule := NewIntegrationTestRule()

	tests := []struct {
		name           string
		sourceCode     string
		assertions     []models.Assertion
		expectFinding  bool
		expectSeverity Severity
	}{
		{
			name: "no assertions",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				[db query:@"SELECT * FROM users"];
			`,
			assertions:     []models.Assertion{},
			expectFinding:  true,
			expectSeverity: HIGH,
		},
		{
			name: "only intermediate assertions",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				XCTAssertNotNil(db);
				HttpServer *server = [HttpServer new];
				XCTAssertNotNil(server);
				[server start];
			`,
			assertions: []models.Assertion{
				{Type: "XCTAssertNotNil", Arguments: []string{"db"}},
				{Type: "XCTAssertNotNil", Arguments: []string{"server"}},
			},
			expectFinding:  true,
			expectSeverity: MEDIUM,
		},
		{
			name: "final outcome assertions",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				HttpServer *server = [HttpServer new];
				[server start];
				NSArray *users = [db query:@"SELECT * FROM users"];
				XCTAssertEqual(users.count, 5);
				XCTAssertEqualObjects(users[0][@"name"], @"Alice");
			`,
			assertions: []models.Assertion{
				{Type: "XCTAssertEqual", Arguments: []string{"users.count", "5"}},
				{Type: "XCTAssertEqualObjects", Arguments: []string{"users[0][@\"name\"]", "@\"Alice\""}},
			},
			expectFinding: false,
		},
		{
			name: "mixed intermediate and final assertions",
			sourceCode: `
				PDSDatabase *db = [PDSDatabase new];
				XCTAssertNotNil(db);
				[db initialize];
				NSArray *result = [db query:@"SELECT * FROM users"];
				XCTAssertEqual(result.count, 10);
			`,
			assertions: []models.Assertion{
				{Type: "XCTAssertNotNil", Arguments: []string{"db"}},
				{Type: "XCTAssertEqual", Arguments: []string{"result.count", "10"}},
			},
			expectFinding: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method := &models.TestMethod{
				Name:       "testIntegration",
				ClassName:  "IntegrationTests",
				SourceCode: tt.sourceCode,
				Assertions: tt.assertions,
			}
			ctx := ValidationContext{
				TestFile: &models.TestFile{
					Path: "Garazyk/Tests/Integration/IntegrationTests.m",
				},
				TestClass:  &models.TestClass{Name: "IntegrationTests"},
				TestMethod: method,
			}

			finding := rule.checkFinalOutcomeAssertions(method, ctx)
			hasFinding := finding != nil

			if hasFinding != tt.expectFinding {
				t.Errorf("Expected finding=%v, got finding=%v", tt.expectFinding, hasFinding)
			}

			if hasFinding && finding.Severity != tt.expectSeverity {
				t.Errorf("Expected %v severity, got %v", tt.expectSeverity, finding.Severity)
			}
		})
	}
}

func TestIntegrationTestRule_Validate_NonIntegrationTest(t *testing.T) {
	rule := NewIntegrationTestRule()

	method := &models.TestMethod{
		Name:       "testUnitFunction",
		ClassName:  "UnitTests",
		SourceCode: "XCTAssertTrue(YES);",
	}
	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "Garazyk/Tests/Core/UnitTests.m",
		},
		TestClass:  &models.TestClass{Name: "UnitTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)
	if len(findings) != 0 {
		t.Errorf("Expected no findings for non-integration test, got %d", len(findings))
	}
}

func TestIntegrationTestRule_Validate_IntegrationTest(t *testing.T) {
	rule := NewIntegrationTestRule()

	// Integration test with multiple issues
	method := &models.TestMethod{
		Name:      "testIntegrationWorkflow",
		ClassName: "IntegrationTests",
		SourceCode: `
			// Only uses database (single component)
			PDSDatabase *db = [PDSDatabase new];
			[db query:@"SELECT * FROM users"];
			// No cleanup
			// No assertions
		`,
		Assertions: []models.Assertion{},
	}
	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "Garazyk/Tests/Integration/IntegrationTests.m",
		},
		TestClass:  &models.TestClass{Name: "IntegrationTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should have findings for:
	// 1. Single component
	// 2. No assertions
	// Note: cleanup detection may not always trigger depending on heuristics
	if len(findings) < 2 {
		t.Errorf("Expected at least 2 findings, got %d", len(findings))
	}

	// Verify finding types
	foundSingleComponent := false
	foundNoAssertions := false

	for _, finding := range findings {
		if finding.Message == "Integration test appears to exercise only a single component. Integration tests should validate interactions between multiple components." {
			foundSingleComponent = true
		}
		if finding.Message == "Integration test has no assertions to validate outcomes" {
			foundNoAssertions = true
		}
	}

	if !foundSingleComponent {
		t.Error("Expected finding about single component")
	}
	if !foundNoAssertions {
		t.Error("Expected finding about no assertions")
	}
}

func TestIntegrationTestRule_Validate_GoodIntegrationTest(t *testing.T) {
	rule := NewIntegrationTestRule()

	// Well-written integration test
	method := &models.TestMethod{
		Name:      "testIntegrationWorkflow",
		ClassName: "IntegrationTests",
		SourceCode: `
			// Multiple components
			PDSConfiguration *config = [PDSConfiguration new];
			PDSApplication *app = [[PDSApplication alloc] initWithConfiguration:config];
			PDSDatabase *db = [app database];
			HttpServer *server = [app server];
			
			// Start services
			[app start];
			
			// Perform operations
			[db query:@"SELECT * FROM users"];
			HttpResponse *response = [server handleRequest:request];
			
			// Final outcome assertions
			XCTAssertEqual(response.statusCode, 200);
			XCTAssertEqualObjects(response.body, expectedBody);
			
			// Cleanup
			[app stop];
			[db close];
		`,
		Assertions: []models.Assertion{
			{Type: "XCTAssertEqual", Arguments: []string{"response.statusCode", "200"}},
			{Type: "XCTAssertEqualObjects", Arguments: []string{"response.body", "expectedBody"}},
		},
	}
	ctx := ValidationContext{
		TestFile: &models.TestFile{
			Path: "Garazyk/Tests/Integration/IntegrationTests.m",
		},
		TestClass:  &models.TestClass{Name: "IntegrationTests"},
		TestMethod: method,
	}

	findings := rule.Validate(ctx)

	// Should have no findings for a well-written integration test
	if len(findings) != 0 {
		t.Errorf("Expected no findings for good integration test, got %d: %v", len(findings), findings)
	}
}
