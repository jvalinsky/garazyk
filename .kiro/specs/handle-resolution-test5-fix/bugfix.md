# Bugfix Requirements Document

## Introduction

The PDS at pds.garazyk.xyz is failing to resolve handles via the HTTPS .well-known endpoint. When attempting to resolve test5.garazyk.xyz (DID: did:plc:5rpam44qoj2eeisejtxmke7e), the endpoint returns a 404 error with the message: `{"error":"Not Found","message":"No handler for GET /.well-known/atproto-did"}`. This indicates the .well-known/atproto-did route is not registered in the PDS server.

Without DNS TXT records configured as fallback, handle resolution completely fails, causing accounts to show as "Unreachable" and preventing proper handle verification. The DID document correctly lists the handle in alsoKnownAs (at://test5.garazyk.xyz) and the service endpoint points to https://pds.garazyk.xyz, but the reverse resolution (handle → DID) is broken.

This is a production issue affecting all accounts on pds.garazyk.xyz.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a client requests GET /.well-known/atproto-did for any handle on the PDS THEN the system returns 404 with error message "No handler for GET /.well-known/atproto-did"

1.2 WHEN HandleResolver attempts to resolve a handle via HTTPS .well-known endpoint THEN the system receives a 404 response and falls back to DNS TXT lookup

1.3 WHEN no DNS TXT record exists for the handle THEN the handle resolution fails completely with "failed to resolve handle" error

1.4 WHEN handle resolution fails THEN the account status shows as "Unreachable" preventing proper handle verification and account discovery

### Expected Behavior (Correct)

2.1 WHEN a client requests GET /.well-known/atproto-did with a valid handle subdomain THEN the system SHALL return 200 with the DID as plain text (e.g., "did:plc:5rpam44qoj2eeisejtxmke7e")

2.2 WHEN the PDS server starts THEN the system SHALL register the /.well-known/atproto-did route handler in the XRPC method registry

2.3 WHEN the .well-known endpoint receives a request for a handle that exists in the PDS database THEN the system SHALL look up the DID for that handle and return it

2.4 WHEN the .well-known endpoint receives a request for a handle that does not exist in the PDS database THEN the system SHALL return 404 with an appropriate error message

2.5 WHEN HandleResolver successfully resolves a handle via the .well-known endpoint THEN the system SHALL cache the result and mark the account as "Reachable"

### Unchanged Behavior (Regression Prevention)

3.1 WHEN resolving handles for other accounts that currently work THEN the system SHALL CONTINUE TO resolve them successfully via HTTPS or DNS methods

3.2 WHEN the .well-known endpoint returns a valid DID for working handles THEN the system SHALL CONTINUE TO cache and return that DID without attempting DNS fallback

3.3 WHEN rate limiting is triggered for handle resolution THEN the system SHALL CONTINUE TO enforce rate limits and return appropriate errors

3.4 WHEN SSRF protection detects private IP addresses THEN the system SHALL CONTINUE TO block resolution attempts to prevent security vulnerabilities

3.5 WHEN handle validation fails for invalid formats THEN the system SHALL CONTINUE TO reject invalid handles before attempting resolution
