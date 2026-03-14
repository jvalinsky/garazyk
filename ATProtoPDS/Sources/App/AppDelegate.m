#import "AppDelegate.h"
#import <os/log.h>
#import "Network/HttpServer.h"
#import "Database/PDSDatabase.h"
#import "Debug/PDSLogger.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 270) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
#endif
    PDS_LOG_INFO_C(PDSLogComponentCore, @"ATProto PDS starting up...");

    self.pdsController = [[PDSController alloc] init];
    NSError *error = nil;
    if (![self.pdsController startServerWithError:&error]) {
        PDS_LOG_ERROR_C(PDSLogComponentCore, @"Failed to start server: %@", error);
#if TARGET_OS_OSX || defined(__APPLE__)
        // Show a visible alert so the user knows the server did not start.
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText     = @"ATProto PDS Failed to Start";
        alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
        alert.alertStyle      = NSAlertStyleCritical;
        [alert runModal];
#endif
    }

#if TARGET_OS_OSX || defined(__APPLE__)
    [self setupStatusBar];
#endif
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    PDS_LOG_INFO_C(PDSLogComponentCore, @"ATProto PDS shutting down...");
    [self.pdsController stopServer];
}

#if TARGET_OS_OSX || defined(__APPLE__)
- (void)setupStatusBar {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.title = @"PDS";
    // NSImageNameNetwork is deprecated since macOS 12; use SF Symbols instead.
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"network"
                                             accessibilityDescription:@"PDS Server"];
    
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"Start Server" action:@selector(startServer:) keyEquivalent:@""];
    [menu addItemWithTitle:@"Stop Server" action:@selector(stopServer:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    
    self.statusItem.menu = menu;
}
#endif

- (void)startServer:(id)sender {
    NSError *error = nil;
    if (![self.pdsController startServerWithError:&error]) {
        PDS_LOG_ERROR_C(PDSLogComponentCore, @"Failed to start server: %@", error);
    }
}

- (void)stopServer:(id)sender {
    [self.pdsController stopServer];
}

@end