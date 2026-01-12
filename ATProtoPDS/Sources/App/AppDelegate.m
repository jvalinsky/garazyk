#import "AppDelegate.h"
#import <os/log.h>

@interface AppDelegate ()

#if defined(__APPLE__)
@property (strong, nonatomic) os_log_t log;
#else
@property (assign, nonatomic) os_log_t log;
#endif

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
    self.log = os_log_create("com.atproto.pds", "AppDelegate");
    os_log_info(self.log, "ATProto PDS starting up...");
#else
    NSLog(@"ATProto PDS starting up...");
#endif
    
    self.pdsController = [[PDSController alloc] init];
    NSError *error = nil;
    if (![self.pdsController startServerWithError:&error]) {
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
        os_log_error(self.log, "Failed to start server: %@", error);
#else
        NSLog(@"Failed to start server: %@", error);
#endif
    }
    
#if TARGET_OS_OSX || defined(__APPLE__)
    [self setupStatusBar];
#endif
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
#if !defined(GNUSTEP) && (TARGET_OS_OSX || defined(__APPLE__))
    os_log_info(self.log, "ATProto PDS shutting down...");
#else
    NSLog(@"ATProto PDS shutting down...");
#endif
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
        os_log_error(self.log, "Failed to start server: %@", error);
#else
        NSLog(@"Failed to start server: %@", error);
#endif
    }
}

- (void)stopServer:(id)sender {
    [self.pdsController stopServer];
}

@end