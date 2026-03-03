# TOTP and WebAuthn

## Overview

The PDS supports two-factor authentication (2FA) using TOTP (Time-based One-Time Password) and WebAuthn (passwordless authentication). These mechanisms provide additional security beyond username/password authentication.

## TOTP (Time-based One-Time Password)

### Overview

TOTP generates time-based one-time passwords using a shared secret:

```
Shared Secret (Base32 encoded)
    ↓
Time Counter (current time / 30 seconds)
    ↓
HMAC-SHA1(secret, counter)
    ↓
6-digit code (valid for 30 seconds)
```

### TOTP Service

```objc
@interface TOTPService : NSObject

// Setup
- (NSString *)generateSecret;
- (NSString *)getQRCodeURL:(NSString *)accountName issuer:(NSString *)issuer;

// Verification
- (BOOL)verifyCode:(NSString *)code withSecret:(NSString *)secret error:(NSError **)error;

// Backup codes
- (NSArray *)generateBackupCodes;
- (BOOL)verifyBackupCode:(NSString *)code forDid:(NSString *)did error:(NSError **)error;

@end
```

### Enabling TOTP

```objc
// 1. Generate secret
NSString *secret = [totpService generateSecret];

// 2. Get QR code URL
NSString *qrCodeUrl = [totpService getQRCodeURL:@"user@example.com"
                                        issuer:@"PDS"];

// 3. Display QR code to user
// User scans with authenticator app

// 4. Verify code
NSString *userCode = @"123456";  // From authenticator app
NSError *error = nil;
BOOL valid = [totpService verifyCode:userCode withSecret:secret error:&error];

if (valid) {
    // 5. Store secret
    [self storeTOTPSecret:secret forDid:userDid];
    
    // 6. Generate backup codes
    NSArray *backupCodes = [totpService generateBackupCodes];
    [self storeBackupCodes:backupCodes forDid:userDid];
}
```

### TOTP Storage

```sql
CREATE TABLE totp_secrets (
    did TEXT PRIMARY KEY,
    secret TEXT NOT NULL,
    enabled BOOLEAN DEFAULT 0,
    created_at DATETIME NOT NULL,
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE TABLE backup_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    code TEXT NOT NULL,
    used BOOLEAN DEFAULT 0,
    used_at DATETIME,
    FOREIGN KEY (did) REFERENCES accounts(did)
);
```

## WebAuthn

### Overview

WebAuthn enables passwordless authentication using hardware security keys or biometric authentication:

```
User Device
    ↓
WebAuthn Authenticator (FIDO2 key, biometric, etc.)
    ↓
Attestation/Assertion
    ↓
PDS Verification
    ↓
Authentication Success
```

### WebAuthn Service

```objc
@interface WebAuthnVerifier : NSObject

// Registration
- (NSString *)generateRegistrationChallenge:(NSString *)did error:(NSError **)error;
- (BOOL)verifyRegistrationResponse:(NSDictionary *)response
                        challenge:(NSString *)challenge
                              did:(NSString *)did
                            error:(NSError **)error;

// Authentication
- (NSString *)generateAuthenticationChallenge:(NSString *)did error:(NSError **)error;
- (BOOL)verifyAuthenticationResponse:(NSDictionary *)response
                          challenge:(NSString *)challenge
                                did:(NSString *)did
                              error:(NSError **)error;

@end
```

### WebAuthn Registration

```objc
// 1. Generate registration challenge
NSError *error = nil;
NSString *challenge = [webAuthnVerifier generateRegistrationChallenge:userDid error:&error];

// 2. Send challenge to client
NSDictionary *registrationOptions = @{
    @"challenge": challenge,
    @"rp": @{
        @"name": @"PDS",
        @"id": @"pds.example.com"
    },
    @"user": @{
        @"id": userDid,
        @"name": userEmail,
        @"displayName": userName
    },
    @"pubKeyCredParams": @[
        @{@"type": @"public-key", @"alg": @-7}  // ES256
    ],
    @"timeout": @60000,
    @"attestation": @"direct"
};

// 3. Client creates credential
// (handled by browser/client)

// 4. Verify registration response
NSDictionary *registrationResponse = /* from client */;
BOOL success = [webAuthnVerifier verifyRegistrationResponse:registrationResponse
                                                  challenge:challenge
                                                        did:userDid
                                                      error:&error];

if (success) {
    // 5. Store credential
    [self storeWebAuthnCredential:registrationResponse forDid:userDid];
}
```

### WebAuthn Authentication

```objc
// 1. Generate authentication challenge
NSError *error = nil;
NSString *challenge = [webAuthnVerifier generateAuthenticationChallenge:userDid error:&error];

// 2. Send challenge to client
NSDictionary *authenticationOptions = @{
    @"challenge": challenge,
    @"timeout": @60000,
    @"userVerification": @"preferred"
};

// 3. Client creates assertion
// (handled by browser/client)

// 4. Verify authentication response
NSDictionary *authenticationResponse = /* from client */;
BOOL success = [webAuthnVerifier verifyAuthenticationResponse:authenticationResponse
                                                   challenge:challenge
                                                         did:userDid
                                                       error:&error];

if (success) {
    // 5. Generate session token
    NSString *sessionToken = [self generateSessionToken:userDid];
    return @{@"sessionToken": sessionToken};
}
```

