// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "AppDelegate.h"
#import <os/log.h>
#import "Network/HttpServer.h"
#import "Database/PDSDatabase.h"
#import "Debug/GZLogger.h"

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 270) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    GZ_LOG_INFO_C(GZLogComponentCore, @"ATProto PDS starting up...");
#else
    GZ_LOG_INFO_C(GZLogComponentCore, @"ATProto PDS starting up...");
#endif
    
    self.pdsController = [[PDSController alloc] init];
    NSError *error = nil;
    if (![self.pdsController startServerWithError:&error]) {
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
        GZ_LOG_ERROR_C(GZLogComponentCore, @"Failed to start server: %@", error);
#else
        GZ_LOG_ERROR_C(GZLogComponentCore, @"Failed to start server: %@", error);
#endif
    }
    
#if TARGET_OS_OSX || defined(__APPLE__)
    [self setupStatusBar];
#endif
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    GZ_LOG_INFO_C(GZLogComponentCore, @"ATProto PDS shutting down...");
    [self.pdsController stopServer];
}

#if TARGET_OS_OSX || defined(__APPLE__)
- (void)setupStatusBar {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.title = @"PDS";
    self.statusItem.button.image = [NSImage imageNamed:NSImageNameNetwork];
    
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
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
        GZ_LOG_ERROR_C(GZLogComponentCore, @"Failed to start server: %@", error);
#else
        GZ_LOG_ERROR_C(GZLogComponentCore, @"Failed to start server: %@", error);
#endif
    }
}

- (void)stopServer:(id)sender {
    [self.pdsController stopServer];
}

@end