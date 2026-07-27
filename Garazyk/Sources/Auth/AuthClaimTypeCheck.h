// SPDX-FileCopyrightText: 2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 @function AuthTypedValue

 @abstract Fail-closed accessor for a value inside attacker-supplied JSON.

 @discussion `NSDictionary` and `NSArray` both implement `-copyWithZone:`, so
 assigning an untyped JSON value straight into a `copy` property (e.g.
 `NSString *`) succeeds even when the JSON value is the wrong type; the
 failure only surfaces later as an unrecognized-selector crash at the first
 message send. This accessor closes that gap at the parse boundary: it never
 returns a value whose class does not match `expectedClass`.

 Static inline (not an exported symbol) so it can be shared by translation
 units in different static libraries without introducing a link-time
 dependency between them.

 @param dictionary The parsed JSON object being read.
 @param key The claim/field name to read.
 @param expectedClass The Objective-C class the value must be a kind of.
 @param typeMismatch Set to YES (never reset to NO) when `key` is present
        with a value that is not a kind of `expectedClass`. Pass the same
        `BOOL *` across a sequence of calls to accumulate a single
        reject/accept decision for a whole dictionary.
 @return The value for `key` if absent, or if present and of the expected
         type; nil otherwise.
 */
static inline id _Nullable AuthTypedValue(NSDictionary<NSString *, id> *dictionary,
                                           NSString *key,
                                           Class expectedClass,
                                           BOOL *typeMismatch) {
    id value = dictionary[key];
    if (value == nil) {
        return nil;
    }
    if (![value isKindOfClass:expectedClass]) {
        if (typeMismatch != NULL) {
            *typeMismatch = YES;
        }
        return nil;
    }
    return value;
}

NS_ASSUME_NONNULL_END
