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

    // Active shell profile and service map
    CPString _serviceProfile;
    CPArray _activeServices;
    CPDictionary _endpointBases;

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
    CPSegmentedControl _serviceSegmentedControl;
}

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    [self bootstrapServiceProfileAndLaunch];
}

- (void)bootstrapServiceProfileAndLaunch
{
    var appSelf = self,
        didLaunch = NO,
        profileOverride = [self profileOverrideFromQuery];

    var launchWithPayload = function(payload)
    {
        if (didLaunch)
            return;

        didLaunch = YES;
        [appSelf applyServiceProfilePayload:payload overrideProfile:profileOverride];
        [appSelf setUpControllers];
        [appSelf setUpWindow];
        [appSelf setUpMainMenu];
    };

    var xhr = new XMLHttpRequest();
    xhr.open("GET", "/ui/profile", YES);
    xhr.setRequestHeader("Accept", "application/json");

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var payload = nil,
            statusCode = xhr.status || 0;

        if (statusCode >= 200 && statusCode < 300)
        {
            try
            {
                payload = xhr.responseText ? JSON.parse(xhr.responseText) : nil;
            }
            catch (e)
            {
                payload = nil;
            }
        }

        launchWithPayload(payload);
    };

    xhr.onerror = function()
    {
        launchWithPayload(nil);
    };

    xhr.send();
}

- (CPString)queryValueForKey:(CPString)key
{
    if (!(window && window.location && window.location.search))
        return nil;

    var search = window.location.search;
    if (!search || search.length <= 1)
        return nil;

    var parts = search.substring(1).split("&"),
        i = 0;

    for (i = 0; i < parts.length; i++)
    {
        var entry = parts[i];
        if (!entry || entry.length === 0)
            continue;

        var eqIndex = entry.indexOf("="),
            rawKey = (eqIndex >= 0) ? entry.substring(0, eqIndex) : entry,
            rawValue = (eqIndex >= 0) ? entry.substring(eqIndex + 1) : "",
            decodedKey = nil,
            decodedValue = nil;

        try
        {
            decodedKey = decodeURIComponent(rawKey.replace(/\+/g, " "));
            decodedValue = decodeURIComponent(rawValue.replace(/\+/g, " "));
        }
        catch (e)
        {
            continue;
        }

        if (decodedKey === String(key))
            return decodedValue;
    }

    return nil;
}

- (CPString)normalizedProfile:(CPString)profile
{
    var normalized = String(profile || "full").toLowerCase();
    if (normalized === "pds" || normalized === "relay" || normalized === "plc" ||
        normalized === "appview" || normalized === "full")
        return normalized;
    return @"full";
}

- (CPString)profileOverrideFromQuery
{
    var override = [self queryValueForKey:@"ui_profile"];
    if (!override)
        override = [self queryValueForKey:@"profile"];

    if (!override)
    {
        var fullFlag = [self queryValueForKey:@"full"];
        if (fullFlag && (String(fullFlag).toLowerCase() === "true" || fullFlag === "1"))
            override = @"full";
    }

    if (!override)
        return nil;

    return [self normalizedProfile:override];
}

- (CPArray)servicesForProfile:(CPString)profile
{
    if ([profile isEqualToString:@"full"])
        return [@"pds,relay,plc,appview" componentsSeparatedByString:@","];

    return [profile ? profile : @"full"];
}

- (CPDictionary)defaultEndpointBasesForProfile:(CPString)profile
{
    var bases = [CPMutableDictionary dictionary];

    if ([profile isEqualToString:@"pds"] || [profile isEqualToString:@"full"])
    {
        [bases setObject:@"/api/pds" forKey:@"explore"];
        [bases setObject:@"/admin" forKey:@"admin"];
        [bases setObject:@"/api/mst" forKey:@"mst"];
        [bases setObject:@"/xrpc" forKey:@"xrpc"];
        [bases setObject:@"/oauth" forKey:@"oauth"];
        [bases setObject:@"/oauth-demo" forKey:@"oauthDemo"];
    }

    if ([profile isEqualToString:@"relay"] || [profile isEqualToString:@"full"])
        [bases setObject:@"/api/relay" forKey:@"relay"];

    if ([profile isEqualToString:@"plc"] || [profile isEqualToString:@"full"])
        [bases setObject:@"" forKey:@"plc"];

    if ([profile isEqualToString:@"appview"] || [profile isEqualToString:@"full"])
        [bases setObject:@"" forKey:@"appview"];

    return bases;
}

