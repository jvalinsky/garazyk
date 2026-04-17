/*
 * PLCDirectoryController.j
 * CappuccinoUI
 *
 * PLC directory browser - lists all registered DIDs
 * with search/filter and click-to-view functionality.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "EmptyStateView.j"

@implementation PLCDirectoryController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTableView _didTable;
    CPArray _dids;
    CPArray _filteredDids;
    CPTextField _searchField;
    CPTextField _statusLabel;
    CPTextField _countLabel;
    EmptyStateView _emptyState;

    id _delegate;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _dids = [];
        _filteredDids = [];
    }
    return self;
}

- (void)setDelegate:(id)delegate
{
    _delegate = delegate;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    var rootFrame = CGRectMake(0.0, 0.0, 1080.0, 700.0),
        statusFrame = CGRectMake(20.0, 16.0, 600.0, 20.0);

    _rootView = [[CPView alloc] initWithFrame:rootFrame];
    [_rootView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    _statusLabel = [[CPTextField alloc] initWithFrame:statusFrame];
    [_statusLabel setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Loading..."];
    [_rootView addSubview:_statusLabel];

    [self buildControlsInView:_rootView];
    [self buildTableInView:_rootView];

    // Load initial data
    [self loadDirectory];

    return _rootView;
}

- (void)buildControlsInView:(CPView)parent
{
    // Search field
    var searchLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 72.0, 60.0, 24.0)];
    [searchLabel setStringValue:@"Search:"];
    [searchLabel setEditable:NO];
    [searchLabel setBezeled:NO];
    [searchLabel setDrawsBackground:NO];
    [parent addSubview:searchLabel];

    _searchField = [[CPTextField alloc] initWithFrame:CGRectMake(80.0, 72.0, 300.0, 28.0)];
    [_searchField setEditable:YES];
    [_searchField setBezeled:YES];
    [_searchField setTarget:self];
    [_searchField setAction:@selector(handleSearch:)];
    [parent addSubview:_searchField];

    // Refresh button
    var refreshButton = [[CPButton alloc] initWithFrame:CGRectMake(400.0, 72.0, 80.0, 28.0)];
    [refreshButton setTitle:@"Refresh"];
    [refreshButton setTarget:self];
    [refreshButton setAction:@selector(handleRefresh:)];
    [parent addSubview:refreshButton];

    // Count label
    _countLabel = [[CPTextField alloc] initWithFrame:CGRectMake(500.0, 76.0, 200.0, 20.0)];
    [_countLabel setEditable:NO];
    [_countLabel setBezeled:NO];
    [_countLabel setDrawsBackground:NO];
    [_countLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_countLabel setTextColor:[CPColor grayColor]];
    [_countLabel setStringValue:@"0 DIDs"];
    [parent addSubview:_countLabel];
}

- (void)buildTableInView:(CPView)parent
{
    var tableLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 110.0, 200.0, 18.0)];
    [tableLabel setStringValue:@"Registered Identities"];
    [tableLabel setEditable:NO];
    [tableLabel setBezeled:NO];
    [tableLabel setDrawsBackground:NO];
    [tableLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [parent addSubview:tableLabel];

    _didTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1040.0, 540.0)];
    [_didTable setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_didTable setDelegate:self];
    [_didTable setDataSource:self];
    [_didTable setAllowsEmptySelection:YES];
    [_didTable setAllowsMultipleSelection:NO];
    // setAlternatingRowBackgroundColors: not available in current Cappuccino

    // DID Column
    var didColumn = [[CPTableColumn alloc] initWithIdentifier:@"did"];
    [[didColumn headerView] setStringValue:@"DID"];
    [didColumn setWidth:800.0];
    [_didTable addTableColumn:didColumn];

    // Action Column
    var actionColumn = [[CPTableColumn alloc] initWithIdentifier:@"action"];
    [[actionColumn headerView] setStringValue:@"Action"];
    [actionColumn setWidth:100.0];
    [_didTable addTableColumn:actionColumn];
    [_didTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    // Scroll view
    var scroll = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 132.0, 1040.0, 548.0)];
    [scroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [scroll setDocumentView:_didTable];
    [scroll setHasHorizontalScroller:NO];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [parent addSubview:scroll];
}

#pragma mark - Data Loading

- (void)loadDirectory
{
    [_statusLabel setStringValue:@"Loading directory..."];
    [self hideEmptyState];

    [_apiClient fetch:@"GET" path:@"/_list" params:nil completion:function(response, error) {
        if (error) {
            [self setErrorStatus:error.localizedDescription];
            [self showEmptyStateWithIcon:EmptyStateIconCloudOff
                                  message:@"Could not reach PLC directory. " + error.localizedDescription];
            return;
        }

        if (response && response.isa) {
            // Response is CPArray
            _dids = response;
        } else if (response && response.length !== undefined) {
            // Response is JS array
            _dids = [CPArray arrayWithArray:response];
        } else {
            _dids = [];
        }

        _filteredDids = _dids;
        [_didTable reloadData];
        [self updateCountLabel];

        if (_dids.length === 0) {
            [self showEmptyStateWithIcon:EmptyStateIconInbox
                                  message:@"No identities found in PLC directory. New accounts may take a moment to register."];
            [self setSuccessStatus:@"PLC directory is empty"];
        } else {
            [self setSuccessStatus:@"Loaded " + _dids.length + " identities"];
        }
    }];
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
                                                  actionTitle:@"Try Again"
                                                actionHandler:function() { [self loadDirectory]; }];

    [_emptyState setIcon:icon];
    [_emptyState setMessage:message];

    // Position it over the table area if possible
    var frame = [_rootView bounds];
    if (_didTable && [_didTable superview])
    {
        var scroll = [[_didTable superview] superview];
        if (scroll && [scroll isKindOfClass:[CPScrollView class]])
            frame = [scroll frame];
    }
    
    [_emptyState setFrame:frame];
    [_emptyState showInView:_rootView];
}

- (void)hideEmptyState
{
    if (_emptyState)
        [_emptyState hide];
}

- (void)updateCountLabel
{
    var total = _dids.length;
    var filtered = _filteredDids.length;

    if (filtered === total) {
        [_countLabel setStringValue:total + " DIDs"];
    } else {
        [_countLabel setStringValue:filtered + " of " + total + " DIDs"];
    }
}

#pragma mark - Actions

- (void)handleSearch:(id)sender
{
    var query = [_searchField stringValue].toLowerCase();

    if (!query || query.length === 0) {
        _filteredDids = _dids;
    } else {
        var filtered = [];
        for (var i = 0; i < _dids.length; i++) {
            var did = _dids[i];
            if (did.toLowerCase().indexOf(query) !== -1) {
                [filtered addObject:did];
            }
        }
        _filteredDids = filtered;
    }

    [_didTable reloadData];
    [self updateCountLabel];
}

- (void)handleRefresh:(id)sender
{
    [_searchField setStringValue:@""];
    [self loadDirectory];
}

#pragma mark - CPTableViewDataSource

- (CPInteger)numberOfRowsInTableView:(CPTableView)tableView
{
    return _filteredDids ? _filteredDids.length : 0;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)column row:(CPInteger)row
{
    var did = _filteredDids[row];

    if ([column identifier] === @"did") {
        return did;
    } else if ([column identifier] === @"action") {
        return "View";
    }

    return nil;
}

#pragma mark - CPTableViewDelegate

- (BOOL)tableView:(CPTableView)tableView shouldSelectRow:(CPInteger)row
{
    var did = _filteredDids[row];

    // Notify delegate to show detail
    if (_delegate && [_delegate respondsToSelector:@selector(plcDirectoryController:didSelectDID:)]) {
        [_delegate plcDirectoryController:self didSelectDID:did];
    }

    return YES;
}

- (void)tableView:(CPTableView)tableView didClickTableColumn:(CPTableColumn)column
{
    // Could implement sorting here
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

@end
