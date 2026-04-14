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

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    // Title
    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 400.0, 28.0)];
    [title setStringValue:@"PLC Directory"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];
    [_rootView addSubview:title];

    // Status label
    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 600.0, 20.0)];
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

    // Scroll view
    var scroll = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 132.0, 1040.0, 548.0)];
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

    [_apiClient fetch:@"GET" path:@"/_list" params:nil completion:function(response, error) {
        if (error) {
            [_statusLabel setStringValue:@"Error: " + error.localizedDescription];
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
        [_statusLabel setStringValue:@"Loaded " + _dids.length + " identities"];
    }];
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
    return _filteredDids.length;
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
