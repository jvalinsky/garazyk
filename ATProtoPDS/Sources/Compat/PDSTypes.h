#ifndef PDSTypes_h
#define PDSTypes_h

#if defined(__APPLE__)
#define PDS_GCD_OBJC_SUPPORT 1
#else
#define PDS_GCD_OBJC_SUPPORT 0
#endif

#if PDS_GCD_OBJC_SUPPORT
#define PDS_DISPATCH_QUEUE_STRONG strong
#else
#define PDS_DISPATCH_QUEUE_STRONG assign
#endif

#endif /* PDSTypes_h */
