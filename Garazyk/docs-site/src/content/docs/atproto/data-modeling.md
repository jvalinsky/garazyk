---
title: Data Modeling and Validation
description: Lexicon schemas, repository records, and validation boundaries
---

AT Protocol services exchange data described by lexicons. A lexicon document
assigns an NSID and defines one or more schemas for XRPC methods, repository
records, or reusable object types.

Lexicons give independent PDS, relay, AppView, and client implementations a
shared wire contract. They do not replace application authorization or semantic
checks; those remain the endpoint's responsibility.

## Lexicon structure

A lexicon has an `id`, a revision number, and a `defs` map. The `main`
definition is the default schema for the NSID. Other definitions can be
referenced as `lex:<nsid>#<definition>`.

Common definition types include:

- `query`, `procedure`, and `subscription` for XRPC methods
- `record` for repository collections
- `object`, `array`, `string`, `integer`, `boolean`, `bytes`, `blob`, `ref`, and
  `union`

Constraints can specify required object fields, string byte and grapheme limits,
numeric ranges, array sizes, known values, and referenced schemas. For example,
`app.bsky.feed.post` constrains `text` by both UTF-8 byte length and grapheme
count.

## Repository records

A record collection is identified by an NSID such as `app.bsky.feed.post`. Each
stored record also has a record key, producing an AT URI of the form:

```text
at://<repository-did>/<collection-nsid>/<record-key>
```

The record is encoded as DAG-CBOR before its CID is calculated. The repository
MST maps `<collection-nsid>/<record-key>` to that record CID.

Unknown lexicon fields may be allowed by an open object schema. Validators must
follow the schema's closed/open behavior rather than rejecting every
unrecognized key.

## Garazyk validation

`ATProtoLexiconRegistry` loads and indexes lexicon schemas.
`ATProtoLexiconValidator` resolves references and applies type and constraint
checks. Repository write paths use the registry for known collections before
encoding records and updating the MST.

A request normally crosses several boundaries:

1. The HTTP parser enforces framing and body-size limits.
2. The XRPC layer parses query parameters or the declared input encoding.
3. Authentication code verifies the caller and method-specific scope.
4. Lexicon validation checks the input or record shape.
5. The service applies semantic rules and performs the storage mutation.
6. The response encoder emits the declared output content type.

Each boundary should return its own error category. A malformed body is
different from an authenticated caller lacking permission, and both are
different from a database failure.

## Objective-C representation

Foundation values represent decoded JSON and DAG-CBOR data:

- `NSDictionary<NSString *, id> *` for objects
- `NSArray *` for arrays
- `NSString *`, `NSNumber *`, and `NSData *` for scalar and byte values
- `NSNull` for an explicit null where the schema permits it

Code should check both the Objective-C class and the lexicon constraint before
using a value. `NSNumber`, in particular, can represent booleans and several
numeric encodings; class membership alone does not prove the expected lexicon
type.

Keep validation at ingress and import boundaries. Internal code may rely on
validated types only when the boundary and its guarantees are explicit.