- (CPDictionary)endpointBasesFromPayload:(id)payload profile:(CPString)profile
{
    var merged = [CPMutableDictionary dictionaryWithDictionary:[self defaultEndpointBasesForProfile:profile]];

    if (payload && payload.endpointBases)
    {
        for (var key in payload.endpointBases)
        {
            if (!payload.endpointBases.hasOwnProperty(key))
                continue;

            var value = payload.endpointBases[key];
            if (value === nil || value === undefined)
                continue;

            [merged setObject:String(value) forKey:String(key)];
        }
    }

    return merged;
}

- (void)applyServiceProfilePayload:(id)payload overrideProfile:(CPString)overrideProfile
{
    var payloadProfile = nil;

    if (payload && payload.serviceProfile)
        payloadProfile = String(payload.serviceProfile);

    _serviceProfile = [self normalizedProfile:(overrideProfile || payloadProfile || @"full")];
    _activeServices = [self servicesForProfile:_serviceProfile];
    _endpointBases = [self endpointBasesFromPayload:payload profile:_serviceProfile];
}

- (BOOL)isServiceEnabled:(CPString)serviceKey
{
    if (!_activeServices)
        return NO;

    return _activeServices.indexOf(String(serviceKey)) >= 0;
}

- (CPString)displayNameForService:(CPString)serviceKey
{
    if ([serviceKey isEqualToString:@"pds"]) return @"PDS";
    if ([serviceKey isEqualToString:@"relay"]) return @"Relay";
    if ([serviceKey isEqualToString:@"plc"]) return @"PLC";
    if ([serviceKey isEqualToString:@"appview"]) return @"AppView";
    return @"Service";
}

- (CPString)selectedServiceKey
{
    if (!_serviceTabView || !_activeServices)
        return nil;

    var tabIndex = [_serviceTabView indexOfTabViewItem:[_serviceTabView selectedTabViewItem]];
    if (tabIndex < 0 || tabIndex >= _activeServices.length)
        return nil;

    return _activeServices[tabIndex];
}

- (void)selectServiceByKey:(CPString)serviceKey
{
    if (!_serviceTabView || !_activeServices)
        return;

    var idx = _activeServices.indexOf(String(serviceKey));
    if (idx < 0)
        return;

    [_serviceTabView selectTabViewItemAtIndex:idx];
    if (_serviceSegmentedControl)
        [_serviceSegmentedControl setSelectedSegment:idx];
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

    if ([self isServiceEnabled:@"pds"])
    {
        var pdsItem = [[CPMenuItem alloc] initWithTitle:@"PDS" action:@selector(handleViewPDS:) keyEquivalent:@"1"];
        [pdsItem setKeyEquivalentModifierMask:CPCommandKeyMask];
        [pdsItem setTarget:self];
        [viewMenu addItem:pdsItem];
    }

    if ([self isServiceEnabled:@"relay"])
    {
        var relayItem = [[CPMenuItem alloc] initWithTitle:@"Relay" action:@selector(handleViewRelay:) keyEquivalent:@"2"];
        [relayItem setKeyEquivalentModifierMask:CPCommandKeyMask];
        [relayItem setTarget:self];
        [viewMenu addItem:relayItem];
    }

    if ([self isServiceEnabled:@"plc"])
    {
        var plcItem = [[CPMenuItem alloc] initWithTitle:@"PLC" action:@selector(handleViewPLC:) keyEquivalent:@"3"];
        [plcItem setKeyEquivalentModifierMask:CPCommandKeyMask];
        [plcItem setTarget:self];
        [viewMenu addItem:plcItem];
    }

    if ([self isServiceEnabled:@"appview"])
    {
        var appViewItem = [[CPMenuItem alloc] initWithTitle:@"AppView" action:@selector(handleViewAppView:) keyEquivalent:@"4"];
        [appViewItem setKeyEquivalentModifierMask:CPCommandKeyMask];
        [appViewItem setTarget:self];
        [viewMenu addItem:appViewItem];
    }

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

    [CPApp setMainMenu:mainMenu];
}

