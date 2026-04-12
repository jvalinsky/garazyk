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
@import "RelayDashboardController.j"
@import "RelayUpstreamsController.j"
@import "RelayEventsController.j"
@import "PLCDirectoryController.j"
@import "PLCDetailController.j"
@import "PLCTimelineController.j"
@import "PLCMetricsController.j"
@import "AppViewBackfillController.j"

@implementation AppController : CPObject
{
    CPWindow _window;
    CPTextField _clockLabel;
    id _clockTimer;
    SessionState _sessionState;
    UIAPIClient _apiClient;

    // PDS Controllers
    ExplorerController _explorerController;
    AdminController _adminController;
    MSTController _mstController;
    OAuthDemoController _oauthDemoController;

    // Relay Controllers
    RelayDashboardController _relayDashboardController;
    RelayUpstreamsController _relayUpstreamsController;
    RelayEventsController _relayEventsController;

    // PLC Controllers
    PLCDirectoryController _plcDirectoryController;
    PLCDetailController _plcDetailController;
    PLCTimelineController _plcTimelineController;
    PLCMetricsController _plcMetricsController;

    // AppView Controllers
    AppViewBackfillController _appViewBackfillController;

    // Service tab views
    CPTabView _serviceTabView;
    CPView _pdsTabContentView;
    CPView _relayTabContentView;
    CPView _plcTabContentView;
    CPView _appViewTabContentView;
    CPTabView _pdsSubTabView;
    CPTabView _relaySubTabView;
    CPTabView _plcSubTabView;
    CPTabView _appViewSubTabView;
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    [self setUpControllers];
    [self setUpWindow];
    [self setUpMainMenu];
}

