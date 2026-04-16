/*
 * RelayEventsController.j
 * CappuccinoUI
 *
 * Real-time event stream viewer using WebSocket.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation RelayEventsController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    CPTableView _eventsTable;
    CPTextView _eventDetailTextView;
    CPPopUpButton _filterTypePopup;
    CPTextField _repoFilterField;
    CPButton _pauseButton;
    CPButton _clearButton;
    CPButton _connectButton;

    CPArray _events;
    CPArray _filteredEvents;
    CPString _currentFilter;
    CPString _currentRepoFilter;
    BOOL _isPaused;
    BOOL _isConnected;
    BOOL _isPolling;
    id _webSocket;
    id _pollTimer;
    CPString _pollCursor;
    int _maxEvents;
    id _selectedEvent;
    BOOL _wsErrorLogged;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _events = [];
        _filteredEvents = [];
        _currentFilter = @"all";
        _currentRepoFilter = @"";
        _isPaused = NO;
        _isConnected = NO;
        _isPolling = NO;
        _webSocket = nil;
        _pollTimer = nil;
        _pollCursor = nil;
        _maxEvents = 500;
        _selectedEvent = nil;
        _wsErrorLogged = NO;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 400.0, 28.0)];
    [title setStringValue:@"Event Stream"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 600.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Disconnected"];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];

    [self buildControlsInView:_rootView];
    [self buildEventsTableInView:_rootView];
    [self buildEventDetailViewInView:_rootView];

    return _rootView;
}

- (void)buildControlsInView:(CPView)parent
{
    // Filter by type
    var filterLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 74.0, 100.0, 18.0)];
    [filterLabel setStringValue:@"Event Type:"];
    [filterLabel setEditable:NO];
    [filterLabel setBezeled:NO];
    [filterLabel setDrawsBackground:NO];
    [parent addSubview:filterLabel];

    _filterTypePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(100.0, 70.0, 120.0, 24.0)];
    [_filterTypePopup addItemsWithTitles:[@"All,Commit,Identity,Account,Error" componentsSeparatedByString:@","]];
    [_filterTypePopup setTarget:self];
    [_filterTypePopup setAction:@selector(handleFilterChanged:)];
    [parent addSubview:_filterTypePopup];

    // Filter by repo
    var repoLabel = [[CPTextField alloc] initWithFrame:CGRectMake(240.0, 74.0, 100.0, 18.0)];
    [repoLabel setStringValue:@"Repo DID:"];
    [repoLabel setEditable:NO];
    [repoLabel setBezeled:NO];
    [repoLabel setDrawsBackground:NO];
    [parent addSubview:repoLabel];

    _repoFilterField = [[CPTextField alloc] initWithFrame:CGRectMake(310.0, 70.0, 200.0, 24.0)];
    [_repoFilterField setPlaceholderString:@"did:plc:..."];
    [_repoFilterField setTarget:self];
    [_repoFilterField setAction:@selector(handleRepoFilterChanged:)];
    [parent addSubview:_repoFilterField];

    // Control buttons
    _connectButton = [[CPButton alloc] initWithFrame:CGRectMake(530.0, 68.0, 100.0, 28.0)];
    [_connectButton setTitle:@"Connect"];
    [_connectButton setTarget:self];
    [_connectButton setAction:@selector(handleConnect:)];

    [parent addSubview:_connectButton];

    _pauseButton = [[CPButton alloc] initWithFrame:CGRectMake(640.0, 68.0, 80.0, 28.0)];
    [_pauseButton setTitle:@"Pause"];
    [_pauseButton setTarget:self];
    [_pauseButton setAction:@selector(handleTogglePause:)];
    [_pauseButton setEnabled:NO];

    [parent addSubview:_pauseButton];

    _clearButton = [[CPButton alloc] initWithFrame:CGRectMake(730.0, 68.0, 60.0, 28.0)];
    [_clearButton setTitle:@"Clear"];
    [_clearButton setTarget:self];
    [_clearButton setAction:@selector(handleClear:)];

    [parent addSubview:_clearButton];

    // Event count
    var countLabel = [[CPTextField alloc] initWithFrame:CGRectMake(820.0, 74.0, 200.0, 18.0)];
    [countLabel setStringValue:@"Max: 500 events"];
    [countLabel setEditable:NO];
    [countLabel setBezeled:NO];
    [countLabel setDrawsBackground:NO];
    [countLabel setTextColor:[CPColor grayColor]];
    [countLabel setTag:@"countLabel"];
    [parent addSubview:countLabel];
}

- (void)buildEventsTableInView:(CPView)parent
{
    var tableLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 110.0, 200.0, 18.0)];
    [tableLabel setStringValue:@"Event Stream"];
    [tableLabel setEditable:NO];
    [tableLabel setBezeled:NO];
    [tableLabel setDrawsBackground:NO];
    [tableLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [parent addSubview:tableLabel];

    _eventsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 700.0, 540.0)];
    [_eventsTable setDelegate:self];
    [_eventsTable setDataSource:self];
    [_eventsTable setAllowsEmptySelection:YES];
    [_eventsTable setAllowsMultipleSelection:NO];
    // setAlternatingRowBackgroundColors: not available in current Cappuccino

    // Time Column
    var timeColumn = [[CPTableColumn alloc] initWithIdentifier:@"time"];
    [[timeColumn headerView] setStringValue:@"Time"];
    [timeColumn setWidth:80.0];
    [_eventsTable addTableColumn:timeColumn];

    // Type Column
    var typeColumn = [[CPTableColumn alloc] initWithIdentifier:@"type"];
    [[typeColumn headerView] setStringValue:@"Type"];
    [typeColumn setWidth:80.0];
    [_eventsTable addTableColumn:typeColumn];

    // Repo Column
    var repoColumn = [[CPTableColumn alloc] initWithIdentifier:@"repo"];
    [[repoColumn headerView] setStringValue:@"Repo"];
    [repoColumn setWidth:200.0];
    [_eventsTable addTableColumn:repoColumn];

    // Sequence Column
    var seqColumn = [[CPTableColumn alloc] initWithIdentifier:@"seq"];
    [[seqColumn headerView] setStringValue:@"Seq"];
    [seqColumn setWidth:100.0];
    [_eventsTable addTableColumn:seqColumn];

    // Summary Column
    var summaryColumn = [[CPTableColumn alloc] initWithIdentifier:@"summary"];
    [[summaryColumn headerView] setStringValue:@"Summary"];
    [summaryColumn setWidth:220.0];
    [_eventsTable addTableColumn:summaryColumn];

    var scrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 130.0, 720.0, 550.0)];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setDocumentView:_eventsTable];
    [scrollView setBorderType:CPBezelBorder];
    [parent addSubview:scrollView];
}

- (void)buildEventDetailViewInView:(CPView)parent
{
    var detailLabel = [[CPTextField alloc] initWithFrame:CGRectMake(760.0, 110.0, 200.0, 18.0)];
    [detailLabel setStringValue:@"Event Detail"];
    [detailLabel setEditable:NO];
    [detailLabel setBezeled:NO];
    [detailLabel setDrawsBackground:NO];
    [detailLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [parent addSubview:detailLabel];

    _eventDetailTextView = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, 0.0, 290.0, 530.0)];
    [_eventDetailTextView setEditable:NO];
    [_eventDetailTextView setSelectable:YES];
    [_eventDetailTextView setString:@""];
    [_eventDetailTextView setFont:[CPFont fontWithName:@"Menlo" size:10.0]];

    var scroll = [[CPScrollView alloc] initWithFrame:CGRectMake(760.0, 130.0, 310.0, 550.0)];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setDocumentView:_eventDetailTextView];
    [scroll setBorderType:CPBezelBorder];
    [parent addSubview:scroll];
}

#pragma mark - WebSocket Connection

- (void)handleConnect:(id)sender
{
    if (_isConnected)
    {
        [self disconnect];
        return;
    }

    [self connect];
}

- (void)connect
{
    if (_webSocket)
        return;

    // Build WebSocket URL - use standard firehose endpoint
    var protocol = (window.location.protocol === "https:") ? "wss:" : "ws:";
    var host = window.location.host;
    var wsUrl = protocol + "//" + host + "/xrpc/com.atproto.sync.subscribeRepos";

    [_statusLabel setStringValue:@"Connecting to " + wsUrl + "..."];

    try
    {
        _webSocket = new WebSocket(wsUrl);

        _webSocket.onopen = function()
        {
            _isConnected = YES;
            _isPolling = NO;
            [self stopPolling];
            _wsErrorLogged = NO;
            [_statusLabel setStringValue:@"Connected (real-time)"];
            [_connectButton setTitle:@"Disconnect"];
            [_pauseButton setEnabled:YES];
        };

        _webSocket.onmessage = function(event)
        {
            if (_isPaused)
                return;

            try
            {
                var data = JSON.parse(event.data);
                [self addEvent:data];
            }
            catch (e)
            {
                // Raw text event
                [self addRawEvent:event.data];
            }
        };

        _webSocket.onclose = function(event)
        {
            _isConnected = NO;
            _webSocket = nil;
            if (!_isPolling)
            {
                [_statusLabel setStringValue:@"Disconnected (code: " + event.code + ") - retrying..."];
                [self startPollingFallback];
            }
            else
            {
                [_statusLabel setStringValue:@"Disconnected (code: " + event.code + ")"];
            }
            [_connectButton setTitle:@"Connect"];
            [_pauseButton setEnabled:NO];
        };

        _webSocket.onerror = function(error)
        {
            if (!_wsErrorLogged)
            {
                [_statusLabel setStringValue:@"WebSocket error - falling back to polling"];
                _wsErrorLogged = YES;
            }
            [self startPollingFallback];
        };
    }
    catch (e)
    {
        [_statusLabel setStringValue:@"Failed to create WebSocket: " + String(e)];
    }
}

- (void)disconnect
{
    if (_webSocket)
    {
        _webSocket.close();
        _webSocket = nil;
    }
    [self stopPolling];
    _isConnected = NO;
    _isPolling = NO;
    _wsErrorLogged = NO;
    [_connectButton setTitle:@"Connect"];
    [_pauseButton setEnabled:NO];
    [_statusLabel setStringValue:@"Disconnected"];
}

#pragma mark - Polling Fallback

- (void)startPollingFallback
{
    if (_isPolling)
        return;

    _isPolling = YES;
    _pollCursor = nil;
    [_statusLabel setStringValue:@"Polling (fallback mode)"];
    [_pauseButton setEnabled:YES];

    [self pollOnce];

    var self = this;
    _pollTimer = setInterval(function() { [self pollOnce]; }, 5000);
}

- (void)stopPolling
{
    if (_pollTimer)
    {
        clearInterval(_pollTimer);
        _pollTimer = nil;
    }
    _isPolling = NO;
}

- (void)pollOnce
{
    if (!_isPolling || _isPaused)
        return;

    var protocol = window.location.protocol;
    var host = window.location.host;
    var url = protocol + "//" + host + "/xrpc/com.atproto.sync.getRepo?limit=100";
    if (_pollCursor)
        url += "&cursor=" + encodeURIComponent(_pollCursor);

    var xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.setRequestHeader("Accept", "application/json");

    var self = this;
    xhr.onload = function()
    {
        if (xhr.status === 200)
        {
            try
            {
                var data = JSON.parse(xhr.responseText);
                if (data.repos && data.repos.length > 0)
                {
                    for (var i = 0; i < data.repos.length; i++)
                    {
                        var repo = data.repos[i];
                        [self addEvent:{type: "commit", repo: repo.did, seq: repo.rev, ops: [], summary: "repo: " + repo.did.substring(0, 12)}];
                    }
                    _pollCursor = data.cursor;
                }
                else if (data.cursor)
                {
                    _pollCursor = data.cursor;
                }
            }
            catch (e)
            {
                // Ignore parse errors
            }
        }
    };

    xhr.send();
}

- (void)dealloc
{
    [self disconnect];
}

#pragma mark - Event Handling

- (void)addEvent:(id)eventData
{
    var event = {
        time: new Date().toLocaleTimeString(),
        type: eventData.type || eventData.kind || "unknown",
        repo: eventData.repo || eventData.did || "",
        seq: eventData.seq || eventData.sequence || "",
        summary: [self eventSummary:eventData],
        raw: eventData
    };

    _events.unshift(event);

    // Trim to max
    while (_events.length > _maxEvents)
        _events.pop();

    [self applyFilters];
}

- (void)addRawEvent:(CPString)rawData
{
    var event = {
        time: new Date().toLocaleTimeString(),
        type: "raw",
        repo: "",
        seq: "",
        summary: [self safeString:rawData].substring(0, 50),
        raw: rawData
    };

    _events.unshift(event);

    while (_events.length > _maxEvents)
        _events.pop();

    [self applyFilters];
}

- (CPString)eventSummary:(id)event
{
    var type = event.type || event.kind || "";

    if (type === "commit" || type === "#commit")
    {
        var ops = event.ops || [];
        var summary = ops.length + " ops: ";
        var types = [];
        for (var i = 0; i < ops.length && i < 3; i++)
        {
            var op = ops[i];
            if (op.action === "create") types.push("+");
            else if (op.action === "update") types.push("~");
            else if (op.action === "delete") types.push("-");
            else types.push("?");
        }
        return summary + types.join(" ");
    }

    if (type === "identity" || type === "#identity")
    {
        return "Identity update";
    }

    if (type === "account" || type === "#account")
    {
        return "Account: " + (event.active ? "active" : "deactivated");
    }

    if (type === "error" || event.error)
    {
        return "Error: " + (event.error || "unknown");
    }

    return type || "unknown";
}

- (void)applyFilters
{
    var filterType = [_filterTypePopup titleOfSelectedItem] || @"All";
    var repoFilter = [self safeString:[_repoFilterField stringValue]].toLowerCase();

    _filteredEvents = [];

    for (var i = 0; i < _events.length; i++)
    {
        var event = _events[i];
        var typeMatch = YES;
        var repoMatch = YES;

        // Type filter
        if (filterType && filterType !== @"All")
        {
            var eventType = (event.type || "").toLowerCase();
            if (filterType === @"Commit" && eventType !== "commit" && eventType !== "#commit")
                typeMatch = NO;
            else if (filterType === @"Identity" && eventType !== "identity" && eventType !== "#identity")
                typeMatch = NO;
            else if (filterType === @"Account" && eventType !== "account" && eventType !== "#account")
                typeMatch = NO;
            else if (filterType === @"Error" && eventType !== "error" && !event.raw.error)
                typeMatch = NO;
        }

        // Repo filter
        if (repoFilter.length > 0)
        {
            var eventRepo = (event.repo || "").toLowerCase();
            if (eventRepo.indexOf(repoFilter) < 0)
                repoMatch = NO;
        }

        if (typeMatch && repoMatch)
            _filteredEvents.push(event);
    }

    [_eventsTable reloadData];

    // Update count label
    var countLabel = [_rootView viewWithTag:@"countLabel"];
    if (countLabel)
        [countLabel setStringValue:String(_filteredEvents.length) + "/" + String(_events.length) + " events"];
}

#pragma mark - Actions

- (void)handleTogglePause:(id)sender
{
    _isPaused = !_isPaused;
    [_pauseButton setTitle:_isPaused ? @"Resume" : @"Pause"];
    if (_isPaused)
        [_statusLabel setStringValue:@"Paused"];
    else if (_isPolling)
        [_statusLabel setStringValue:@"Polling (fallback mode)"];
    else if (_isConnected)
        [_statusLabel setStringValue:@"Connected (real-time)"];
    else
        [_statusLabel setStringValue:@"Disconnected"];
}

- (void)handleClear:(id)sender
{
    _events = [];
    _filteredEvents = [];
    _selectedEvent = nil;
    [_eventsTable reloadData];
    [_eventDetailTextView setString:@""];
}

- (void)handleFilterChanged:(id)sender
{
    [self applyFilters];
}

- (void)handleRepoFilterChanged:(id)sender
{
    [self applyFilters];
}

#pragma mark - Helpers

- (CPString)safeString:(id)value
{
    if (value === nil || value === undefined)
        return @"";
    if (typeof value === "string")
        return value;
    return String(value);
}

#pragma mark - CPTableView DataSource

- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    return _filteredEvents.length;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (row < 0 || row >= _filteredEvents.length)
        return @"";

    var event = _filteredEvents[row],
        identifier = [tableColumn identifier];

    if ([identifier isEqual:@"time"])
        return event.time || "";
    else if ([identifier isEqual:@"type"])
        return event.type || "";
    else if ([identifier isEqual:@"repo"])
        return [self abbreviatedRepo:event.repo];
    else if ([identifier isEqual:@"seq"])
        return String(event.seq || "");
    else if ([identifier isEqual:@"summary"])
        return event.summary || "";

    return @"";
}

- (CPString)abbreviatedRepo:(CPString)repo
{
    if (!repo || repo.length < 24)
        return repo || "";
    return repo.substring(0, 12) + "..." + repo.substring(repo.length - 8);
}

#pragma mark - CPTableView Delegate

- (void)tableViewSelectionDidChange:(CPNotification)notification
{
    var row = [_eventsTable selectedRow];
    if (row < 0 || row >= _filteredEvents.length)
    {
        _selectedEvent = nil;
        [_eventDetailTextView setString:@""];
        return;
    }

    _selectedEvent = _filteredEvents[row];
    var raw = _selectedEvent.raw;

    try
    {
        var pretty = JSON.stringify(raw, null, 2);
        [_eventDetailTextView setString:pretty];
    }
    catch (e)
    {
        [_eventDetailTextView setString:[self safeString:raw]];
    }
}

@end
