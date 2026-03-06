package validation

// DefaultRules returns all built-in validation rules.
func DefaultRules() []ValidationRule {
	return []ValidationRule{
		&FalsePositiveDetectionRule{},
		&NameAssertionAlignmentRule{},
		&SecurityTestRule{},
		&AsyncTestRule{},
		&PropertyBasedTestRule{},
		&CoverageGapRule{},
		&IntegrationTestRule{},
		&InteropTestRule{},
		&ParserSerializerRule{},
		&AssertionQualityRule{},
		&CharacterizationTestRule{},
		&TestDependencyRule{},
		&MockStubRule{},
		&TestDocumentationRule{},
		&TestFixtureRule{},
		&TestOrganizationRule{},
	}
}
