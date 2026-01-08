#import "AppDelegate.h"
#import <os/log.h>

@interface AppDelegate ()

@property (strong, nonatomic) os_log_t log;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.log = os_log_create("com.atproto.pds", "AppDelegate");
    os_log_info(self.log, "ATProto PDS starting up...");
    
    self.pdsController = [[PDSController alloc] init];
    NSError *error = nil;
    if (![self.pdsController startServerWithError:&error]) {
        os_log_error(self.log, "Failed to start server: %@", error);
    }
    
    [self setupStatusBar];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    os_log_info(self.log, "ATProto PDS shutting down...");
    [self.pdsController stopServer];
}

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

- (void)startServer:(id)sender {
    NSError *error = nil;
    if (![self.pdsController startServerWithError:&error]) {
        os_log_error(self.log, "Failed to start server: %@", error);
    }
}

- (void)stopServer:(id)sender {
    [self.pdsController stopServer];
}

@end