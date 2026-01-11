#import <Foundation/Foundation.h>
#import "PDSController.h"

#if TARGET_OS_OSX || defined(__APPLE__)
#import <AppKit/AppKit.h>
#define PDS_NS_APPLICATION_DELEGATE <NSApplicationDelegate>
#else
#define PDS_NS_APPLICATION_DELEGATE
#endif

@interface AppDelegate : NSObject PDS_NS_APPLICATION_DELEGATE

@property (strong, nonatomic) PDSController *pdsController;

#if TARGET_OS_OSX || defined(__APPLE__)
@property (strong, nonatomic) NSStatusItem *statusItem;
#endif

@end