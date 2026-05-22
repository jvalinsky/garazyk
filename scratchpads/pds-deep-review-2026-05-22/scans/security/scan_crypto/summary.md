# Objective-C Cryptographic Security Scan

- Root: .
- Scan path: ./Garazyk/Sources
- Generated: 2026-05-22T18:10:03Z

## Counts
- Weak hash usage (MD5/SHA1): 4
- Weak encryption (DES/3DES/RC4): 8
- Hardcoded key references: 17
- Hardcoded IV references: 4
- Timing-vulnerable comparisons: 46
- Weak random usage: 2
- ECB mode usage: 1
- Secure random usage: 26

## Files with potential crypto issues
- ./Garazyk/Sources/AppView/Services/ContactService.m
- ./Garazyk/Sources/AppView/Services/GraphService.m
- ./Garazyk/Sources/Auth/OAuth2.m
- ./Garazyk/Sources/Auth/OAuth2Handler.m
- ./Garazyk/Sources/Auth/OAuthClientAuthPolicy.m
- ./Garazyk/Sources/Auth/OAuthProvider/OAuthProvider.m
- ./Garazyk/Sources/Auth/PDSAppleKeyManager.m
- ./Garazyk/Sources/Auth/PDSOpenSSLSessionKeyManager.m
- ./Garazyk/Sources/Blob/MimeTypeValidator.m
- ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m
- ./Garazyk/Sources/CLI/PDSCLIAdminCommand.m
- ./Garazyk/Sources/CLI/PDSCLIDispatcher.m
- ./Garazyk/Sources/CLI/PDSCLIInputHelper.m
- ./Garazyk/Sources/CLI/PDSCLIOAuthCommand.m
- ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonCryptor.h
- ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonDigest.h
- ./Garazyk/Sources/Compat/PlatformShims/CoreFoundation/CFBase.h
- ./Garazyk/Sources/Core/ATProtoCBORSerialization.m
- ./Garazyk/Sources/Core/ATProtoDagCBOR.m
- ./Garazyk/Sources/Core/ATProtoValidator.m
- ./Garazyk/Sources/Core/ATURI.m
- ./Garazyk/Sources/Core/DID.m
- ./Garazyk/Sources/Database/Utils/ATProtoDatabaseUtilities.h
- ./Garazyk/Sources/Email/PDSEmailProviderFactory.m
- ./Garazyk/Sources/Lexicon/ATProtoLexiconValidator.m
- ./Garazyk/Sources/Network/SSRFValidator.m
- ./Garazyk/Sources/Network/WebSocketUpgradeHandler.m
- ./Garazyk/Sources/Network/XrpcAdminPack.m
- ./Garazyk/Sources/Network/XrpcAuthHelper.m
- ./Garazyk/Sources/Repository/CBOR.m
- ./Garazyk/Sources/Repository/MST.m
- ./Garazyk/Sources/Security/PDSKeyEnvelope.m
- ./Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m
- ./Garazyk/Sources/Video/VideoJWTAuthProvider.m

## Detailed findings

### Weak hash algorithms (MD5/SHA1)
  ./Garazyk/Sources/Sync/WebSocket/WebSocketConnection.m:391:    CC_SHA1(data.bytes, (CC_LONG)data.length, hash);
  ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonDigest.h:24:#define CC_SHA1(data, len, md) SHA1((const unsigned char *)(data), (size_t)(len), (md))
  ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonDigest.h:25:#define CC_MD5(data, len, md) MD5((const unsigned char *)(data), (size_t)(len), (md))
  ./Garazyk/Sources/Network/WebSocketUpgradeHandler.m:100:    CC_SHA1(cStr, (CC_LONG)strlen(cStr), digest);

### Timing-vulnerable secret comparisons
  ./Garazyk/Sources/Lexicon/ATProtoLexiconValidator.m:469:    } else if ([format isEqualToString:@"record-key"]) {
  ./Garazyk/Sources/Email/PDSEmailProviderFactory.m:193:        if ([source isEqualToString:@"keychain"]) {
  ./Garazyk/Sources/CLI/PDSCLIAdminCommand.m:150:        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:613:        if (memcmp(bytes, "RIFF", 4) == 0) {
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:614:            if (memcmp(bytes + 8, "WEBP", 4) == 0) return @"image/webp";
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:615:            if (memcmp(bytes + 8, "AVI ", 4) == 0) return @"video/avi";
  ./Garazyk/Sources/Blob/MimeTypeValidator.m:616:            if (memcmp(bytes + 8, "WAVE", 4) == 0) return @"audio/wav";
  ./Garazyk/Sources/CLI/PDSCLIInputHelper.m:17:    if (nonInteractive && (strcmp(nonInteractive, "1") == 0 || strcmp(nonInteractive, "true") == 0)) {
  ./Garazyk/Sources/CLI/PDSCLIAccountCommand.m:222:        } else if ([arg isEqualToString:@"--password"] || [arg isEqualToString:@"-p"]) {
  ./Garazyk/Sources/CLI/PDSCLIOAuthCommand.m:98:        } else if ([arg isEqualToString:@"--secret"] || [arg isEqualToString:@"-s"]) {
  ./Garazyk/Sources/CLI/PDSCLIDispatcher.m:304:        if ([key isEqualToString:[self.commands[key] name]]) {
  ./Garazyk/Sources/AppView/Services/ContactService.m:112:    if ([token isEqualToString:@"test-import-token"] && ([allowHTTP isEqualToString:@"1"] || [allowHTTP isEqualToString:@"true"])) {
  ./Garazyk/Sources/Core/DID.m:393:            if (!selectedMethod && [methodType isKindOfClass:[NSString class]] && [methodType isEqualToString:@"Multikey"]) {
  ./Garazyk/Sources/Core/ATProtoCBORSerialization.m:120:    if (strcmp(objCType, @encode(float)) == 0 ||
  ./Garazyk/Sources/Core/ATProtoCBORSerialization.m:121:        strcmp(objCType, @encode(double)) == 0) {
  ... and 31 more

### ECB mode usage
  ./Garazyk/Sources/Compat/PlatformShims/CommonCrypto/CommonCryptor.h:28:    kCCOptionECBMode = 2

## Notes
- SHA1/MD5 may be acceptable for non-security uses (checksums, dedup).
- Verify context before flagging as vulnerability.
- Timing attacks require network access; prioritize based on threat model.
- arc4random() without arguments is often used for non-crypto purposes.
