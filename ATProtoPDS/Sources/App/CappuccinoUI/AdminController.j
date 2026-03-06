/*
 * AdminController.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation AdminController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 20.0, 900.0, 28.0)];
    [title setStringValue:@"Admin (Objective-J scaffold)"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    var subtitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 56.0, 980.0, 22.0)];
    [subtitle setStringValue:@"Planned sources: /api/v2/ui/admin/*"];
    [subtitle setEditable:NO];
    [subtitle setBezeled:NO];
    [subtitle setDrawsBackground:NO];

    [_rootView addSubview:title];
    [_rootView addSubview:subtitle];

    return _rootView;
}

@end
