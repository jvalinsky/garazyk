# Bugfix Requirements Document

## Introduction

When records are created and stored in the PDS, the computed CID doesn't match what external clients (like pdsls.dev) compute when they re-encode the same record content. This causes record verification failures and breaks interoperability with AT Protocol clients.

The root cause is that the DAG-CBOR encoding implementation in `ATProtoCBORSerialization` does not sort map keys according to the canonical DAG-CBOR specification, which requires keys to be sorted by their CBOR-encoded byte representation (length-first, then lexicographically).

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a record is created with fields like `{"text": "...", "$type": "...", "createdAt": "...", "langs": [...]}` THEN the system produces a CID that differs from external clients re-encoding the same content

1.2 WHEN the PDS encodes a record to DAG-CBOR THEN map keys are not sorted according to canonical DAG-CBOR rules (CBOR-encoded byte length first, then lexicographic)

1.3 WHEN external verification tools compute the CID for a stored record THEN they produce a different CID hash due to different key ordering

### Expected Behavior (Correct)

2.1 WHEN a record is created with any field ordering THEN the system SHALL produce a CID that matches what external clients compute for the same content

2.2 WHEN the PDS encodes a record to DAG-CBOR THEN map keys SHALL be sorted by their CBOR-encoded byte representation (length-first, then lexicographically) per the DAG-CBOR canonical encoding specification

2.3 WHEN external verification tools compute the CID for a stored record THEN they SHALL produce the same CID hash as the PDS

### Unchanged Behavior (Regression Prevention)

3.1 WHEN records are created, retrieved, or deleted THEN the system SHALL CONTINUE TO perform all existing operations successfully

3.2 WHEN records contain nested objects or arrays THEN the system SHALL CONTINUE TO encode and decode them correctly

3.3 WHEN records contain various data types (strings, numbers, booleans, null) THEN the system SHALL CONTINUE TO handle them correctly

3.4 WHEN CIDs are computed for non-record data structures THEN the system SHALL CONTINUE TO produce correct CIDs
