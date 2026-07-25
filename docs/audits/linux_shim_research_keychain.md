# Apple Keychain API & Attribute Serialization

## Overview

The Apple Keychain Services API (e.g., `SecItemAdd`, `SecItemUpdate`, `SecItemCopyMatching`, `SecItemDelete`) provides a secure storage mechanism for sensitive data on macOS, iOS, tvOS, and watchOS. When interacting with the Keychain, developers use dictionaries of attributes to define the item being added, updated, or queried. These attributes are represented as CoreFoundation (`CFType`) or Foundation (`NSObject`) types.

When implementing a Linux shim or bridging this API to another environment (e.g., cross-platform services), serializing these attribute dictionaries correctly is critical. This document explains the types of data stored in Keychain item attributes, the limitations of JSON serialization, and why Property Lists (PLIST) are the native and robust choice for this task.

## Keychain Attribute Data Types

Keychain attributes define the metadata and the payload of a secure item. These attributes use constants (like `kSecAttrAccount`, `kSecValueData`) as keys, and their values must be specific `CFType` (CoreFoundation) or `NSObject` (Foundation) objects. 

Key data types used in Keychain attributes include:

1.  **`CFString` / `NSString`**: Used for textual metadata.
    *   `kSecAttrAccount` (Account name)
    *   `kSecAttrService` (Service name)
    *   `kSecAttrAccessGroup` (Access group)
    *   `kSecAttrLabel` (User-visible label)

2.  **`CFData` / `NSData`**: Used for raw binary data.
    *   `kSecValueData`: The actual secure payload (e.g., the password, crypto key, or token).
    *   `kSecAttrGeneric`: A user-defined attribute often used to store custom binary data or serialized structures related to the item.

3.  **`CFDate` / `NSDate`**: Used for timestamps (managed primarily by the system).
    *   `kSecAttrCreationDate`: The timestamp when the item was initially created.
    *   `kSecAttrModificationDate`: The timestamp of the item's most recent modification.

4.  **`CFNumber` / `NSNumber`** and **`CFBoolean`**: Used for numeric flags and boolean options.
    *   `kSecReturnAttributes` (Boolean indicating if attributes should be returned in a query).
    *   `kSecReturnData` (Boolean indicating if the raw data should be returned).

When performing a `SecItemCopyMatching` query with `kSecReturnAttributes = true`, the system returns a dictionary containing these underlying types.

## The Flaw of `NSJSONSerialization`

A common mistake when bridging Keychain data (e.g., passing it from an Objective-C/Swift layer to a Node.js/Rust/Go process or across a network) is attempting to serialize the attribute dictionary using `NSJSONSerialization`.

This approach is fundamentally flawed due to the strict limitations of the JSON specification and Apple's JSON serializer:

1.  **No Native Date Support**: JSON has no native `Date` type. `NSJSONSerialization` explicitly **does not support** `NSDate` or `CFDate`. If you attempt to serialize a dictionary containing `kSecAttrCreationDate` or `kSecAttrModificationDate`, `NSJSONSerialization` will throw an exception (`NSInvalidArgumentException: Invalid type in JSON write`).
2.  **No Native Binary Data Support**: JSON has no native binary type. `NSJSONSerialization` **does not support** `NSData` or `CFData`. To serialize `kSecValueData` or `kSecAttrGeneric` to JSON, the data must be manually extracted, Base64-encoded, and converted to an `NSString` before serialization.
3.  **Loss of Type Fidelity**: When decoding JSON, an external system cannot distinguish between a Base64-encoded string representing `NSData`, an ISO8601 string representing an `NSDate`, or just a standard `NSString`, without a secondary schema mapping.

To use JSON, developers are forced to write fragile middleware to traverse the dictionary, convert `NSDate` to ISO8601 strings, and `NSData` to Base64 strings prior to serialization, and perform the exact inverse upon deserialization.

## The Solution: `NSPropertyListSerialization`

Apple's Property List (plist) format was explicitly designed to serialize CoreFoundation and Foundation types seamlessly. `NSPropertyListSerialization` is the correct, native choice for serializing Keychain attribute dictionaries.

Property lists natively support the following types without any manual conversion:
*   `NSString`
*   `NSNumber`
*   **`NSData`**
*   **`NSDate`**
*   `NSArray`
*   `NSDictionary`

### Advantages of Property List Serialization

1.  **Zero-Conversion Serialization**: You can pass the dictionary returned by `SecItemCopyMatching` directly into `NSPropertyListSerialization` without traversing or mutating the dictionary. `CFDate` and `CFData` are handled natively.
2.  **Format Flexibility**: Property lists can be serialized into an XML format (human-readable and easily parsed by non-Apple XML/Plist libraries) or a Binary format (compact, highly performant, and standard for inter-process communication on Apple platforms).
3.  **Strict Type Preservation**: Upon deserialization (e.g., using `plist` parsing libraries in Node.js, Python, or Rust), the target environment natively receives `Date` objects and `Buffer`/Byte arrays, preserving the exact type semantics required to bridge the data back into the underlying OS APIs.

### Conclusion

When implementing shims, mocks, or cross-platform bridges for the Apple Keychain API, never use `NSJSONSerialization` for the attribute dictionaries. The presence of `CFDate` and `CFData` guarantees serialization failures or necessitates brittle type-casting workarounds. `NSPropertyListSerialization` accurately preserves the memory model of the Keychain API and allows for robust, error-free data transport.
