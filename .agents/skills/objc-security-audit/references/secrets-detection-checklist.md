# Secrets Detection Checklist

Use this checklist while validating candidates from `scan_secrets.sh`.

## Hardcoded credentials
- Verify password strings are not production credentials.
- Check if strings are test fixtures with obvious placeholder values.
- Confirm secrets are loaded from environment or keychain at runtime.
- Verify no credentials in version control history.

## API keys and tokens
- Verify API keys are not hardcoded in source.
- Check for API keys in configuration files committed to repo.
- Confirm keys are rotated and not long-lived.
- Verify keys have minimal required permissions.

## Private keys and certificates
- Verify no private keys in source code.
- Check for certificate files (.pem, .key) in repo.
- Confirm keys are stored in secure keychain or HSM.
- Verify key rotation procedures exist.

## Connection strings
- Verify no credentials in connection strings.
- Check for database passwords in URLs.
- Confirm connection strings use integrated auth where possible.
- Verify connection strings are not logged.

## Environment files
- Verify .env files are in .gitignore.
- Check for .env.example with safe placeholder values.
- Confirm no production .env files committed.
- Verify secrets are injected at deploy time, not baked in.

## Remediation steps
1. Remove secrets from source code immediately.
2. Rotate any exposed credentials.
3. Add patterns to pre-commit hooks.
4. Scan git history with gitleaks/trufflehog.
5. Consider using git-secrets or detect-secrets.
