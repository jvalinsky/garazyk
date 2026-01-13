# ATProto Compliance Review Skill

## Overview

This skill performs comprehensive compliance reviews of ATProto Personal Data Server (PDS) implementations against official ATProto specifications. It analyzes codebases for adherence to protocol requirements, identifies compliance gaps, and provides structured remediation recommendations.

## Supported Specifications

- **XRPC (HTTP API)** - REST API conventions, authentication, error handling
- **OAuth** - Authorization flows, client registration, DPoP, PKCE
- **Repository** - Data storage, commit structures, sync protocols
- **DID (Decentralized Identifiers)** - Identity resolution and verification
- **Handle** - Account handle resolution and validation
- **Lexicon** - Schema definitions and validation
- **Data Model** - Record structures, CBOR serialization, CAR files
- **NSID** - Namespace identifiers
- **Cryptography** - Required algorithms (secp256k1, P-256, SHA-256) and key formats

## Scripts

Two shell scripts are available:

| Script | Purpose |
|--------|----------|
| `scripts/atproto-compliance-review.sh` | Comprehensive analysis with all output formats |
| `scripts/atproto-compliance-review-simple.sh` | Simplified analysis with executive summary |

## Usage Examples

```bash
# Basic compliance check (comprehensive script)
./scripts/atproto-compliance-review.sh /path/to/pds

# Check current directory with all output formats
./scripts/atproto-compliance-review.sh .

# Executive summary only
./scripts/atproto-compliance-review.sh /path/to/pds all standard executive_summary

# Simplified compliance check
./scripts/atproto-compliance-review-simple.sh /path/to/pds
```

### Arguments (Positional)

| Position | Name | Description | Default |
|----------|------|-------------|--------|
| 1 | `codebase_path` | Path to codebase root | Current directory or repo root |
| 2 | `focus_areas` | Areas to check (comma-separated) | `all` |
| 3 | `compliance_level` | Strictness: basic, standard, comprehensive | `standard` |
| 4 | `output_format` | Report format (see below) | `all` |

### Focus Areas

`oauth`, `xrpc`, `repository`, `did`, `lexicon`, `handle`, `crypto`, `data_model`, `all`

### Output Formats

- `structured_checklist` - Machine-readable checklist with pass/fail status
- `executive_summary` - High-level overview with risk assessment
- `detailed_gap_analysis` - Comprehensive analysis with code references
- `all` - All of the above

## Compliance Check Categories

### 🔐 Authentication & Authorization
- OAuth 2.0 flow implementation
- DPoP proof-of-possession requirements
- PKCE code challenge validation
- Client metadata handling
- Session management and token refresh

### 🌐 HTTP API (XRPC)
- Endpoint path conventions (`/xrpc/{nsid}`)
- Request/response schema validation
- Error response standardization
- Authentication header processing
- CORS and security headers

### 🏛️ Repository & Data
- Record structure compliance
- CID generation and validation
- Repository commit formats
- Sync protocol adherence
- Blob upload/download handling

### 🆔 Identity Systems
- DID document resolution
- Handle resolution and verification
- NSID format validation
- Key management and rotation

### 📋 Lexicon & Schemas
- Schema definition compliance
- Type validation rules
- Parameter and response schemas
- Backward compatibility handling

## Output Formats

### Structured Checklist
Machine-readable compliance checklist with pass/fail status for each requirement.

### Executive Summary
High-level overview of compliance status with risk assessment and priority recommendations.

### Detailed Gap Analysis
Comprehensive analysis of non-compliant areas with specific code references and remediation steps.

## Integration Points

- **CI/CD Pipelines**: Automated compliance checks in build pipelines
- **Development Workflow**: Pre-commit compliance validation
- **Security Audits**: Compliance verification for security reviews
- **Interoperability Testing**: Client compatibility verification

## Error Classification

### Critical (🚨)
- Security vulnerabilities
- Protocol violations that break interoperability
- Data corruption risks

### Important (⚠️)
- Missing optional features that affect usability
- Performance or scalability issues
- Deviation from best practices

### Minor (ℹ️)
- Documentation gaps
- Code style inconsistencies
- Future compatibility concerns

## Remediation Workflow

1. **Gap Identification**: Skill identifies specific compliance gaps
2. **Priority Assessment**: Critical issues addressed first
3. **Code Changes**: Targeted fixes for non-compliant areas
4. **Validation**: Re-run compliance check to verify fixes
5. **Documentation**: Update implementation docs as needed

## Continuous Compliance

For ongoing compliance maintenance:
- Integrate into CI/CD pipeline
- Run on every pull request
- Monitor for specification updates
- Regular compliance audits

This skill ensures ATProto implementations remain compliant with protocol evolution while maintaining interoperability and security standards.