/*
 * SessionState.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>

@implementation SessionState : CPObject
{
    CPString _currentDID @accessors(property=currentDID);
    CPString _currentHandle @accessors(property=currentHandle);
    BOOL _adminAuthenticated @accessors(property=adminAuthenticated);
}

- (id)init
{
    self = [super init];
    if (self)
    {
        _adminAuthenticated = NO;
    }
    return self;
}

@end
