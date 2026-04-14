/*
 * RelayUpstreamsController.j
 * CappuccinoUI
 *
 * Upstream connection management for the relay.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "EmptyStateView.j"

@implementation RelayUpstreamsController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    CPTableView _upstreamsTable;
    CPTextField _addUpstreamField;
    CPArray _upstreams;
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
        _upstreams = [];
        _isRunning = NO;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 400.0, 28.0)];
    [title setStringValue:@"Upstream Connections"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 1040.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Loading upstreams..."];

    [self buildControlsInView:_rootView];
    [self buildUpstreamsTableInView:_rootView];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];

    [self loadUpstreams];
    [self startAutoRefresh];

    return _rootView;
}

- (void)buildControlsInView:(CPView)parent
{
    // Add upstream input
    var addLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 74.0, 100.0, 18.0)];
    [addLabel setStringValue:@"Add Upstream:"];
    [addLabel setEditable:NO];
    [addLabel setBezeled:NO];
    [addLabel setDrawsBackground:NO];
    [parent addSubview:addLabel];

    _addUpstreamField = [[CPTextField alloc] initWithFrame:CGRectMake(120.0, 70.0, 300.0, 24.0)];
    [_addUpstreamField setPlaceholderString:@"wss://bsky.network"];

    [parent addSubview:_addUpstreamField];

    var addButton = [[CPButton alloc] initWithFrame:CGRectMake(430.0, 68.0, 60.0, 28.0)];
    [addButton setTitle:@"Add"];
    [addButton setTarget:self];
    [addButton setAction:@selector(handleAddUpstream:)];

    [parent addSubview:addButton];

    // Control buttons
    var refreshBtn = [[CPButton alloc] initWithFrame:CGRectMake(510.0, 68.0, 80.0, 28.0)];
    [refreshBtn setTitle:@"Refresh"];
    [refreshBtn setTarget:self];
    [refreshBtn setAction:@selector(handleRefresh:)];

    [parent addSubview:refreshBtn];

    var reconnectAllBtn = [[CPButton alloc] initWithFrame:CGRectMake(600.0, 68.0, 120.0, 28.0)];
    [reconnectAllBtn setTitle:@"Reconnect All"];
    [reconnectAllBtn setTarget:self];
    [reconnectAllBtn setAction:@selector(handleReconnectAll:)];

    [parent addSubview:reconnectAllBtn];

    var disconnectAllBtn = [[CPButton alloc] initWithFrame:CGRectMake(730.0, 68.0, 120.0, 28.0)];
    [disconnectAllBtn setTitle:@"Disconnect All"];
    [disconnectAllBtn setTarget:self];
    [disconnectAllBtn setAction:@selector(handleDisconnectAll:)];

    [parent addSubview:disconnectAllBtn];
}

- (void)buildUpstreamsTableInView:(CPView)parent
{
    // Table header label
    var tableLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 110.0, 200.0, 18.0)];
    [tableLabel setStringValue:@"Connected Upstreams"];
    [tableLabel setEditable:NO];
    [tableLabel setBezeled:NO];
    [tableLabel setDrawsBackground:NO];
    [tableLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [parent addSubview:tableLabel];

    // Create table
    _upstreamsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1040.0, 540.0)];
    [_upstreamsTable setDelegate:self];
    [_upstreamsTable setDataSource:self];
    [_upstreamsTable setAllowsEmptySelection:YES];
    [_upstreamsTable setAllowsMultipleSelection:NO];
    [_upstreamsTable setAlternatingRowBackgroundColors:[[CPColor whiteColor], [CPColor colorWithCalibratedWhite:0.98 alpha:1.0]]];

    // URL Column
    var urlColumn = [[CPTableColumn alloc] initWithIdentifier:@"url"];
    [[urlColumn headerView] setStringValue:@"Upstream URL"];
    [urlColumn setWidth:400.0];
    [_upstreamsTable addTableColumn:urlColumn];

    // Status Column
    var statusColumn = [[CPTableColumn alloc] initWithIdentifier:@"status"];
    [[statusColumn headerView] setStringValue:@"Status"];
    [statusColumn setWidth:120.0];
    [_upstreamsTable addTableColumn:statusColumn];

    // Active Column
    var activeColumn = [[CPTableColumn alloc] initWithIdentifier:@"active"];
    [[activeColumn headerView] setStringValue:@"Active"];
    [activeColumn setWidth:80.0];
    [_upstreamsTable addTableColumn:activeColumn];

    // Actions Column
    var actionsColumn = [[CPTableColumn alloc] initWithIdentifier:@"actions"];
    [[actionsColumn headerView] setStringValue:@"Actions"];
    [actionsColumn setWidth:200.0];
    [_upstreamsTable addTableColumn:actionsColumn];

    // Scroll view
    var scrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 130.0, 1040.0, 550.0)];
    [scrollView setHasVerticalScroller:YES];
    [scrollView setAutohidesScrollers:YES];
    [scrollView setDocumentView:_upstreamsTable];
    [scrollView setBorderType:CPBezelBorder];
    [parent addSubview:scrollView];
}

#pragma mark - Data Loading

- (void)loadUpstreams
{
    [_apiClient getJSONWithPath:@"/upstreams"
                  endpointGroup:@"relay"
                    queryParams:nil
                     completion:function(statusCode, payload, errorMessage)
                     {
                         if (errorMessage)
                         {
                             [_statusLabel setStringValue:@"Error: " + errorMessage];
                             _upstreams = [];
                         }
                         else if (payload && payload.upstreams)
                         {
                             _upstreams = payload.upstreams;
                             [_statusLabel setStringValue:@"Loaded " + _upstreams.length + " upstream(s)"];
                         }
                         else
                         {
                             _upstreams = [];
                             [_statusLabel setStringValue:@"No upstreams configured"];
                         }
                         [_upstreamsTable reloadData];
                     }];
}

#pragma mark - Actions

- (void)handleRefresh:(id)sender
{
    [self loadUpstreams];
}

- (void)handleAddUpstream:(id)sender
{
    var url = [_addUpstreamField stringValue];
    if (!url || url.length === 0)
    {
        [_statusLabel setStringValue:@"Enter an upstream URL"];
        return;
    }

    // Basic validation
    if (!url.startsWith("wss://") && !url.startsWith("ws://"))
    {
        [_statusLabel setStringValue:@"URL must start with wss:// or ws://"];
        return;
    }

    [_statusLabel setStringValue:@"Adding upstream " + url + "..."];

    [_apiClient requestJSONWithPath:@"/upstreams"
                      endpointGroup:@"relay"
                             method:@"POST"
                        queryParams:nil
                         bodyObject:@{url: url}
                           completion:function(statusCode, payload, errorMessage)
                           {
                               if (errorMessage || statusCode >= 400)
                               {
                                   [_statusLabel setStringValue:@"Failed to add upstream: " + (errorMessage || "HTTP " + statusCode)];
                               }
                               else
                               {
                                   [_statusLabel setStringValue:@"Upstream added: " + url];
                                   [_addUpstreamField setStringValue:@""];
                                   [self loadUpstreams];
                               }
                           }];
}

- (void)handleReconnectAll:(id)sender
{
    [_statusLabel setStringValue:@"Reconnecting all upstreams..."];

    [_apiClient requestJSONWithPath:@"/upstreams/reconnect-all"
                      endpointGroup:@"relay"
                             method:@"POST"
                        queryParams:nil
                         bodyObject:nil
                           completion:function(statusCode, payload, errorMessage)
                           {
                               if (errorMessage || statusCode >= 400)
                               {
                                   [_statusLabel setStringValue:@"Failed to reconnect: " + (errorMessage || "HTTP " + statusCode)];
                               }
                               else
                               {
                                   [_statusLabel setStringValue:@"All upstreams reconnecting..."];
                                   [self loadUpstreams];
                               }
                           }];
}

- (void)handleDisconnectAll:(id)sender
{
    [_statusLabel setStringValue:@"Disconnecting all upstreams..."];

    [_apiClient requestJSONWithPath:@"/upstreams/disconnect-all"
                      endpointGroup:@"relay"
                             method:@"POST"
                        queryParams:nil
                         bodyObject:nil
                           completion:function(statusCode, payload, errorMessage)
                           {
                               if (errorMessage || statusCode >= 400)
                               {
                                   [_statusLabel setStringValue:@"Failed to disconnect: " + (errorMessage || "HTTP " + statusCode)];
                               }
                               else
                               {
                                   [_statusLabel setStringValue:@"All upstreams disconnected"];
                                   [self loadUpstreams];
                               }
                           }];
}

- (void)handleConnectUpstream:(id)sender
{
    var url = [sender tag];
    if (!url) return;

    [_statusLabel setStringValue:@"Connecting to " + url + "..."];

    // URL encode for path
    var encodedUrl = encodeURIComponent(String(url));
    [_apiClient requestJSONWithPath:("/upstreams/" + encodedUrl + "/connect")
                      endpointGroup:@"relay"
                             method:@"POST"
                        queryParams:nil
                         bodyObject:nil
                           completion:function(statusCode, payload, errorMessage)
                           {
                               if (errorMessage || statusCode >= 400)
                               {
                                   [_statusLabel setStringValue:@"Failed to connect: " + (errorMessage || "HTTP " + statusCode)];
                               }
                               else
                               {
                                   [_statusLabel setStringValue:@"Connected to " + url];
                                   [self loadUpstreams];
                               }
                           }];
}

- (void)handleDisconnectUpstream:(id)sender
{
    var url = [sender tag];
    if (!url) return;

    var selfRef = self;
    [self confirmDisconnectUpstream:url handler:function()
    {
        [selfRef disconnectUpstream:url];
    }];
}

- (void)disconnectUpstream:(CPString)url
{
    [_statusLabel setStringValue:@"Disconnecting from " + url + "..."];
    [self setWarningStatus:@"Disconnecting..."];

    var encodedUrl = encodeURIComponent(String(url));
    var selfRef = self;
    [_apiClient requestJSONWithPath:("/upstreams/" + encodedUrl + "/disconnect")
                      endpointGroup:@"relay"
                             method:@"POST"
                        queryParams:nil
                         bodyObject:nil
                           completion:function(statusCode, payload, errorMessage)
                           {
                               if (errorMessage || statusCode >= 400)
                               {
                                   [selfRef setErrorStatus:@"Failed to disconnect: " + (errorMessage || "HTTP " + statusCode)];
                               }
                               else
                               {
                                   [selfRef setSuccessStatus:@"Disconnected from " + url];
                                   [selfRef loadUpstreams];
                               }
                           }];
}

- (void)handleRemoveUpstream:(id)sender
{
    var url = [sender tag];
    if (!url) return;

    var selfRef = self;
    [self confirmRemoveUpstream:url handler:function()
    {
        [selfRef removeUpstream:url];
    }];
}

- (void)removeUpstream:(CPString)url
{
    [_statusLabel setStringValue:@"Removing upstream " + url + "..."];
    [self setWarningStatus:@"Removing..."];

    var encodedUrl = encodeURIComponent(String(url));
    var selfRef = self;
    [_apiClient requestJSONWithPath:("/upstreams/" + encodedUrl)
                      endpointGroup:@"relay"
                             method:@"DELETE"
                        queryParams:nil
                         bodyObject:nil
                           completion:function(statusCode, payload, errorMessage)
                           {
                               if (errorMessage || statusCode >= 400)
                               {
                                   [selfRef setErrorStatus:@"Failed to remove: " + (errorMessage || "HTTP " + statusCode)];
                               }
                               else
                               {
                                   [selfRef setSuccessStatus:@"Removed upstream " + url];
                                   [selfRef loadUpstreams];
                               }
                           }];
}

#pragma mark - Auto Refresh

- (void)startAutoRefresh
{
    if (_isRunning)
        return;

    _isRunning = YES;

    if (!(window && window.setInterval))
        return;

    _refreshTimer = window.setInterval(function()
    {
        if (_isRunning)
            [self loadUpstreams];
    }, 5000);
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

#pragma mark - CPTableView DataSource

- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    return _upstreams.length;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (row < 0 || row >= _upstreams.length)
        return @"";

    var upstream = _upstreams[row],
        identifier = [tableColumn identifier];

    if ([identifier isEqual:@"url"])
    {
        return upstream.url || "";
    }
    else if ([identifier isEqual:@"status"])
    {
        return upstream.status || "unknown";
    }
    else if ([identifier isEqual:@"active"])
    {
        return upstream.active ? @"Yes" : @"No";
    }
    else if ([identifier isEqual:@"actions"])
    {
        // Return a string representation; actual buttons need custom cell
        return "Connect | Disconnect | Remove";
    }

    return @"";
}

#pragma mark - CPTableView Delegate

- (BOOL)tableView:(CPTableView)tableView shouldSelectRow:(int)row
{
    return YES;
}

#pragma mark - Status Helpers

- (void)setErrorStatus:(CPString)message
{
    [_statusLabel setStringValue:@"Error: " + message];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(185.0/255.0)
                                                         green:(28.0/255.0)
                                                          blue:(28.0/255.0)
                                                         alpha:1.0]];
}

- (void)setSuccessStatus:(CPString)message
{
    [_statusLabel setStringValue:message];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(4.0/255.0)
                                                         green:(120.0/255.0)
                                                          blue:(87.0/255.0)
                                                         alpha:1.0]];
}

- (void)setWarningStatus:(CPString)message
{
    [_statusLabel setStringValue:@"Warning: " + message];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(180.0/255.0)
                                                         green:(83.0/255.0)
                                                          blue:(9.0/255.0)
                                                         alpha:1.0]];
}

#pragma mark - Confirmation Dialogs

- (void)confirmDisconnectUpstream:(CPString)upstreamURL handler:(Function)handler
{
    var alert = [[CPAlert alloc] init];
    [alert setAlertStyle:CPAlertStyleWarning];
    [alert setMessageText:@"Disconnect upstream?"];
    [alert setInformativeText:@"This will stop syncing from " + upstreamURL + ". You can reconnect later."];

    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Disconnect"];

    var buttons = [alert buttons];
    if (buttons && buttons.length >= 2)
    {

    }

    var window = [_rootView window];
    if (window)
    {
        [alert beginSheetModalForWindow:window completionHandler:function(response)
        {
            if (response === 1 && handler)
                handler();
        }];
    }
}

- (void)confirmRemoveUpstream:(CPString)upstreamURL handler:(Function)handler
{
    var alert = [[CPAlert alloc] init];
    [alert setAlertStyle:CPAlertStyleCritical];
    [alert setMessageText:@"Remove upstream?"];
    [alert setInformativeText:@"This will permanently remove " + upstreamURL + " from the configuration."];

    [alert addButtonWithTitle:@"Cancel"];
    [alert addButtonWithTitle:@"Remove"];

    var buttons = [alert buttons];
    if (buttons && buttons.length >= 2)
    {

    }

    var window = [_rootView window];
    if (window)
    {
        [alert beginSheetModalForWindow:window completionHandler:function(response)
        {
            if (response === 1 && handler)
                handler();
        }];
    }
}

@end
