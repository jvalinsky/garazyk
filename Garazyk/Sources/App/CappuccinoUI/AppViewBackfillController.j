/*
 * AppViewBackfillController.j
 * CappuccinoUI
 *
 * Backfill status dashboard with queue overview,
 * worker metrics, and admin controls for AppViewServer.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "EmptyStateView.j"
@import "ResponsiveMixin.j"

@implementation AppViewBackfillController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    EmptyStateView _emptyState;

    // Metric cards
    CPTextField _queueDepthLabel;
    CPTextField _activeWorkersLabel;
    CPTextField _syncedLabel;
    CPTextField _dirtyLabel;

    // Status section labels
    CPTextField _pendingCountLabel;
    CPTextField _processingCountLabel;
    CPTextField _syncedCountLabel;
    CPTextField _dirtyCountLabel;

    // Lag table
    CPTableView _lagTable;
    CPArray _lagData;

    // Admin controls
    CPTextField _didsField;
    CPSecureTextField _adminTokenField;
    CPTextView _resultTextView;

    // Queue operations
    CPTableView _queueTable;
    CPArray _queueData;
    CPTextField _selectedRepoLabel;

    CPDictionary _lastStatus;
    CPString _refreshTimer;
    BOOL _isRunning;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _lastStatus = nil;
        _lagData = [];
        _queueData = [];
        _isRunning = NO;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    // Note: Title removed - tab already shows "Backfill" in AppView sub-tabs
    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 1040.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Loading status..."];

    // Connection cards row
    [self buildMetricCardsInView:_rootView atY:48.0];

    // Repo status section
    [self buildRepoStatusInView:_rootView atY:168.0];

    // Ingest lag section
    [self buildLagSectionInView:_rootView atY:328.0];

    // Admin controls
    [self buildAdminControlsInView:_rootView atY:488.0];

    [_rootView addSubview:_statusLabel];

    // Start auto-refresh
    [self startAutoRefresh];

    // Set up resize observation for responsive layout
    [_rootView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [[CPNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleViewResize:)
                                                 name:CPViewFrameDidChangeNotification
                                               object:_rootView];

    return _rootView;
}

- (void)buildMetricCardsInView:(CPView)parent atY:(float)startY
{
    var cardWidth = 240.0,
        cardHeight = 90.0,
        gap = 20.0,
        startX = 20.0;

    // Queue depth card
    var queueCard = [self buildMetricCardWithTitle:@"Queue Depth"
                                             value:@"0"
                                          frame:CGRectMake(startX, startY, cardWidth, cardHeight)
                                            color:[CPColor colorWithCalibratedRed:0.2 green:0.6 blue:1.0 alpha:1.0]];
    _queueDepthLabel = [queueCard viewWithTag:@"valueLabel"];

    // Active workers card
    var workersCard = [self buildMetricCardWithTitle:@"Active Workers"
                                              value:@"0"
                                           frame:CGRectMake(startX + cardWidth + gap, startY, cardWidth, cardHeight)
                                             color:[CPColor colorWithCalibratedRed:0.2 green:0.8 blue:0.4 alpha:1.0]];
    _activeWorkersLabel = [workersCard viewWithTag:@"valueLabel"];

    // Synced repos card
    var syncedCard = [self buildMetricCardWithTitle:@"Synced Repos"
                                             value:@"0"
                                          frame:CGRectMake(startX + 2 * (cardWidth + gap), startY, cardWidth, cardHeight)
                                            color:[CPColor colorWithCalibratedRed:0.4 green:0.7 blue:0.4 alpha:1.0]];
    _syncedLabel = [syncedCard viewWithTag:@"valueLabel"];

    // Dirty repos card
    var dirtyCard = [self buildMetricCardWithTitle:@"Dirty Repos"
                                            value:@"0"
                                         frame:CGRectMake(startX + 3 * (cardWidth + gap), startY, cardWidth, cardHeight)
                                           color:[CPColor colorWithCalibratedRed:0.9 green:0.5 blue:0.2 alpha:1.0]];
    _dirtyLabel = [dirtyCard viewWithTag:@"valueLabel"];
}

- (CPView)buildMetricCardWithTitle:(CPString)title value:(CPString)value frame:(CGRect)frame color:(CPColor)color
{
    var card = [[CPView alloc] initWithFrame:frame];
    [card setWantsLayer:YES];
    [card setBackgroundColor:[CPColor colorWithCalibratedWhite:0.95 alpha:1.0]];

    // Color bar on left
    var colorBar = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 4.0, frame.size.height)];
    [colorBar setBackgroundColor:color];
    [card addSubview:colorBar];

    // Title
    var titleLabel = [[CPTextField alloc] initWithFrame:CGRectMake(12.0, 12.0, frame.size.width - 24.0, 20.0)];
    [titleLabel setStringValue:title];
    [titleLabel setFont:[CPFont systemFontOfSize:12.0]];
    [titleLabel setTextColor:[CPColor colorWithCalibratedWhite:0.4 alpha:1.0]];
    [titleLabel setEditable:NO];
    [titleLabel setBezeled:NO];
    [titleLabel setDrawsBackground:NO];
    [card addSubview:titleLabel];

    // Value
    var valueLabel = [[CPTextField alloc] initWithFrame:CGRectMake(12.0, 38.0, frame.size.width - 24.0, 40.0)];
    [valueLabel setStringValue:value];
    [valueLabel setFont:[CPFont boldSystemFontOfSize:28.0]];
    [valueLabel setEditable:NO];
    [valueLabel setBezeled:NO];
    [valueLabel setDrawsBackground:NO];
    [valueLabel setTag:@"valueLabel"];
    [card addSubview:valueLabel];

    return card;
}

- (void)buildRepoStatusInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 200.0, 24.0)];
    [sectionTitle setStringValue:@"Repo Status Breakdown"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    var statusItems = [
        {label: @"Pending:", tag: @"pendingCount"},
        {label: @"Processing:", tag: @"processingCount"},
        {label: @"Synced:", tag: @"syncedCount"},
        {label: @"Dirty:", tag: @"dirtyCount"}
    ];

    var y = startY + 30.0;
    for (var i = 0; i < statusItems.length; i++)
    {
        var item = statusItems[i];
        var labelField = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, y, 120.0, 22.0)];
        [labelField setStringValue:item.label];
        [labelField setFont:[CPFont systemFontOfSize:12.0]];
        [labelField setEditable:NO];
        [labelField setBezeled:NO];
        [labelField setDrawsBackground:NO];
        [labelField setAlignment:CPRightTextAlignment];
        [parent addSubview:labelField];

        var valueField = [[CPTextField alloc] initWithFrame:CGRectMake(150.0, y, 200.0, 22.0)];
        [valueField setStringValue:@"0"];
        [valueField setFont:[CPFont boldSystemFontOfSize:12.0]];
        [valueField setEditable:NO];
        [valueField setBezeled:NO];
        [valueField setDrawsBackground:NO];
        [valueField setTag:item.tag];
        [parent addSubview:valueField];

        y += 26.0;
    }

    _pendingCountLabel = [parent viewWithTag:@"pendingCount"];
    _processingCountLabel = [parent viewWithTag:@"processingCount"];
    _syncedCountLabel = [parent viewWithTag:@"syncedCount"];
    _dirtyCountLabel = [parent viewWithTag:@"dirtyCount"];
}

- (void)buildLagSectionInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 300.0, 24.0)];
    [sectionTitle setStringValue:@"Ingest Lag by Relay"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    _lagTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 600.0, 120.0)];
    [_lagTable setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_lagTable setDelegate:self];
    [_lagTable setDataSource:self];
    [_lagTable setAllowsEmptySelection:YES];
    [_lagTable setAllowsMultipleSelection:NO];

    var relayColumn = [[CPTableColumn alloc] initWithIdentifier:@"lag_relay"];
    [[relayColumn headerView] setStringValue:@"Relay Host"];
    [relayColumn setWidth:300.0];
    [_lagTable addTableColumn:relayColumn];

    var lagColumn = [[CPTableColumn alloc] initWithIdentifier:@"lag_value"];
    [[lagColumn headerView] setStringValue:@"Lag (events)"];
    [lagColumn setWidth:150.0];
    [_lagTable addTableColumn:lagColumn];

    var statusColumn = [[CPTableColumn alloc] initWithIdentifier:@"lag_status"];
    [[statusColumn headerView] setStringValue:@"Status"];
    [statusColumn setWidth:140.0];
    [_lagTable addTableColumn:statusColumn];
    [_lagTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var scroll = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, startY + 30.0, 620.0, 120.0)];
    [scroll setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setDocumentView:_lagTable];
    [parent addSubview:scroll];
}

- (void)buildAdminControlsInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 200.0, 24.0)];
    [sectionTitle setStringValue:@"Admin Controls"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    // Admin token field
    var tokenLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY + 32.0, 80.0, 18.0)];
    [tokenLabel setStringValue:@"Admin Token:"];
    [tokenLabel setEditable:NO];
    [tokenLabel setBezeled:NO];
    [tokenLabel setDrawsBackground:NO];
    [parent addSubview:tokenLabel];

    _adminTokenField = [[CPSecureTextField alloc] initWithFrame:CGRectMake(105.0, startY + 28.0, 300.0, 26.0)];
    [_adminTokenField setPlaceholderString:@"Enter admin secret"];
    [parent addSubview:_adminTokenField];

    // DIDs field
    var didsLabel = [[CPTextField alloc] initWithFrame:CGRectMake(420.0, startY + 32.0, 40.0, 18.0)];
    [didsLabel setStringValue:@"DIDs:"];
    [didsLabel setEditable:NO];
    [didsLabel setBezeled:NO];
    [didsLabel setDrawsBackground:NO];
    [parent addSubview:didsLabel];

    _didsField = [[CPTextField alloc] initWithFrame:CGRectMake(465.0, startY + 28.0, 350.0, 26.0)];
    [_didsField setPlaceholderString:@"did:plc:xxx, did:plc:yyy (comma-separated)"];
    [parent addSubview:_didsField];

    // Action buttons
    var enqueueButton = [[CPButton alloc] initWithFrame:CGRectMake(20.0, startY + 64.0, 120.0, 28.0)];
    [enqueueButton setTitle:@"Enqueue DIDs"];
    [enqueueButton setTarget:self];
    [enqueueButton setAction:@selector(handleEnqueueDIDs:)];
    [parent addSubview:enqueueButton];

    var rebuildButton = [[CPButton alloc] initWithFrame:CGRectMake(150.0, startY + 64.0, 160.0, 28.0)];
    [rebuildButton setTitle:@"Rebuild Relevance Set"];
    [rebuildButton setTarget:self];
    [rebuildButton setAction:@selector(handleRebuildScope:)];
    [parent addSubview:rebuildButton];

    var refreshButton = [[CPButton alloc] initWithFrame:CGRectMake(320.0, startY + 64.0, 100.0, 28.0)];
    [refreshButton setTitle:@"Refresh Now"];
    [refreshButton setTarget:self];
    [refreshButton setAction:@selector(handleRefresh:)];
    [parent addSubview:refreshButton];

    var autoRefreshBtn = [[CPButton alloc] initWithFrame:CGRectMake(430.0, startY + 64.0, 140.0, 28.0)];
    [autoRefreshBtn setTitle:@"Auto Refresh: ON"];
    [autoRefreshBtn setTag:@"autoRefreshBtn"];
    [autoRefreshBtn setTarget:self];
    [autoRefreshBtn setAction:@selector(handleToggleAutoRefresh:)];
    [parent addSubview:autoRefreshBtn];

    // Result text view
    var resultScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, startY + 100.0, 1040.0, 60.0)];
    [resultScroll setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    var resultText = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1040.0, 60.0)];
    [resultText setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [resultText setEditable:NO];
    [resultText setSelectable:YES];
    [resultText setString:@""];
    [resultText setFont:[CPFont systemFontOfSize:11.0]];
    [resultScroll setHasVerticalScroller:YES];
    [resultScroll setAutohidesScrollers:YES];
    [resultScroll setDocumentView:resultText];
    [parent addSubview:resultScroll];
    _resultTextView = resultText;

    [self buildQueueOperationsInView:parent atY:startY + 170.0];
}

- (void)buildQueueOperationsInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 300.0, 24.0)];
    [sectionTitle setStringValue:@"Queue Operations"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    _queueTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 600.0, 100.0)];
    [_queueTable setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_queueTable setDelegate:self];
    [_queueTable setDataSource:self];
    [_queueTable setAllowsEmptySelection:YES];
    [_queueTable setAllowsMultipleSelection:NO];

    var didColumn = [[CPTableColumn alloc] initWithIdentifier:@"queue_did"];
    [[didColumn headerView] setStringValue:@"Repo DID"];
    [didColumn setWidth:280.0];
    [_queueTable addTableColumn:didColumn];

    var statusColumn = [[CPTableColumn alloc] initWithIdentifier:@"queue_status"];
    [[statusColumn headerView] setStringValue:@"Status"];
    [statusColumn setWidth:100.0];
    [_queueTable addTableColumn:statusColumn];

    var errorColumn = [[CPTableColumn alloc] initWithIdentifier:@"queue_error"];
    [[errorColumn headerView] setStringValue:@"Error"];
    [errorColumn setWidth:200.0];
    [_queueTable addTableColumn:errorColumn];
    [_queueTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var scrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, startY + 30.0, 800.0, 120.0)];
    [scrollView setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setDocumentView:_queueTable];
    [scrollView setBorderType:CPBezelBorder];
    [parent addSubview:scrollView];

    var retryBtn = [[CPButton alloc] initWithFrame:CGRectMake(20.0, startY + 160.0, 80.0, 28.0)];
    [retryBtn setTitle:@"Retry"];
    [retryBtn setTarget:self];
    [retryBtn setAction:@selector(handleRetryRepo:)];
    [parent addSubview:retryBtn];

    var cancelBtn = [[CPButton alloc] initWithFrame:CGRectMake(110.0, startY + 160.0, 80.0, 28.0)];
    [cancelBtn setTitle:@"Cancel"];
    [cancelBtn setTarget:self];
    [cancelBtn setAction:@selector(handleCancelRepo:)];
    [parent addSubview:cancelBtn];

    _selectedRepoLabel = [[CPTextField alloc] initWithFrame:CGRectMake(200.0, startY + 165.0, 400.0, 18.0)];
    [_selectedRepoLabel setStringValue:@""];
    [_selectedRepoLabel setFont:[CPFont systemFontOfSize:11.0]];
    [_selectedRepoLabel setEditable:NO];
    [_selectedRepoLabel setBezeled:NO];
    [_selectedRepoLabel setDrawsBackground:NO];
    [parent addSubview:_selectedRepoLabel];

    _queueData = [];
}

#pragma mark - Data Loading

- (void)loadStatus
{
    [self hideEmptyState];
    var token = _adminTokenField ? [_adminTokenField stringValue] : @"";

    if (!token || token.length === 0)
    {
        [_statusLabel setTextColor:[CPColor colorWithCalibratedWhite:0.3 alpha:1.0]];
        [_statusLabel setStringValue:@"Enter admin token to load backfill status."];
        [self showEmptyStateWithIcon:EmptyStateIconReport
                              message:@"Admin token required. Please enter the master secret to view AppView backfill status."];
        return;
    }
    
    var urlString = [_apiClient URLStringForPath:@"/admin/backfill/status"
                                    endpointGroup:@"appview"
                                     queryParams:nil],
        xhr = new XMLHttpRequest();

    xhr.open("GET", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + String(token));

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0,
            responseText = xhr.responseText || "",
            payload = nil;

        try { payload = responseText.length > 0 ? JSON.parse(responseText) : {}; } catch (e) { CPLog.warn("AppViewBackfillController: JSON parse error: " + e); }

        if (statusCode < 200 || statusCode >= 300)
        {
            var errMsg = (payload && payload.error) ? payload.error : ("HTTP " + statusCode);
            if (statusCode === 401) {
                errMsg = "Unauthorized - check admin token";
                [self showEmptyStateWithIcon:EmptyStateIconReport
                                      message:@"Invalid admin token. Access to AppView admin routes is restricted."];
            } else {
                [self showEmptyStateWithIcon:EmptyStateIconCloudOff
                                      message:@"Could not reach AppView admin API. " + errMsg];
            }
            [_statusLabel setStringValue:@"Error: " + errMsg];
            [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:0.8 green:0.2 blue:0.2 alpha:1.0]];
            return;
        }

        [_statusLabel setTextColor:[CPColor colorWithCalibratedWhite:0.3 alpha:1.0]];

        if (payload)
        {
            [self updateStatusDisplay:payload];
            [_statusLabel setStringValue:@"Updated " + new Date().toLocaleTimeString()];
            [self loadQueueData];
            
            if ((payload.queue_depth || 0) === 0 && (payload.repos_synced || 0) === 0) {
                 [self showEmptyStateWithIcon:EmptyStateIconInbox
                                       message:@"AppView backfill is idle. No repos are currently queued or synced."];
            }
        }
    };

    xhr.onerror = function()
    {
        [_statusLabel setStringValue:@"Error: Network error"];
        [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:0.8 green:0.2 blue:0.2 alpha:1.0]];
        [self showEmptyStateWithIcon:EmptyStateIconCloudOff
                              message:@"Could not reach AppView server. Network connection failed."];
    };

    xhr.send();
}

#pragma mark - Empty State Helpers

- (void)showEmptyStateWithIcon:(CPString)icon message:(CPString)message
{
    if (!_rootView)
        return;

    if (!_emptyState)
        _emptyState = [[EmptyStateView alloc] initWithFrame:[_rootView bounds]
                                                        icon:icon
                                                     message:message
                                                  actionTitle:@"Refresh"
                                                actionHandler:function() { [self loadStatus]; }];

    [_emptyState setIcon:icon];
    [_emptyState setMessage:message];
    
    // Cover the main content area (below status label)
    var frame = [_rootView bounds];
    frame.origin.y = 48.0;
    frame.size.height -= 48.0;
    [_emptyState setFrame:frame];
    
    [_emptyState showInView:_rootView];
}

- (void)hideEmptyState
{
    if (_emptyState)
        [_emptyState hide];
}

- (void)updateStatusDisplay:(id)status
{
    if (!status)
        return;

    _lastStatus = status;

    // Update metric cards (with nil guards)
    if (_queueDepthLabel)
        [_queueDepthLabel setStringValue:[self formatNumber:status.queue_depth]];
    if (_activeWorkersLabel)
        [_activeWorkersLabel setStringValue:String(status.active_workers || 0)];
    if (_syncedLabel)
        [_syncedLabel setStringValue:[self formatNumber:status.repos_synced]];
    if (_dirtyLabel)
        [_dirtyLabel setStringValue:[self formatNumber:status.repos_dirty]];

    // Update status breakdown (with nil guards)
    if (_pendingCountLabel)
        [_pendingCountLabel setStringValue:[self formatNumber:status.repos_pending]];
    if (_processingCountLabel)
        [_processingCountLabel setStringValue:[self formatNumber:status.repos_processing]];
    if (_syncedCountLabel)
        [_syncedCountLabel setStringValue:[self formatNumber:status.repos_synced]];
    if (_dirtyCountLabel)
        [_dirtyCountLabel setStringValue:[self formatNumber:status.repos_dirty]];

    // Update lag table
    var lagByRelay = status.ingest_lag_by_relay || {};
    _lagData = [];
    var relayHosts = Object.keys(lagByRelay);
    for (var i = 0; i < relayHosts.length; i++)
    {
        var host = relayHosts[i];
        var lag = lagByRelay[host];
        _lagData.push({
            relay: host,
            lag: lag,
            status: lag > 1000 ? "Behind" : (lag > 100 ? "Catching up" : "Synced")
        });
    }
    [_lagTable reloadData];
}

- (CPString)formatNumber:(id)numValue
{
    var num = parseInt(numValue) || 0;
    if (num >= 1000000000)
        return (num / 1000000000).toFixed(1) + "B";
    if (num >= 1000000)
        return (num / 1000000).toFixed(1) + "M";
    if (num >= 1000)
        return (num / 1000).toFixed(1) + "K";
    return String(num);
}

#pragma mark - Auto Refresh

- (void)startAutoRefresh
{
    if (_isRunning)
        return;

    _isRunning = YES;
    [self loadStatus];

    if (!(window && window.setInterval))
        return;

    _refreshTimer = window.setInterval(function()
    {
        if (_isRunning)
            [self loadStatus];
    }, 3000);
}

- (void)stopAutoRefresh
{
    _isRunning = NO;
    if (_refreshTimer && window && window.clearInterval)
    {
        window.clearInterval(_refreshTimer);
        _refreshTimer = nil;
    }
}

#pragma mark - Actions

- (void)handleRefresh:(id)sender
{
    [self loadStatus];
}

- (void)handleToggleAutoRefresh:(id)sender
{
    if (_isRunning)
    {
        [self stopAutoRefresh];
        [sender setTitle:@"Auto Refresh: OFF"];
    }
    else
    {
        [self startAutoRefresh];
        [sender setTitle:@"Auto Refresh: ON"];
    }
}

- (void)handleEnqueueDIDs:(id)sender
{
    var didsText = [_didsField stringValue] || "";
    var token = [_adminTokenField stringValue] || "";

    if (didsText.length === 0)
    {
        [_resultTextView setString:@"Error: Enter at least one DID"];
        return;
    }

    if (token.length === 0)
    {
        [_resultTextView setString:@"Error: Admin token required"];
        return;
    }

    // Parse DIDs (comma-separated)
    var dids = didsText.split(",").map(function(d) { return d.trim(); }).filter(function(d) { return d.length > 0; });

    if (dids.length === 0)
    {
        [_resultTextView setString:@"Error: No valid DIDs found"];
        return;
    }

    [_resultTextView setString:@"Enqueuing " + dids.length + " DIDs..."];

    // Direct XHR with Authorization header
    var urlString = [_apiClient URLStringForPath:@"/admin/backfill/repos"
                                    endpointGroup:@"appview"
                                     queryParams:nil],
        xhr = new XMLHttpRequest();

    xhr.open("POST", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + String(token));

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0,
            responseText = xhr.responseText || "",
            payload = nil;

        try { payload = JSON.parse(responseText); } catch (e) { CPLog.warn("AppViewBackfillController: JSON parse error: " + e); }

        if (statusCode < 200 || statusCode >= 300)
        {
            var errMsg = (payload && payload.error) ? payload.error : ("HTTP " + statusCode);
            if (statusCode === 401)
                errMsg = "Unauthorized - check admin token";
            [_resultTextView setString:@"Error: " + errMsg];
            return;
        }

        var result = "Enqueued: " + (payload.enqueued || 0) + "\n";
        result += "Skipped: " + (payload.skipped || 0);
        [_resultTextView setString:result];
        [self loadStatus];
    };

    xhr.onerror = function()
    {
        [_resultTextView setString:@"Error: Network error"];
    };

    xhr.send(JSON.stringify({dids: dids}));
}

- (void)handleRebuildScope:(id)sender
{
    var token = [_adminTokenField stringValue] || "";

    if (token.length === 0)
    {
        [_resultTextView setString:@"Error: Admin token required"];
        return;
    }

    [_resultTextView setString:@"Rebuilding relevance scope..."];

    // Direct XHR with Authorization header
    var urlString = [_apiClient URLStringForPath:@"/admin/backfill/scope/rebuild"
                                    endpointGroup:@"appview"
                                     queryParams:nil],
        xhr = new XMLHttpRequest();

    xhr.open("POST", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + String(token));

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0,
            responseText = xhr.responseText || "",
            payload = nil;

        try { payload = JSON.parse(responseText); } catch (e) { CPLog.warn("AppViewBackfillController: JSON parse error: " + e); }

        if (statusCode < 200 || statusCode >= 300)
        {
            var errMsg = (payload && payload.error) ? payload.error : ("HTTP " + statusCode);
            if (statusCode === 401)
                errMsg = "Unauthorized - check admin token";
            [_resultTextView setString:@"Error: " + errMsg];
            return;
        }

        var result = "Relevance set rebuilt\n";
        result += "Scope size: " + (payload.relevance_set_size || 0) + " DIDs";
        [_resultTextView setString:result];
        [self loadStatus];
    };

    xhr.onerror = function()
    {
        [_resultTextView setString:@"Error: Network error"];
    };

    xhr.send("{}");
}

- (void)handleRetryRepo:(id)sender
{
    var token = [_adminTokenField stringValue] || "";
    if (token.length === 0)
    {
        [_resultTextView setString:@"Error: Admin token required"];
        return;
    }

    var selectedRow = [_queueTable selectedRow];
    if (selectedRow < 0 || selectedRow >= _queueData.length)
    {
        [_resultTextView setString:@"Select a repo from the queue to retry"];
        return;
    }

    var repo = _queueData[selectedRow];
    var did = repo.did;
    var encodedDID = encodeURIComponent(String(did));

    [_resultTextView setString:@"Retrying " + did + "..."];

    var urlString = [_apiClient URLStringForPath:@"/admin/backfill/repos/" + encodedDID + "/retry"
                                    endpointGroup:@"appview"
                                     queryParams:nil],
        xhr = new XMLHttpRequest();

    xhr.open("POST", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + String(token));

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0;
        if (statusCode >= 200 && statusCode < 300)
        {
            [_resultTextView setString:@"Retry initiated for " + did];
            [self loadStatus];
        }
        else
        {
            var payload = nil;
            try { payload = JSON.parse(xhr.responseText || "{}"); } catch (e) { CPLog.warn("AppViewBackfillController: JSON parse error: " + e); }
            var errorMessage = (payload && payload.error) ? payload.error : ("HTTP " + statusCode);
            [_resultTextView setString:@"Error: Failed to retry " + did + " (" + errorMessage + ")"];
        }
    };

    xhr.send();
}

- (void)handleCancelRepo:(id)sender
{
    var token = [_adminTokenField stringValue] || "";
    if (token.length === 0)
    {
        [_resultTextView setString:@"Error: Admin token required"];
        return;
    }

    var selectedRow = [_queueTable selectedRow];
    if (selectedRow < 0 || selectedRow >= _queueData.length)
    {
        [_resultTextView setString:@"Select a repo from the queue to cancel"];
        return;
    }

    var repo = _queueData[selectedRow];
    var did = repo.did;
    var encodedDID = encodeURIComponent(String(did));

    [_resultTextView setString:@"Cancelling " + did + "..."];

    var urlString = [_apiClient URLStringForPath:@"/admin/backfill/repos/" + encodedDID + "/cancel"
                                    endpointGroup:@"appview"
                                     queryParams:nil],
        xhr = new XMLHttpRequest();

    xhr.open("POST", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + String(token));

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0;
        if (statusCode >= 200 && statusCode < 300)
        {
            [_resultTextView setString:@"Cancelled " + did];
            [self loadStatus];
        }
        else
        {
            var payload = nil;
            try { payload = JSON.parse(xhr.responseText || "{}"); } catch (e) { CPLog.warn("AppViewBackfillController: JSON parse error: " + e); }
            var errorMessage = (payload && payload.error) ? payload.error : ("HTTP " + statusCode);
            [_resultTextView setString:@"Error: Failed to cancel " + did + " (" + errorMessage + ")"];
        }
    };

    xhr.send();
}

- (void)loadQueueData
{
    var token = [_adminTokenField stringValue] || "";
    if (!token || token.length === 0)
        return;

    var urlString = [_apiClient URLStringForPath:@"/admin/backfill/queue"
                                    endpointGroup:@"appview"
                                     queryParams:@{@"limit": @"50"}],
        xhr = new XMLHttpRequest();

    xhr.open("GET", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.setRequestHeader("Authorization", "Bearer " + String(token));

    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        var statusCode = xhr.status || 0;
        if (statusCode >= 200 && statusCode < 300)
        {
            try
            {
                var payload = JSON.parse(xhr.responseText);
                _queueData = payload.entries || payload.repos || [];
                [_queueTable reloadData];
            }
            catch (e)
            {
                _queueData = [];
                [_queueTable reloadData];
            }
        }
        else
        {
            _queueData = [];
            [_queueTable reloadData];
        }
    };

    xhr.send();
}

#pragma mark - CPTableView Data Source

- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    if (tableView === _lagTable)
        return _lagData ? _lagData.length : 0;
    if (tableView === _queueTable)
        return _queueData ? _queueData.length : 0;
    return 0;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (tableView === _lagTable && row < _lagData.length)
    {
        var item = _lagData[row];
        var identifier = [tableColumn identifier];

        if ([identifier isEqual:@"lag_relay"])
            return item.relay || "";
        if ([identifier isEqual:@"lag_value"])
            return String(item.lag || 0);
        if ([identifier isEqual:@"lag_status"])
            return item.status || "-";
    }
    if (tableView === _queueTable && row < _queueData.length)
    {
        var repo = _queueData[row];
        var identifier = [tableColumn identifier];

        if ([identifier isEqual:@"queue_did"])
            return repo.did || "";
        if ([identifier isEqual:@"queue_status"])
            return repo.status || "-";
        if ([identifier isEqual:@"queue_error"])
            return repo.last_error || repo.error || "-";
    }
    return @"";
}

- (void)tableViewSelectionDidChange:(CPNotification)notification
{
    if ([notification object] !== _queueTable)
        return;

    var selectedRow = [_queueTable selectedRow];
    if (selectedRow < 0 || selectedRow >= _queueData.length)
    {
        [_selectedRepoLabel setStringValue:@""];
        return;
    }

    var repo = _queueData[selectedRow] || {};
    var did = repo.did || @"";
    var status = repo.status || @"unknown";
    [_selectedRepoLabel setStringValue:@"Selected: " + did + " (" + status + ")"];
}

#pragma mark - Responsive Layout

- (void)handleViewResize:(CPNotification)notification
{
    var width = _rootView.bounds.size.width;
    var breakpoint = [ResponsiveMixin currentBreakpointForWidth:width];
    
    [self rebuildLayoutForBreakpoint:breakpoint width:width];
}

- (void)rebuildLayoutForBreakpoint:(CPString)breakpoint width:(float)width
{
    var startX = 20.0;
    var gap = 20.0;
    var cardWidth = 240.0;
    var cardHeight = 90.0;
    var startY = 80.0;
    
    var maxColumns = 4;
    
    var queueCard = _queueDepthLabel ? [_queueDepthLabel superview] : nil;
    var workersCard = _activeWorkersLabel ? [_activeWorkersLabel superview] : nil;
    var syncedCard = _syncedLabel ? [_syncedLabel superview] : nil;
    var dirtyCard = _dirtyLabel ? [_dirtyLabel superview] : nil;
    var cardViews = [queueCard, workersCard, syncedCard, dirtyCard];

    for (var i = 0; i < cardViews.length; i++)
    {
        var card = cardViews[i];
        if (!card)
            continue;
        var col = i % maxColumns;
        var row = parseInt(i / maxColumns);
        var newFrame = CGRectMake(startX + col * (cardWidth + gap), startY + row * (cardHeight + gap), cardWidth, cardHeight);
        [card setFrame:newFrame];
    }
}

@end