#pragma mark - Keyboard Shortcut Handlers

- (void)handleViewPDS:(id)sender
{
    [self selectServiceByKey:@"pds"];
}

- (void)handleViewRelay:(id)sender
{
    [self selectServiceByKey:@"relay"];
}

- (void)handleViewPLC:(id)sender
{
    [self selectServiceByKey:@"plc"];
}

- (void)handleViewAppView:(id)sender
{
    [self selectServiceByKey:@"appview"];
}

- (void)handleRefreshCurrent:(id)sender
{
    var serviceKey = [self selectedServiceKey];

    if ([serviceKey isEqualToString:@"pds"])
    {
        var subTabIndex = _pdsSubTabView ? [_pdsSubTabView indexOfTabViewItem:[_pdsSubTabView selectedTabViewItem]] : -1;
        if (subTabIndex === 0 && _explorerController)
            [_explorerController handleRefreshAccounts:sender];
        else if (subTabIndex === 1 && _adminController)
            [_adminController handleRefreshOverview:sender];
    }
    else if ([serviceKey isEqualToString:@"relay"] && _relayDashboardController)
    {
        [_relayDashboardController handleRefresh:sender];
    }
    else if ([serviceKey isEqualToString:@"plc"] && _plcDirectoryController)
    {
        [_plcDirectoryController handleRefresh:sender];
    }
    else if ([serviceKey isEqualToString:@"appview"] && _appViewBackfillController)
    {
        [_appViewBackfillController handleRefresh:sender];
    }
}

- (void)handleFocusSearch:(id)sender
{
    var serviceKey = [self selectedServiceKey];

    if ([serviceKey isEqualToString:@"pds"] && _explorerController)
        [_explorerController handleFocusSearch:sender];
}