### WebAuthn Storage

```sql
CREATE TABLE webauthn_credentials (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    did TEXT NOT NULL,
    credential_id BLOB NOT NULL,
    public_key BLOB NOT NULL,
    sign_count INTEGER DEFAULT 0,
    created_at DATETIME NOT NULL,
    last_used DATETIME,
    UNIQUE(did, credential_id),
    FOREIGN KEY (did) REFERENCES accounts(did)
);

CREATE TABLE webauthn_challenges (
    challenge TEXT PRIMARY KEY,
    did TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    expires_at DATETIME NOT NULL,
    used BOOLEAN DEFAULT 0,
    FOREIGN KEY (did) REFERENCES accounts(did)
);
```

## 2FA Enrollment Flow

```
1. User enables 2FA
   ↓
2. Choose method (TOTP or WebAuthn)
   ↓
3. For TOTP:
   - Generate secret
   - Display QR code
   - User scans with authenticator
   - Verify code
   - Generate backup codes
   ↓
4. For WebAuthn:
   - Generate challenge
   - User registers key
   - Verify registration
   - Store credential
   ↓
5. 2FA enabled
```

## 2FA Login Flow

```
1. User enters username/password
   ↓
2. Credentials verified
   ↓
3. Check if 2FA enabled
   ↓
4. If TOTP:
   - Prompt for code
   - Verify code
   - Generate session token
   ↓
5. If WebAuthn:
   - Generate challenge
   - User authenticates with key
   - Verify assertion
   - Generate session token
   ↓
6. Login complete
```

## Best Practices

1. **TOTP Setup**
   - Generate strong secrets (256-bit)
   - Display QR code for easy setup
   - Generate backup codes
   - Store backup codes securely

2. **TOTP Verification**
   - Accept codes within ±1 time window
   - Prevent code reuse
   - Rate limit verification attempts
   - Log verification failures

3. **WebAuthn Setup**
   - Validate attestation
   - Store credential ID and public key
   - Track sign count for cloned key detection
   - Support multiple credentials per user

4. **WebAuthn Verification**
   - Verify challenge matches
   - Verify signature
   - Check sign count increases
   - Detect cloned keys

5. **Backup Codes**
   - Generate 10-12 codes
   - Store hashed codes
   - Mark as used after use
   - Regenerate periodically

## Common Patterns

### Enabling TOTP

```objc
// 1. Generate secret
NSString *secret = [totpService generateSecret];

// 2. Display QR code
NSString *qrUrl = [totpService getQRCodeURL:userEmail issuer:@"PDS"];
[self displayQRCode:qrUrl];

// 3. Verify code
NSString *userCode = [self promptForCode];
BOOL valid = [totpService verifyCode:userCode withSecret:secret error:&error];

if (valid) {
    // 4. Store secret
    [database executeUpdate:@"INSERT INTO totp_secrets (did, secret, enabled) VALUES (?, ?, 1)"
                withParameters:@[userDid, secret]];
    
    // 5. Generate backup codes
    NSArray *backupCodes = [totpService generateBackupCodes];
    for (NSString *code in backupCodes) {
        [database executeUpdate:@"INSERT INTO backup_codes (did, code) VALUES (?, ?)"
                    withParameters:@[userDid, code]];
    }
}
```

### Verifying TOTP During Login

```objc
// 1. Get TOTP secret
NSArray *result = [database executeQuery:@"SELECT secret FROM totp_secrets WHERE did = ?"
                            withParameters:@[userDid]];

if (result.count == 0) {
    // TOTP not enabled
    return YES;
}

NSString *secret = result[0][@"secret"];

// 2. Prompt for code
NSString *userCode = [self promptForTOTPCode];

// 3. Verify code
NSError *error = nil;
BOOL valid = [totpService verifyCode:userCode withSecret:secret error:&error];

if (!valid) {
    // Try backup code
    NSArray *backupResult = [database executeQuery:
        @"SELECT id FROM backup_codes WHERE did = ? AND code = ? AND used = 0"
        withParameters:@[userDid, userCode]];
    
    if (backupResult.count > 0) {
        // Mark backup code as used
        [database executeUpdate:@"UPDATE backup_codes SET used = 1, used_at = datetime('now') WHERE id = ?"
                    withParameters:@[backupResult[0][@"id"]]];
        return YES;
    }
    
    return NO;
}

return YES;
```

## See Also

- [JWT Tokens](./jwt-tokens)
- [OAuth 2.0 with DPoP](./oauth2-dpop)
- [Key Rotation](./key-rotation)
