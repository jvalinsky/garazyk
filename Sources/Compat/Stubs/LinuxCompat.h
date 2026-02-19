// Linux/GNUstep compatibility definitions
#ifndef LINUX_COMPAT_H
#define LINUX_COMPAT_H

#ifdef GNUSTEP

// __unused attribute (may not be recognized in @catch context)
#ifndef __unused
#define __unused __attribute__((unused))
#endif

// Deprecation macros (no-op on GNUstep)
#ifndef DEPRECATED_MSG_ATTRIBUTE
#define DEPRECATED_MSG_ATTRIBUTE(msg)
#endif

#ifndef NS_SWIFT_NAME
#define NS_SWIFT_NAME(name)
#endif

#ifndef NS_REFINED_FOR_SWIFT
#define NS_REFINED_FOR_SWIFT
#endif

#ifndef NS_SWIFT_UNAVAILABLE
#define NS_SWIFT_UNAVAILABLE(msg)
#endif

// NSErrorUserInfoKey type alias (GNUstep doesn't have this)
// This will be defined after Foundation is included
#ifndef NSErrorUserInfoKey
#define NSErrorUserInfoKey NSString*
#endif

// API availability macros
#ifndef API_AVAILABLE
#define API_AVAILABLE(...)
#endif

#ifndef API_UNAVAILABLE
#define API_UNAVAILABLE(...)
#endif

#ifndef API_DEPRECATED
#define API_DEPRECATED(...)
#endif

#ifndef API_DEPRECATED_WITH_REPLACEMENT
#define API_DEPRECATED_WITH_REPLACEMENT(...)
#endif

#endif // GNUSTEP

#endif // LINUX_COMPAT_H
