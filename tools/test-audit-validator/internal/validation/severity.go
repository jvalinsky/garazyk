package validation

// Severity represents the severity level of a validation finding
type Severity int

const (
	// CRITICAL indicates test provides false confidence - fix immediately
	CRITICAL Severity = iota
	// HIGH indicates test likely doesn't test what it claims - review and fix
	HIGH
	// MEDIUM indicates test has potential gaps - consider improving
	MEDIUM
	// LOW indicates minor quality issues - improve when convenient
	LOW
)

// String returns the string representation of the severity level
func (s Severity) String() string {
	switch s {
	case CRITICAL:
		return "critical"
	case HIGH:
		return "high"
	case MEDIUM:
		return "medium"
	case LOW:
		return "low"
	default:
		return "unknown"
	}
}

// ParseSeverity converts a string to a Severity level
func ParseSeverity(s string) (Severity, bool) {
	switch s {
	case "critical":
		return CRITICAL, true
	case "high":
		return HIGH, true
	case "medium":
		return MEDIUM, true
	case "low":
		return LOW, true
	default:
		return LOW, false
	}
}