- (void)setUpMainMenu
{
    // Create main menu with keyboard shortcuts for WCAG accessibility
    var mainMenu = [[CPMenu alloc] init];

    // App menu (first item, special)
    var appMenuItem = [[CPMenuItem alloc] initWithTitle:@"Kaszlak UI" action:nil keyEquivalent:@""];
    var appMenu = [[CPMenu alloc] initWithTitle:@"Kaszlak UI"];
    [appMenuItem setSubmenu:appMenu];
    [mainMenu addItem:appMenuItem];

    // View menu with navigation shortcuts
    var viewMenuItem = [[CPMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    var viewMenu = [[CPMenu alloc] initWithTitle:@"View"];

    // Cmd+1 - PDS
    var pdsItem = [[CPMenuItem alloc] initWithTitle:@"PDS" action:@selector(handleViewPDS:) keyEquivalent:@"1"];
    [pdsItem setKeyEquivalentModifierMask:CPCommandKeyMask];
    [pdsItem setTarget:self];
    [viewMenu addItem:pdsItem];

    // Cmd+2 - Relay
    var relayItem = [[CPMenuItem alloc] initWithTitle:@"Relay" action:@selector(handleViewRelay:) keyEquivalent:@"2"];
    [relayItem setKeyEquivalentModifierMask:CPCommandKeyMask];
    [relayItem setTarget:self];
    [viewMenu addItem:relayItem];

    // Cmd+3 - PLC
    var plcItem = [[CPMenuItem alloc] initWithTitle:@"PLC" action:@selector(handleViewPLC:) keyEquivalent:@"3"];
    [plcItem setKeyEquivalentModifierMask:CPCommandKeyMask];
    [plcItem setTarget:self];
    [viewMenu addItem:plcItem];

    // Cmd+4 - AppView
    var appViewItem = [[CPMenuItem alloc] initWithTitle:@"AppView" action:@selector(handleViewAppView:) keyEquivalent:@"4"];
    [appViewItem setKeyEquivalentModifierMask:CPCommandKeyMask];
    [appViewItem setTarget:self];
    [viewMenu addItem:appViewItem];

    [viewMenu addItem:[CPMenuItem separatorItem]];

    // Cmd+R - Refresh current view
    var refreshItem = [[CPMenuItem alloc] initWithTitle:@"Refresh" action:@selector(handleRefreshCurrent:) keyEquivalent:@"r"];
    [refreshItem setKeyEquivalentModifierMask:CPCommandKeyMask];
    [refreshItem setTarget:self];
    [viewMenu addItem:refreshItem];

    // Cmd+F - Focus search
    var searchItem = [[CPMenuItem alloc] initWithTitle:@"Focus Search" action:@selector(handleFocusSearch:) keyEquivalent:@"f"];
    [searchItem setKeyEquivalentModifierMask:CPCommandKeyMask];
    [searchItem setTarget:self];
    [viewMenu addItem:searchItem];

    [viewMenuItem setSubmenu:viewMenu];
    [mainMenu addItem:viewMenuItem];

    // Set as main menu
    [CPApp setMainMenu:mainMenu];
}

#pragma mark - Keyboard Shortcut Handlers

- (void)handleViewPDS:(id)sender
{
    [_serviceTabView selectTabViewItemAtIndex:0];
}

- (void)handleViewRelay:(id)sender
{
    [_serviceTabView selectTabViewItemAtIndex:1];
}

- (void)handleViewPLC:(id)sender
{
    [_serviceTabView selectTabViewItemAtIndex:2];
}

- (void)handleViewAppView:(id)sender
{
    [_serviceTabView selectTabViewItemAtIndex:3];
}

- (void)handleRefreshCurrent:(id)sender
{
    // Refresh the current view based on which service/tab is selected
    var tabIndex = [_serviceTabView indexOfTabViewItem:[_serviceTabView selectedTabViewItem]];

    if (tabIndex === 0) // PDS
    {
        var subTabIndex = [_pdsSubTabView indexOfTabViewItem:[_pdsSubTabView selectedTabViewItem]];
        if (subTabIndex === 0 && _explorerController)
            [_explorerController handleRefreshAccounts:sender];
        else if (subTabIndex === 1 && _adminController)
            [_adminController handleRefreshOverview:sender];
    }
    else if (tabIndex === 1 && _relayDashboardController) // Relay
    {
        [_relayDashboardController handleRefresh:sender];
    }
    else if (tabIndex === 2 && _plcDirectoryController) // PLC
    {
        [_plcDirectoryController handleRefresh:sender];
    }
    else if (tabIndex === 3 && _appViewBackfillController) // AppView
    {
        [_appViewBackfillController handleRefresh:sender];
    }
}

- (void)handleFocusSearch:(id)sender
{
    // Focus search field in current view
    var tabIndex = [_serviceTabView indexOfTabViewItem:[_serviceTabView selectedTabViewItem]];

    if (tabIndex === 0) // PDS
    {
        [_explorerController handleFocusSearch:sender];
    }
    else if (tabIndex === 2) // PLC
    {
        // Focus search field in PLC directory
        // The directory controller has _searchField
        // Could add a handleFocusSearch method to PLCDirectoryController
    }
}

- (void)setUpControllers
{
    _sessionState = [[SessionState alloc] init];
    _apiClient = [[UIAPIClient alloc] init];

    // PDS controllers
    _explorerController = [[ExplorerController alloc] initWithSessionState:_sessionState
                                                                  apiClient:_apiClient];
    _adminController = [[AdminController alloc] initWithSessionState:_sessionState
                                                            apiClient:_apiClient];
    _mstController = [[MSTController alloc] initWithSessionState:_sessionState
                                                         apiClient:_apiClient];
    _oauthDemoController = [[OAuthDemoController alloc] initWithSessionState:_sessionState
                                                                     apiClient:_apiClient];

    // Relay controllers
    _relayDashboardController = [[RelayDashboardController alloc] initWithSessionState:_sessionState
                                                                              apiClient:_apiClient];
    _relayUpstreamsController = [[RelayUpstreamsController alloc] initWithSessionState:_sessionState
                                                                              apiClient:_apiClient];
    _relayEventsController = [[RelayEventsController alloc] initWithSessionState:_sessionState
                                                                          apiClient:_apiClient];

    // PLC controllers
    _plcDirectoryController = [[PLCDirectoryController alloc] initWithSessionState:_sessionState
                                                                           apiClient:_apiClient];
    _plcDetailController = [[PLCDetailController alloc] initWithSessionState:_sessionState
                                                                     apiClient:_apiClient];
    _plcTimelineController = [[PLCTimelineController alloc] initWithSessionState:_sessionState
                                                                       apiClient:_apiClient];
    _plcMetricsController = [[PLCMetricsController alloc] initWithSessionState:_sessionState
                                                                       apiClient:_apiClient];

    // AppView controllers
    _appViewBackfillController = [[AppViewBackfillController alloc] initWithSessionState:_sessionState
                                                                                apiClient:_apiClient];

    // Wire directory -> detail/timeline
    [_plcDirectoryController setDelegate:self];
}

- (void)setUpWindow
{
    _window = [[CPWindow alloc] initWithContentRect:CGRectMake(80.0, 80.0, 1200.0, 800.0)
                                           styleMask:CPTitledWindowMask | CPClosableWindowMask | CPResizableWindowMask];
    [_window setTitle:@"Kaszlak UI (Cappuccino)"];

    var contentBounds = [[_window contentView] bounds],
        statusBarHeight = 26.0,
        serviceTabHeight = 32.0;

    // Status bar at bottom
    var statusBar = [[CPView alloc] initWithFrame:CGRectMake(0.0, contentBounds.size.height - statusBarHeight, contentBounds.size.width, statusBarHeight)];
    [statusBar setAutoresizingMask:CPViewWidthSizable | CPViewMinYMargin];

    _clockLabel = [[CPTextField alloc] initWithFrame:CGRectMake(contentBounds.size.width - 260.0, 4.0, 248.0, 18.0)];
    [_clockLabel setAutoresizingMask:CPViewMinXMargin];
    [_clockLabel setEditable:NO];
    [_clockLabel setBezeled:NO];
    [_clockLabel setDrawsBackground:NO];
    [_clockLabel setAlignment: CPRightTextAlignment];
    [_clockLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_clockLabel setStringValue:@"Clock: --:--:--"];
    [statusBar addSubview:_clockLabel];

    // Build sub-tabs for each service
    _pdsSubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_pdsSubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_pdsSubTabView setTabViewType:CPTopTabsBezelBorder];

    [self addTabToView:_pdsSubTabView label:@"Explorer" contentView:[_explorerController rootView]];
    [self addTabToView:_pdsSubTabView label:@"Admin" contentView:[_adminController rootView]];
    [self addTabToView:_pdsSubTabView label:@"MST" contentView:[_mstController rootView]];
    [self addTabToView:_pdsSubTabView label:@"OAuth Demo" contentView:[_oauthDemoController rootView]];

    // PDS content view
    _pdsTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_pdsTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_pdsTabContentView addSubview:_pdsSubTabView];

    // Relay sub-tabs
    _relaySubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_relaySubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_relaySubTabView setTabViewType:CPTopTabsBezelBorder];

    [self addTabToView:_relaySubTabView label:@"Dashboard" contentView:[_relayDashboardController rootView]];
    [self addTabToView:_relaySubTabView label:@"Upstreams" contentView:[_relayUpstreamsController rootView]];
    [self addTabToView:_relaySubTabView label:@"Events" contentView:[_relayEventsController rootView]];

    // Relay content view
    _relayTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_relayTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_relayTabContentView addSubview:_relaySubTabView];

    // PLC sub-tabs
    _plcSubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_plcSubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_plcSubTabView setTabViewType:CPTopTabsBezelBorder];

    [self addTabToView:_plcSubTabView label:@"Directory" contentView:[_plcDirectoryController rootView]];
    [self addTabToView:_plcSubTabView label:@"Detail" contentView:[_plcDetailController rootView]];
    [self addTabToView:_plcSubTabView label:@"Timeline" contentView:[_plcTimelineController rootView]];
    [self addTabToView:_plcSubTabView label:@"Metrics" contentView:[_plcMetricsController rootView]];

    // PLC content view
    _plcTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_plcTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_plcTabContentView addSubview:_plcSubTabView];

    // AppView sub-tabs
    _appViewSubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_appViewSubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_appViewSubTabView setTabViewType:CPTopTabsBezelBorder];

    [self addTabToView:_appViewSubTabView label:@"Backfill" contentView:[_appViewBackfillController rootView]];

    // AppView content view
    _appViewTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_appViewTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_appViewTabContentView addSubview:_appViewSubTabView];

    // Service-level tab view (no tabs visible - uses segmented control instead)
    _serviceTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, serviceTabHeight, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_serviceTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_serviceTabView setTabViewType:CPTopTabsBezelBorder];

    [self addTabToView:_serviceTabView label:@"PDS" contentView:_pdsTabContentView];
    [self addTabToView:_serviceTabView label:@"Relay" contentView:_relayTabContentView];
    [self addTabToView:_serviceTabView label:@"PLC" contentView:_plcTabContentView];
    [self addTabToView:_serviceTabView label:@"AppView" contentView:_appViewTabContentView];

    // Service selector segmented control
    var segmentedControl = [[CPSegmentedControl alloc] initWithFrame:CGRectMake(20.0, 4.0, 340.0, 24.0)];
    [segmentedControl setSegmentCount:4];
    [segmentedControl setLabel:@"PDS" forSegment:0];
    [segmentedControl setLabel:@"Relay" forSegment:1];
    [segmentedControl setLabel:@"PLC" forSegment:2];
    [segmentedControl setLabel:@"AppView" forSegment:3];
    [segmentedControl setSelectedSegment:0];
    [segmentedControl setTarget:self];
    [segmentedControl setAction:@selector(handleServiceSelected:)];
    [segmentedControl setAutoresizingMask:CPViewMaxXMargin];

    var serviceBar = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, serviceTabHeight)];
    [serviceBar setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [serviceBar setBackgroundColor:[CPColor colorWithCalibratedWhite:0.96 alpha:1.0]];

    [serviceBar addSubview:segmentedControl];

    [[_window contentView] addSubview:serviceBar];
    [[_window contentView] addSubview:_serviceTabView];
    [[_window contentView] addSubview:statusBar];

    [self startStatusClock];
    [_window orderFront:self];
}

