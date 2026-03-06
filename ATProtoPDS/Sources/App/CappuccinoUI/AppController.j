/*
 * AppController.j
 * CappuccinoUI
 *
 * Created by You on March 5, 2026.
 * Copyright 2026, Your Company All rights reserved.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "ExplorerController.j"
@import "AdminController.j"
@import "MSTController.j"
@import "OAuthDemoController.j"

@implementation AppController : CPObject
{
    CPWindow _window;
    SessionState _sessionState;
    UIAPIClient _apiClient;
    ExplorerController _explorerController;
    AdminController _adminController;
    MSTController _mstController;
    OAuthDemoController _oauthDemoController;
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    [self setUpControllers];
    [self setUpWindow];
}

- (void)setUpControllers
{
    _sessionState = [[SessionState alloc] init];
    _apiClient = [[UIAPIClient alloc] init];

    _explorerController = [[ExplorerController alloc] initWithSessionState:_sessionState
                                                                  apiClient:_apiClient];
    _adminController = [[AdminController alloc] initWithSessionState:_sessionState
                                                            apiClient:_apiClient];
    _mstController = [[MSTController alloc] initWithSessionState:_sessionState
                                                         apiClient:_apiClient];
    _oauthDemoController = [[OAuthDemoController alloc] initWithSessionState:_sessionState
                                                                     apiClient:_apiClient];
}

- (void)setUpWindow
{
    _window = [[CPWindow alloc] initWithContentRect:CGRectMake(80.0, 80.0, 1120.0, 760.0)
                                           styleMask:CPTitledWindowMask | CPClosableWindowMask | CPResizableWindowMask];
    [_window setTitle:@"September UI (Objective-J)"];

    var tabView = [[CPTabView alloc] initWithFrame:[[_window contentView] bounds]];
    [tabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    [self addTabToView:tabView label:@"Explorer" contentView:[_explorerController rootView]];
    [self addTabToView:tabView label:@"Admin" contentView:[_adminController rootView]];
    [self addTabToView:tabView label:@"MST" contentView:[_mstController rootView]];
    [self addTabToView:tabView label:@"OAuth Demo" contentView:[_oauthDemoController rootView]];

    [[_window contentView] addSubview:tabView];
    [_window orderFront:self];
}

- (void)addTabToView:(CPTabView)tabView label:(CPString)label contentView:(CPView)contentView
{
    var item = [[CPTabViewItem alloc] initWithIdentifier:label];
    [item setLabel:label];
    [item setView:contentView];
    [tabView addTabViewItem:item];
}

@end
