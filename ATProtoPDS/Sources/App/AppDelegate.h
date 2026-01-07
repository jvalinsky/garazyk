#import <Cocoa/Cocoa.h>
#import "PDSController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (strong, nonatomic) PDSController *pdsController;
@property (strong, nonatomic) NSStatusItem *statusItem;

@end