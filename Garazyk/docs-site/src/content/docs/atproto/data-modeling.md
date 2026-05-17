---
title: Data Modeling & Validation
description: Parsing Lexicons, verifying XRPC schemas, and ensuring network-wide data integrity
---

The AT Protocol is inherently, powerfully distributed. When millions of different clients, distinct
Personal Data Server (PDS) instances, global AppViews, and Relays all talk to each other
simultaneously over the internet, they absolutely cannot simply hurl unstructured, arbitrary JSON
across the wire and hope the receiver understands it.

To ensure absolute interoperability across the federation, all inter-server and client-server
communication is strictly typed via a unified JSON schema system called **Lexicons**.

## Understanding Lexicons

A single `.json` Lexicon file completely and definitively describes an RPC method, an Object schema,
or a database Record. It acts as a contractual interface between the client and the server.

For example, the `app.bsky.feed.post` lexicon defines exactly what a globally recognized "Tweet" (or
"Skeet") looks like on the network:

- **`id`**: `app.bsky.feed.post` (The procedure, namespace, or record name identifier)
- **`type`**: `record` (Denotes this schema describes data stored persistently in a user's
  cryptographic repository, rather than a transient RPC query)
- **`schema`**: Defines strictly what properties the JSON payload MUST or MAY contain.
  - E.g., `text` must be a string with a maximum of 300 characters.
  - E.g., `createdAt` must be a datetime formatted precisely as an ISO8601 string.
  - E.g., `embed` can optionally contain a specific union of an image object or a quoted post.

If you are implementing a server like `ATProtoPDS`, you must enforce these schemas rigidly on
_every_ incoming HTTP request before passing any data to your underlying database or business
routing layer. Failing to validate Lexicons means you risk storing malformed data that will break
downstream Relays (AppViews) and corrupt the user's Merkle Search Tree (MST).

## Dynamic Validation in Objective-C

In a high-level JavaScript or TypeScript runtime environment, developers typically utilize powerful
runtime libraries like `Zod` or `AJV` to elegantly validate incoming JSON payloads against defined
schemas.

Because `ATProtoPDS` is written in low-level, high-performance Objective-C, we cannot rely on
Node.js luxuries. Instead, we use the iOS/macOS Foundation framework's rigorously battle-tested
`NSJSONSerialization` to parse incoming HTTP/1.1 body bytes securely into raw `NSDictionary` or
`NSArray` heaps. _Then_, we manually algorithmically validate them against our custom Lexicon parser
engine.

```objc
// Example simplified snippet representing core input validation inside an XrpcHandler
- (BOOL)validateBody:(NSDictionary *)json 
         withLexicon:(PDSLexicon *)lexicon 
               error:(NSError **)error {
               
    // 1. Check if all strictly required fields declared by the Lexicon exist
    for (NSString *key in lexicon.requiredProperties) {
        if (!json[key]) {
            // Immediately explicitly reject the HTTP request with a 400 Bad Request
            *error = [PDSValidationError errorWithReason:[NSString stringWithFormat:@"Missing required param: %@", key]];
            return NO;
        }
    }
    
    // 2. Iterate through the parsed NSDictionary payload to rigorously enforce:
    //    - string length character limits
    //    - maximum/minimum integer bounds
    //    - exact array item constraints and depth limits
    for (NSString *key in json) {
        PDSConstraint *constraint = lexicon.properties[key];
        
        // If a client sends an unknown key not defined in the schema, it can optionally be rejected.
        if (constraint) {
            if (![constraint validateValue:json[key]]) {
                *error = [PDSValidationError errorWithReason:[NSString stringWithFormat:@"Constraint violated for field: %@", key]];
                return NO;
            }
        }
    }
    
    return YES;
}
```

### The `XrpcHandler` Lifecycle

By heavily utilizing the `XrpcHandler` abstract classes (such as `XrpcRepoPack` or
`XrpcIdentityPack`), the PDS architectural design ensures that endpoint route handlers _only_
execute application logic when the incoming data correctly matches the ATProto standard 1-to-1.

The lifecycle of an incoming repository mutation travels through a strict sieve:

1. **Routing:** The `HttpRouter` reads the absolute URL (e.g.,
   `/xrpc/com.atproto.repo.createRecord`) and maps the invocation to the correct Objective-C
   `XrpcHandler` subclass.
2. **Auth Verification:** The handler rigorously mathematically asserts the `Authorization: Bearer`
   JWT token or validates the complex DPoP cryptographic signature.
3. **Parse & Validate:** The raw incoming JSON body bytes are parsed into objects and ruthlessly
   validated against the cached Lexicon schema constraints. The request drops here if it is
   malformed.
4. **Execute:** _Only now_, perfectly confident in the structural integrity of the authenticated
   data, does the Objective-C controller code run to physically mutate the local SQLite `.db` actor
   file.
5. **Serialize:** The outgoing server response is serialized beautifully back into either formatted
   JSON or raw DAG-CBOR (Content Addressable aRchives) bytes, based entirely on the Lexicon's
   rigidly defined return response types.

By front-loading incredibly aggressive validation, `ATProtoPDS` protects the wider Bluesky network
from data pollution.
