/*!
 @file AppDelegate.h

 @abstract Application delegate for macOS PDS application.

 @discussion Manages application lifecycle on macOS, including menu bar status
 item and PDS controller initialization. On Linux/GNUstep, provides minimal
 lifecycle management without UI components.

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>
#import "PDSController.h"

#if TARGET_OS_OSX || defined(__APPLE__)
#import <AppKit/AppKit.h>
#define PDS_NS_APPLICATION_DELEGATE <NSApplicationDelegate>
#else
#define PDS_NS_APPLICATION_DELEGATE
#endif

NS_ASSUME_NONNULL_BEGIN

/*!
 @class AppDelegate

 @abstract Manages PDS application lifecycle and UI on macOS.

 @discussion On macOS, provides NSApplicationDelegate implementation with
 menu bar status item. On Linux/GNUstep, provides basic initialization without
 AppKit dependencies.
 */
@interface AppDelegate : NSObject PDS_NS_APPLICATION_DELEGATE

/*! Main PDS controller managing server and services. */
@property (strong, nonatomic) PDSController *pdsController;

#if TARGET_OS_OSX || defined(__APPLE__)
/*! macOS menu bar status item for PDS controls. */
@property (strong, nonatomic, nullable) NSStatusItem *statusItem;
/*! Main application window. */
@property (strong, nonatomic, nullable) NSWindow *window;
#endif

@end

NS_ASSUME_NONNULL_END