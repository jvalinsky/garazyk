#import "Core/PDSAccountEvents.h"

NSNotificationName const PDSAccountCreatedNotification =
    @"PDSAccountCreatedNotification";

NSNotificationName const PDSAccountActivatedNotification =
    @"PDSAccountActivatedNotification";

NSNotificationName const PDSAccountDeactivatedNotification =
    @"PDSAccountDeactivatedNotification";

NSString * const PDSAccountEventDidKey = @"did";
NSString * const PDSAccountEventHandleKey = @"handle";
NSString * const PDSAccountEventStatusKey = @"status";