- (void)addTabToView:(CPTabView)tabView label:(CPString)label contentView:(CPView)contentView
{
    var item = [[CPTabViewItem alloc] initWithIdentifier:label];
    [item setLabel:label];
    [item setView:contentView];
    [tabView addTabViewItem:item];
}

- (void)handleServiceSelected:(id)sender
{
    var selected = [sender selectedSegment];
    [_serviceTabView selectTabViewItemAtIndex:selected];
}

// PLCDirectoryController delegate
- (void)plcDirectoryController:(PLCDirectoryController)controller didSelectDID:(CPString)did
{
    [_plcDetailController loadDID:did];
    [_plcTimelineController loadDID:did];

    // Switch to PLC detail view
    [_plcSubTabView selectTabViewItemAtIndex:1];
}

- (void)updateClockLabel
{
    if (!_clockLabel)
        return;

    var now = new Date();
    [_clockLabel setStringValue:(@"Clock: " + now.toLocaleTimeString())];
}

- (void)startStatusClock
{
    [self updateClockLabel];
    if (!(window && window.setInterval))
        return;

    if (_clockTimer)
        window.clearInterval(_clockTimer);

    var clockSelf = self;
    _clockTimer = window.setInterval(function()
    {
        [clockSelf updateClockLabel];
    }, 1000);
}

@end
