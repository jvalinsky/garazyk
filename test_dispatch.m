#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

int main() {
    @autoreleasepool {
        dispatch_queue_t queue = dispatch_queue_create("com.test", NULL);
        dispatch_sync(queue, ^{
            NSLog(@"In Queue!");
        });
        NSLog(@"Dispatch works!");
    }
    return 0;
}