- (void)setUpControllers
{
    _sessionState = [[SessionState alloc] init];
    _apiClient = [[UIAPIClient alloc] initWithEndpointBases:_endpointBases];

    if ([self isServiceEnabled:@"pds"])
    {
        _explorerController = [[ExplorerController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _adminController = [[AdminController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _mstController = [[MSTController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _oauthDemoController = [[OAuthDemoController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
    }

    if ([self isServiceEnabled:@"relay"])
    {
        _relayDashboardController = [[RelayDashboardController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _relayUpstreamsController = [[RelayUpstreamsController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _relayEventsController = [[RelayEventsController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
    }

    if ([self isServiceEnabled:@"plc"])
    {
        _plcDirectoryController = [[PLCDirectoryController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _plcDetailController = [[PLCDetailController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _plcTimelineController = [[PLCTimelineController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        _plcMetricsController = [[PLCMetricsController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
        [_plcDirectoryController setDelegate:self];
    }

    if ([self isServiceEnabled:@"appview"])
    {
        _appViewBackfillController = [[AppViewBackfillController alloc] initWithSessionState:_sessionState apiClient:_apiClient];
    }
}

- (void)setUpWindow
{
    _window = [[CPWindow alloc] initWithContentRect:CGRectMake(80.0, 80.0, 1200.0, 800.0)
                                           styleMask:CPTitledWindowMask | CPClosableWindowMask | CPResizableWindowMask];

    var profileDisplayName = [_serviceProfile isEqualToString:@"full"] ? @"All Services" : [self displayNameForService:_serviceProfile];
    [_window setTitle:[@"Kaszlak UI (Cappuccino) - " stringByAppendingString:profileDisplayName]];

    var contentBounds = [[_window contentView] bounds],
        statusBarHeight = 26.0,
        serviceTabHeight = 32.0;

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

    if ([self isServiceEnabled:@"pds"])
    {
        _pdsSubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_pdsSubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_pdsSubTabView setTabViewType:CPTopTabsBezelBorder];

        [self addTabToView:_pdsSubTabView label:@"Explorer" contentView:[_explorerController rootView]];
        [self addTabToView:_pdsSubTabView label:@"Admin" contentView:[_adminController rootView]];
        [self addTabToView:_pdsSubTabView label:@"MST" contentView:[_mstController rootView]];
        [self addTabToView:_pdsSubTabView label:@"OAuth Demo" contentView:[_oauthDemoController rootView]];

        _pdsTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_pdsTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_pdsTabContentView addSubview:_pdsSubTabView];
    }

    if ([self isServiceEnabled:@"relay"])
    {
        _relaySubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_relaySubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_relaySubTabView setTabViewType:CPTopTabsBezelBorder];

        [self addTabToView:_relaySubTabView label:@"Dashboard" contentView:[_relayDashboardController rootView]];
        [self addTabToView:_relaySubTabView label:@"Upstreams" contentView:[_relayUpstreamsController rootView]];
        [self addTabToView:_relaySubTabView label:@"Events" contentView:[_relayEventsController rootView]];

        _relayTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_relayTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_relayTabContentView addSubview:_relaySubTabView];
    }

    if ([self isServiceEnabled:@"plc"])
    {
        _plcSubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_plcSubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_plcSubTabView setTabViewType:CPTopTabsBezelBorder];

        [self addTabToView:_plcSubTabView label:@"Directory" contentView:[_plcDirectoryController rootView]];
        [self addTabToView:_plcSubTabView label:@"Detail" contentView:[_plcDetailController rootView]];
        [self addTabToView:_plcSubTabView label:@"Timeline" contentView:[_plcTimelineController rootView]];
        [self addTabToView:_plcSubTabView label:@"Metrics" contentView:[_plcMetricsController rootView]];

        _plcTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_plcTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_plcTabContentView addSubview:_plcSubTabView];
    }

    if ([self isServiceEnabled:@"appview"])
    {
        _appViewSubTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_appViewSubTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_appViewSubTabView setTabViewType:CPTopTabsBezelBorder];

        [self addTabToView:_appViewSubTabView label:@"Backfill" contentView:[_appViewBackfillController rootView]];

        _appViewTabContentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
        [_appViewTabContentView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
        [_appViewTabContentView addSubview:_appViewSubTabView];
    }

    _serviceTabView = [[CPTabView alloc] initWithFrame:CGRectMake(0.0, serviceTabHeight, contentBounds.size.width, contentBounds.size.height - statusBarHeight - serviceTabHeight)];
    [_serviceTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_serviceTabView setTabViewType:CPTopTabsBezelBorder];

    for (var i = 0; i < _activeServices.length; i++)
    {
        var key = _activeServices[i];
        if (key === "pds" && _pdsTabContentView)
            [self addTabToView:_serviceTabView label:@"PDS" contentView:_pdsTabContentView];
        else if (key === "relay" && _relayTabContentView)
            [self addTabToView:_serviceTabView label:@"Relay" contentView:_relayTabContentView];
        else if (key === "plc" && _plcTabContentView)
            [self addTabToView:_serviceTabView label:@"PLC" contentView:_plcTabContentView];
        else if (key === "appview" && _appViewTabContentView)
            [self addTabToView:_serviceTabView label:@"AppView" contentView:_appViewTabContentView];
    }

    var segmentCount = _activeServices.length,
        segmentedWidth = segmentCount * 88.0;

    if (segmentedWidth < 180.0)
        segmentedWidth = 180.0;

    _serviceSegmentedControl = [[CPSegmentedControl alloc] initWithFrame:CGRectMake(20.0, 4.0, segmentedWidth, 24.0)];
    [_serviceSegmentedControl setSegmentCount:segmentCount];

    for (var segmentIndex = 0; segmentIndex < segmentCount; segmentIndex++)
    {
        var label = [self displayNameForService:_activeServices[segmentIndex]];
        [_serviceSegmentedControl setLabel:label forSegment:segmentIndex];
    }

    [_serviceSegmentedControl setSelectedSegment:0];
    [_serviceSegmentedControl setTarget:self];
    [_serviceSegmentedControl setAction:@selector(handleServiceSelected:)];
    [_serviceSegmentedControl setAutoresizingMask:CPViewMaxXMargin];

    var serviceBar = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, contentBounds.size.width, serviceTabHeight)];
    [serviceBar setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [serviceBar setBackgroundColor:[CPColor colorWithCalibratedWhite:0.96 alpha:1.0]];
    [serviceBar addSubview:_serviceSegmentedControl];

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
    if (!_plcDetailController || !_plcTimelineController || !_plcSubTabView)
        return;

    [_plcDetailController loadDID:did];
    [_plcTimelineController loadDID:did];

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
