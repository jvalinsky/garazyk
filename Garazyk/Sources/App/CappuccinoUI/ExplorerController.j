/*
 * ExplorerController.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "LoadingSpinner.j"
@import "EmptyStateView.j"

@implementation ExplorerController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;
    CPTextField _statusLabel;
    CPTextField _lookupField;
    CPTextField _cidField;
    CPTableView _accountsTable;
    CPTableView _collectionsTable;
    CPTableView _recordsTable;
    CPTabView _detailsTabView;
    CPPopUpButton _feedModePopup;
    CPPopUpButton _feedViewModePopup;
    CPPopUpButton _recordModePopup;
    CPPopUpButton _profileViewModePopup;
    CPPopUpButton _mstExportFormatPopup;
    CPPopUpButton _didViewModePopup;
    CPPopUpButton _plcViewModePopup;
    CPTextView _didTextView;
    CPTextView _plcTextView;
    CPView _didRenderedView;
    CPTableView _didSummaryTable;
    CPTableView _didItemsTable;
    CPView _plcRenderedView;
    CPTableView _plcOpsTable;
    CPTableView _plcDetailTable;
    CPTextView _recordDetailTextView;
    CPView _recordRenderedView;
    CPTableView _recordSummaryTable;
    CPTextView _recordBodyTextView;
    CPTextView _feedTextView;
    CPView _feedRenderedView;
    CPTableView _feedTable;
    CPTableView _feedDetailTable;
    CPTableView _graphTable;
    CPTableView _graphDetailTable;
    CPTextView _profileTextView;
    CPView _profileRenderedView;
    CPTableView _profileSummaryTable;
    CPTextView _profileBioTextView;
    CPTextView _utilityTextView;
    CPTextField _mstDidField;
    CPView _mstTreeListView;
    CPTableView _mstStatsTable;
    CPTableView _mstNodesTable;
    CPTextView _mstTreeTextView;
    CPTextField _oauthHandleField;
    CPTextField _oauthDidField;
    CPTextField _postTextField;
    CPTextField _postReplyField;
    CPTextView _authResultTextView;

    CPArray _accounts;
    CPArray _collections;
    CPArray _records;
    id _currentRecordPayload;
    id _currentFeedPayload;
    id _currentProfilePayload;
    id _currentMSTTreePayload;
    id _currentMSTStatsPayload;
    id _currentDIDPayload;
    id _currentPLCPayload;
    CPString _currentDID;
    CPString _currentHandle;
    CPString _selectedCollection;
    CPString _currentFeedMode;
    BOOL _mstExpanded;
    id _dpopKeyPair;
    CPString _oauthAccessToken;
    CPString _oauthSessionDid;
    CPArray _recordSummaryRows;
    CPArray _feedRows;
    CPArray _feedDetailRows;
    CPArray _graphRows;
    CPArray _graphDetailRows;
    CPArray _profileSummaryRows;
    CPArray _mstStatsRows;
    CPArray _mstNodeRows;
    LoadingSpinner _loadingSpinner;
    CPArray _didSummaryRows;
    CPArray _didItemRows;
    CPArray _plcOpRows;
    CPArray _plcDetailRows;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _accounts = [];
        _collections = [];
        _records = [];
        _currentRecordPayload = nil;
        _currentFeedPayload = nil;
        _currentProfilePayload = nil;
        _currentMSTTreePayload = nil;
        _currentMSTStatsPayload = nil;
        _currentDIDPayload = nil;
        _currentPLCPayload = nil;
        _currentDID = nil;
        _currentHandle = nil;
        _selectedCollection = nil;
        _currentFeedMode = @"Posts";
        _mstExpanded = NO;
        _dpopKeyPair = nil;
        _oauthAccessToken = nil;
        _oauthSessionDid = nil;
        _recordSummaryRows = [];
        _feedRows = [];
        _feedDetailRows = [];
        _graphRows = [];
        _graphDetailRows = [];
        _profileSummaryRows = [];
        _mstStatsRows = [];
        _mstNodeRows = [];
        _didSummaryRows = [];
        _didItemRows = [];
        _plcOpRows = [];
        _plcDetailRows = [];
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];
    [_rootView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 900.0, 28.0)];
    [title setStringValue:@"Explore"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];
    // Accessibility: setAccessibilityLabel:@"Explore Dashboard Title"

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 1040.0, 20.0)];
    [_statusLabel setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Idle"];
    // Accessibility: setAccessibilityLabel:@"Status message"

    _lookupField = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 72.0, 260.0, 28.0)];
    [_lookupField setPlaceholderString:@"Enter DID or handle"];
    // Accessibility: setAccessibilityLabel:@"DID or handle lookup input"
    // Accessibility: setAccessibilityHint:@"Enter a DID (did:plc:xxx) or handle (user.bskysocial.com) to look up"

    var lookupButton = [[CPButton alloc] initWithFrame:CGRectMake(290.0, 72.0, 80.0, 28.0)];
    [lookupButton setTitle:@"Lookup"];
    [lookupButton setTarget:self];
    [lookupButton setAction:@selector(handleLookup:)];
    // Accessibility: setAccessibilityLabel:@"Lookup DID or handle"
    // Accessibility: setAccessibilityHint:@"Search for the DID or handle entered above"

    var refreshButton = [[CPButton alloc] initWithFrame:CGRectMake(380.0, 72.0, 110.0, 28.0)];
    [refreshButton setTitle:@"Refresh Accounts"];
    [refreshButton setTarget:self];
    [refreshButton setAction:@selector(handleRefreshAccounts:)];
    // Accessibility: setAccessibilityLabel:@"Refresh accounts list"
    // Accessibility: setAccessibilityHint:@"Reload the list of known accounts"

    var docsButton = [[CPButton alloc] initWithFrame:CGRectMake(500.0, 72.0, 90.0, 28.0)];
    [docsButton setTitle:@"API Docs"];
    [docsButton setTarget:self];
    [docsButton setAction:@selector(handleOpenDocs:)];
    // Accessibility: setAccessibilityLabel:@"Open API documentation"
    // Accessibility: setAccessibilityHint:@"Open the AT Protocol API documentation in a new window"

    var accountsLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 106.0, 120.0, 18.0)];
    [accountsLabel setStringValue:@"Accounts"];
    [accountsLabel setEditable:NO];
    [accountsLabel setBezeled:NO];
    [accountsLabel setDrawsBackground:NO];
    [accountsLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    // Accessibility: setAccessibilityLabel:@"Accounts section header"

    _accountsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 240.0, 530.0)];
    [_accountsTable setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_accountsTable setDelegate:self];
    [_accountsTable setDataSource:self];
    [_accountsTable setAllowsEmptySelection:YES];
    [_accountsTable setAllowsMultipleSelection:NO];
    // Accessibility: setAccessibilityLabel:@"Accounts list"
    // Accessibility: setAccessibilityHint:@"Select an account to view details"

    var accountColumn = [[CPTableColumn alloc] initWithIdentifier:@"account"];
    [[accountColumn headerView] setStringValue:@"Handle / DID"];
    [accountColumn setWidth:240.0];
    [_accountsTable addTableColumn:accountColumn];
    [_accountsTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var accountsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 130.0, 260.0, 540.0)];
    [accountsScroll setAutoresizingMask:CPViewMaxXMargin | CPViewHeightSizable];
    [accountsScroll setHasVerticalScroller:YES];
    [accountsScroll setAutohidesScrollers:YES];
    [accountsScroll setDocumentView:_accountsTable];

    _detailsTabView = [[CPTabView alloc] initWithFrame:CGRectMake(300.0, 106.0, 760.0, 564.0)];
    [_detailsTabView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [self setUpDetailTabs];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];
    [_rootView addSubview:_lookupField];
    [_rootView addSubview:lookupButton];
    [_rootView addSubview:refreshButton];
    [_rootView addSubview:docsButton];
    [_rootView addSubview:accountsLabel];
    [_rootView addSubview:accountsScroll];
    [_rootView addSubview:_detailsTabView];

    [self restoreAuthSessionFromStorage];
    [self handleOAuthCallbackIfPresent];
    [self loadAccounts];

    return _rootView;
}

- (void)setUpDetailTabs
{
    var didTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [didTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    var didViewLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 40.0, 18.0)];
    [didViewLabel setStringValue:@"View:"];
    [didViewLabel setEditable:NO];
    [didViewLabel setBezeled:NO];
    [didViewLabel setDrawsBackground:NO];
    [didTab addSubview:didViewLabel];

    _didViewModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(52.0, 10.0, 120.0, 24.0)];
    [_didViewModePopup addItemsWithTitles:[@"Rendered,JSON" componentsSeparatedByString:@","]];
    [_didViewModePopup setTarget:self];
    [_didViewModePopup setAction:@selector(handleDidViewModeChanged:)];
    [didTab addSubview:_didViewModePopup];

    _didRenderedView = [[CPView alloc] initWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)];
    [_didRenderedView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [didTab addSubview:_didRenderedView];

    _didSummaryTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 166.0)];
    [_didSummaryTable setDelegate:self];
    [_didSummaryTable setDataSource:self];
    [_didSummaryTable setAllowsEmptySelection:YES];

    [_didSummaryTable setAllowsMultipleSelection:NO];

    var didSummaryFieldColumn = [[CPTableColumn alloc] initWithIdentifier:@"did_summary_field"];
    [[didSummaryFieldColumn headerView] setStringValue:@"Field"];
    [didSummaryFieldColumn setWidth:200.0];
    [_didSummaryTable addTableColumn:didSummaryFieldColumn];

    var didSummaryValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"did_summary_value"];
    [[didSummaryValueColumn headerView] setStringValue:@"Value"];
    [didSummaryValueColumn setWidth:510.0];
    [_didSummaryTable addTableColumn:didSummaryValueColumn];
    [_didSummaryTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var didSummaryScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 166.0)];
    [didSummaryScroll setAutoresizingMask:CPViewWidthSizable];
    [didSummaryScroll setHasVerticalScroller:YES];
    [didSummaryScroll setAutohidesScrollers:YES];
    [didSummaryScroll setDocumentView:_didSummaryTable];
    [_didRenderedView addSubview:didSummaryScroll];

    _didItemsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 282.0)];
    [_didItemsTable setDelegate:self];
    [_didItemsTable setDataSource:self];
    [_didItemsTable setAllowsEmptySelection:YES];

    [_didItemsTable setAllowsMultipleSelection:NO];

    var didItemTypeColumn = [[CPTableColumn alloc] initWithIdentifier:@"did_item_type"];
    [[didItemTypeColumn headerView] setStringValue:@"Type"];
    [didItemTypeColumn setWidth:120.0];
    [_didItemsTable addTableColumn:didItemTypeColumn];

    var didItemLabelColumn = [[CPTableColumn alloc] initWithIdentifier:@"did_item_label"];
    [[didItemLabelColumn headerView] setStringValue:@"Label"];
    [didItemLabelColumn setWidth:220.0];
    [_didItemsTable addTableColumn:didItemLabelColumn];

    var didItemValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"did_item_value"];
    [[didItemValueColumn headerView] setStringValue:@"Value"];
    [didItemValueColumn setWidth:370.0];
    [_didItemsTable addTableColumn:didItemValueColumn];
    [_didItemsTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var didItemsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 176.0, 730.0, 282.0)];
    [didItemsScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [didItemsScroll setHasVerticalScroller:YES];
    [didItemsScroll setAutohidesScrollers:YES];
    [didItemsScroll setDocumentView:_didItemsTable];
    [_didRenderedView addSubview:didItemsScroll];

    _didTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)
                                                  inView:didTab];
    [_didTextView setHidden:YES];
    [self addTabItemWithLabel:@"DID" contentView:didTab];

    var plcTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [plcTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    var plcViewLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 40.0, 18.0)];
    [plcViewLabel setStringValue:@"View:"];
    [plcViewLabel setEditable:NO];
    [plcViewLabel setBezeled:NO];
    [plcViewLabel setDrawsBackground:NO];
    [plcTab addSubview:plcViewLabel];

    _plcViewModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(52.0, 10.0, 120.0, 24.0)];
    [_plcViewModePopup addItemsWithTitles:[@"Rendered,JSON" componentsSeparatedByString:@","]];
    [_plcViewModePopup setTarget:self];
    [_plcViewModePopup setAction:@selector(handlePLCViewModeChanged:)];
    [plcTab addSubview:_plcViewModePopup];

    _plcRenderedView = [[CPView alloc] initWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)];
    [_plcRenderedView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [plcTab addSubview:_plcRenderedView];

    _plcOpsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 258.0)];
    [_plcOpsTable setDelegate:self];
    [_plcOpsTable setDataSource:self];
    [_plcOpsTable setAllowsEmptySelection:YES];

    [_plcOpsTable setAllowsMultipleSelection:NO];

    var plcWhenColumn = [[CPTableColumn alloc] initWithIdentifier:@"plc_op_when"];
    [[plcWhenColumn headerView] setStringValue:@"When"];
    [plcWhenColumn setWidth:170.0];
    [_plcOpsTable addTableColumn:plcWhenColumn];

    var plcSummaryColumn = [[CPTableColumn alloc] initWithIdentifier:@"plc_op_summary"];
    [[plcSummaryColumn headerView] setStringValue:@"Summary"];
    [plcSummaryColumn setWidth:180.0];
    [_plcOpsTable addTableColumn:plcSummaryColumn];

    var plcDetailsColumn = [[CPTableColumn alloc] initWithIdentifier:@"plc_op_details"];
    [[plcDetailsColumn headerView] setStringValue:@"Details"];
    [plcDetailsColumn setWidth:360.0];
    [_plcOpsTable addTableColumn:plcDetailsColumn];
    [_plcOpsTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var plcOpsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 258.0)];
    [plcOpsScroll setAutoresizingMask:CPViewWidthSizable];
    [plcOpsScroll setHasVerticalScroller:YES];
    [plcOpsScroll setAutohidesScrollers:YES];
    [plcOpsScroll setDocumentView:_plcOpsTable];
    [_plcRenderedView addSubview:plcOpsScroll];

    _plcDetailTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 190.0)];
    [_plcDetailTable setDelegate:self];
    [_plcDetailTable setDataSource:self];
    [_plcDetailTable setAllowsEmptySelection:YES];
    [_plcDetailTable setAllowsMultipleSelection:NO];

    var plcDetailFieldColumn = [[CPTableColumn alloc] initWithIdentifier:@"plc_detail_field"];
    [[plcDetailFieldColumn headerView] setStringValue:@"Field"];
    [plcDetailFieldColumn setWidth:210.0];
    [_plcDetailTable addTableColumn:plcDetailFieldColumn];

    var plcDetailValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"plc_detail_value"];
    [[plcDetailValueColumn headerView] setStringValue:@"Value"];
    [plcDetailValueColumn setWidth:500.0];
    [_plcDetailTable addTableColumn:plcDetailValueColumn];
    [_plcDetailTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var plcDetailScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 268.0, 730.0, 190.0)];
    [plcDetailScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [plcDetailScroll setHasVerticalScroller:YES];
    [plcDetailScroll setAutohidesScrollers:YES];
    [plcDetailScroll setDocumentView:_plcDetailTable];
    [_plcRenderedView addSubview:plcDetailScroll];

    _plcTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)
                                                  inView:plcTab];
    [_plcTextView setHidden:YES];
    [self addTabItemWithLabel:@"PLC" contentView:plcTab];

    var collectionsTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [collectionsTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    _collectionsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 455.0)];
    [_collectionsTable setDelegate:self];
    [_collectionsTable setDataSource:self];
    [_collectionsTable setAllowsEmptySelection:YES];

    [_collectionsTable setAllowsMultipleSelection:NO];

    var collectionNameColumn = [[CPTableColumn alloc] initWithIdentifier:@"collection"];
    [[collectionNameColumn headerView] setStringValue:@"Collection"];
    [collectionNameColumn setWidth:580.0];
    [_collectionsTable addTableColumn:collectionNameColumn];

    var collectionCountColumn = [[CPTableColumn alloc] initWithIdentifier:@"count"];
    [[collectionCountColumn headerView] setStringValue:@"Count"];
    [collectionCountColumn setWidth:130.0];
    [_collectionsTable addTableColumn:collectionCountColumn];
    [_collectionsTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var collectionsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 10.0, 730.0, 455.0)];
    [collectionsScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [collectionsScroll setHasVerticalScroller:YES];
    [collectionsScroll setAutohidesScrollers:YES];
    [collectionsScroll setDocumentView:_collectionsTable];
    [collectionsTab addSubview:collectionsScroll];

    var loadCollectionButton = [[CPButton alloc] initWithFrame:CGRectMake(10.0, 474.0, 190.0, 28.0)];
    [loadCollectionButton setTitle:@"Load Selected Collection"];
    [loadCollectionButton setTarget:self];
    [loadCollectionButton setAction:@selector(handleLoadSelectedCollection:)];
    [collectionsTab addSubview:loadCollectionButton];
    [self addTabItemWithLabel:@"Collections" contentView:collectionsTab];

    var recordsTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [recordsTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    _recordsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 220.0)];
    [_recordsTable setDelegate:self];
    [_recordsTable setDataSource:self];
    [_recordsTable setAllowsEmptySelection:YES];
    [_recordsTable setAllowsMultipleSelection:NO];

    var recordsRKeyColumn = [[CPTableColumn alloc] initWithIdentifier:@"rkey"];
    [[recordsRKeyColumn headerView] setStringValue:@"RKey"];
    [recordsRKeyColumn setWidth:200.0];
    [_recordsTable addTableColumn:recordsRKeyColumn];

    var recordsCIDColumn = [[CPTableColumn alloc] initWithIdentifier:@"cid"];
    [[recordsCIDColumn headerView] setStringValue:@"CID"];
    [recordsCIDColumn setWidth:180.0];
    [_recordsTable addTableColumn:recordsCIDColumn];

    var recordsURIColumn = [[CPTableColumn alloc] initWithIdentifier:@"uri"];
    [[recordsURIColumn headerView] setStringValue:@"URI"];
    [recordsURIColumn setWidth:330.0];
    [_recordsTable addTableColumn:recordsURIColumn];
    [_recordsTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var recordsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 10.0, 730.0, 220.0)];
    [recordsScroll setAutoresizingMask:CPViewWidthSizable];
    [recordsScroll setHasVerticalScroller:YES];
    [recordsScroll setAutohidesScrollers:YES];
    [recordsScroll setDocumentView:_recordsTable];
    [recordsTab addSubview:recordsScroll];

    var modeLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 238.0, 70.0, 18.0)];
    [modeLabel setStringValue:@"Detail:"];
    [modeLabel setEditable:NO];
    [modeLabel setBezeled:NO];
    [modeLabel setDrawsBackground:NO];
    [recordsTab addSubview:modeLabel];

    _recordModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(82.0, 234.0, 120.0, 24.0)];
    [_recordModePopup addItemsWithTitles:[@"Rendered,JSON" componentsSeparatedByString:@","]];
    [_recordModePopup setTarget:self];
    [_recordModePopup setAction:@selector(handleRecordModeChanged:)];
    [recordsTab addSubview:_recordModePopup];

    _recordRenderedView = [[CPView alloc] initWithFrame:CGRectMake(10.0, 266.0, 730.0, 236.0)];
    [_recordRenderedView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [recordsTab addSubview:_recordRenderedView];

    _recordSummaryTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 124.0)];
    [_recordSummaryTable setDelegate:self];
    [_recordSummaryTable setDataSource:self];
    [_recordSummaryTable setAllowsEmptySelection:YES];
    [_recordSummaryTable setAllowsMultipleSelection:NO];

    var recordFieldColumn = [[CPTableColumn alloc] initWithIdentifier:@"record_field"];
    [[recordFieldColumn headerView] setStringValue:@"Field"];
    [recordFieldColumn setWidth:180.0];
    [_recordSummaryTable addTableColumn:recordFieldColumn];

    var recordValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"record_value"];
    [[recordValueColumn headerView] setStringValue:@"Value"];
    [recordValueColumn setWidth:540.0];
    [_recordSummaryTable addTableColumn:recordValueColumn];
    [_recordSummaryTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var recordSummaryScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 124.0)];
    [recordSummaryScroll setAutoresizingMask:CPViewWidthSizable];
    [recordSummaryScroll setHasVerticalScroller:YES];
    [recordSummaryScroll setAutohidesScrollers:YES];
    [recordSummaryScroll setDocumentView:_recordSummaryTable];
    [_recordRenderedView addSubview:recordSummaryScroll];

    var recordBodyLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, 132.0, 120.0, 18.0)];
    [recordBodyLabel setStringValue:@"Record Content"];
    [recordBodyLabel setEditable:NO];
    [recordBodyLabel setBezeled:NO];
    [recordBodyLabel setDrawsBackground:NO];
    [recordBodyLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [_recordRenderedView addSubview:recordBodyLabel];

    _recordBodyTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(0.0, 154.0, 730.0, 82.0)
                                                         inView:_recordRenderedView];

    _recordDetailTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 266.0, 730.0, 236.0)
                                                           inView:recordsTab];
    [_recordDetailTextView setHidden:YES];
    [self addTabItemWithLabel:@"Records" contentView:recordsTab];

    var feedTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [feedTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    _feedModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(10.0, 10.0, 180.0, 24.0)];
    [_feedModePopup addItemsWithTitles:[@"Posts,Likes,Reposts" componentsSeparatedByString:@","]];
    [feedTab addSubview:_feedModePopup];

    var loadFeedButton = [[CPButton alloc] initWithFrame:CGRectMake(198.0, 8.0, 80.0, 28.0)];
    [loadFeedButton setTitle:@"Load"];
    [loadFeedButton setTarget:self];
    [loadFeedButton setAction:@selector(handleLoadFeed:)];
    [feedTab addSubview:loadFeedButton];

    var feedViewLabel = [[CPTextField alloc] initWithFrame:CGRectMake(290.0, 12.0, 40.0, 18.0)];
    [feedViewLabel setStringValue:@"View:"];
    [feedViewLabel setEditable:NO];
    [feedViewLabel setBezeled:NO];
    [feedViewLabel setDrawsBackground:NO];
    [feedTab addSubview:feedViewLabel];

    _feedViewModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(330.0, 10.0, 120.0, 24.0)];
    [_feedViewModePopup addItemsWithTitles:[@"Rendered,JSON" componentsSeparatedByString:@","]];
    [_feedViewModePopup setTarget:self];
    [_feedViewModePopup setAction:@selector(handleFeedViewModeChanged:)];
    [feedTab addSubview:_feedViewModePopup];

    _feedRenderedView = [[CPView alloc] initWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)];
    [_feedRenderedView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [feedTab addSubview:_feedRenderedView];

    _feedTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 262.0)];
    [_feedTable setDelegate:self];
    [_feedTable setDataSource:self];
    [_feedTable setAllowsEmptySelection:YES];

    [_feedTable setAllowsMultipleSelection:NO];

    var feedTypeColumn = [[CPTableColumn alloc] initWithIdentifier:@"feed_type"];
    [[feedTypeColumn headerView] setStringValue:@"Type"];
    [feedTypeColumn setWidth:80.0];
    [_feedTable addTableColumn:feedTypeColumn];

    var feedActorColumn = [[CPTableColumn alloc] initWithIdentifier:@"feed_actor"];
    [[feedActorColumn headerView] setStringValue:@"Actor"];
    [feedActorColumn setWidth:170.0];
    [_feedTable addTableColumn:feedActorColumn];

    var feedPrimaryColumn = [[CPTableColumn alloc] initWithIdentifier:@"feed_primary"];
    [[feedPrimaryColumn headerView] setStringValue:@"Summary"];
    [feedPrimaryColumn setWidth:340.0];
    [_feedTable addTableColumn:feedPrimaryColumn];

    var feedCreatedColumn = [[CPTableColumn alloc] initWithIdentifier:@"feed_created"];
    [[feedCreatedColumn headerView] setStringValue:@"Created At"];
    [feedCreatedColumn setWidth:130.0];
    [_feedTable addTableColumn:feedCreatedColumn];
    [_feedTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var feedTableScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 262.0)];
    [feedTableScroll setAutoresizingMask:CPViewWidthSizable];
    [feedTableScroll setHasVerticalScroller:YES];
    [feedTableScroll setAutohidesScrollers:YES];
    [feedTableScroll setDocumentView:_feedTable];
    [_feedRenderedView addSubview:feedTableScroll];

    _feedDetailTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 186.0)];
    [_feedDetailTable setDelegate:self];
    [_feedDetailTable setDataSource:self];
    [_feedDetailTable setAllowsEmptySelection:YES];
    [_feedDetailTable setAllowsMultipleSelection:NO];

    var feedDetailFieldColumn = [[CPTableColumn alloc] initWithIdentifier:@"feed_detail_field"];
    [[feedDetailFieldColumn headerView] setStringValue:@"Field"];
    [feedDetailFieldColumn setWidth:160.0];
    [_feedDetailTable addTableColumn:feedDetailFieldColumn];

    var feedDetailValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"feed_detail_value"];
    [[feedDetailValueColumn headerView] setStringValue:@"Value"];
    [feedDetailValueColumn setWidth:550.0];
    [_feedDetailTable addTableColumn:feedDetailValueColumn];
    [_feedDetailTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var feedDetailScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 272.0, 730.0, 186.0)];
    [feedDetailScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [feedDetailScroll setHasVerticalScroller:YES];
    [feedDetailScroll setAutohidesScrollers:YES];
    [feedDetailScroll setDocumentView:_feedDetailTable];
    [_feedRenderedView addSubview:feedDetailScroll];

    _feedTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)
                                                   inView:feedTab];
    [_feedTextView setHidden:YES];
    [self addTabItemWithLabel:@"Feed" contentView:feedTab];

    var graphTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [graphTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    var loadGraphButton = [[CPButton alloc] initWithFrame:CGRectMake(10.0, 8.0, 180.0, 28.0)];
    [loadGraphButton setTitle:@"Load Graph Follows"];
    [loadGraphButton setTarget:self];
    [loadGraphButton setAction:@selector(handleLoadGraph:)];
    [graphTab addSubview:loadGraphButton];

    _graphTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 304.0)];
    [_graphTable setDelegate:self];
    [_graphTable setDataSource:self];
    [_graphTable setAllowsEmptySelection:YES];

    [_graphTable setAllowsMultipleSelection:NO];

    var graphHandleColumn = [[CPTableColumn alloc] initWithIdentifier:@"graph_handle"];
    [[graphHandleColumn headerView] setStringValue:@"Handle"];
    [graphHandleColumn setWidth:170.0];
    [_graphTable addTableColumn:graphHandleColumn];

    var graphDidColumn = [[CPTableColumn alloc] initWithIdentifier:@"graph_did"];
    [[graphDidColumn headerView] setStringValue:@"DID"];
    [graphDidColumn setWidth:320.0];
    [_graphTable addTableColumn:graphDidColumn];

    var graphDisplayNameColumn = [[CPTableColumn alloc] initWithIdentifier:@"graph_display_name"];
    [[graphDisplayNameColumn headerView] setStringValue:@"Display Name"];
    [graphDisplayNameColumn setWidth:130.0];
    [_graphTable addTableColumn:graphDisplayNameColumn];

    var graphCreatedColumn = [[CPTableColumn alloc] initWithIdentifier:@"graph_created"];
    [[graphCreatedColumn headerView] setStringValue:@"Created At"];
    [graphCreatedColumn setWidth:100.0];
    [_graphTable addTableColumn:graphCreatedColumn];
    [_graphTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var graphScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 44.0, 730.0, 304.0)];
    [graphScroll setAutoresizingMask:CPViewWidthSizable];
    [graphScroll setHasVerticalScroller:YES];
    [graphScroll setAutohidesScrollers:YES];
    [graphScroll setDocumentView:_graphTable];
    [graphTab addSubview:graphScroll];

    _graphDetailTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 146.0)];
    [_graphDetailTable setDelegate:self];
    [_graphDetailTable setDataSource:self];
    [_graphDetailTable setAllowsEmptySelection:YES];
    [_graphDetailTable setAllowsMultipleSelection:NO];

    var graphDetailFieldColumn = [[CPTableColumn alloc] initWithIdentifier:@"graph_detail_field"];
    [[graphDetailFieldColumn headerView] setStringValue:@"Field"];
    [graphDetailFieldColumn setWidth:170.0];
    [_graphDetailTable addTableColumn:graphDetailFieldColumn];

    var graphDetailValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"graph_detail_value"];
    [[graphDetailValueColumn headerView] setStringValue:@"Value"];
    [graphDetailValueColumn setWidth:540.0];
    [_graphDetailTable addTableColumn:graphDetailValueColumn];
    [_graphDetailTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var graphDetailScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 356.0, 730.0, 146.0)];
    [graphDetailScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [graphDetailScroll setHasVerticalScroller:YES];
    [graphDetailScroll setAutohidesScrollers:YES];
    [graphDetailScroll setDocumentView:_graphDetailTable];
    [graphTab addSubview:graphDetailScroll];
    [self addTabItemWithLabel:@"Graph" contentView:graphTab];

    var profileTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [profileTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    var loadProfileButton = [[CPButton alloc] initWithFrame:CGRectMake(10.0, 8.0, 150.0, 28.0)];
    [loadProfileButton setTitle:@"Load Profile"];
    [loadProfileButton setTarget:self];
    [loadProfileButton setAction:@selector(handleLoadProfile:)];
    [profileTab addSubview:loadProfileButton];

    var profileViewLabel = [[CPTextField alloc] initWithFrame:CGRectMake(172.0, 12.0, 40.0, 18.0)];
    [profileViewLabel setStringValue:@"View:"];
    [profileViewLabel setEditable:NO];
    [profileViewLabel setBezeled:NO];
    [profileViewLabel setDrawsBackground:NO];
    [profileTab addSubview:profileViewLabel];

    _profileViewModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(212.0, 10.0, 120.0, 24.0)];
    [_profileViewModePopup addItemsWithTitles:[@"Rendered,JSON" componentsSeparatedByString:@","]];
    [_profileViewModePopup setTarget:self];
    [_profileViewModePopup setAction:@selector(handleProfileViewModeChanged:)];
    [profileTab addSubview:_profileViewModePopup];

    _profileRenderedView = [[CPView alloc] initWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)];
    [_profileRenderedView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [profileTab addSubview:_profileRenderedView];

    _profileSummaryTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 218.0)];
    [_profileSummaryTable setDelegate:self];
    [_profileSummaryTable setDataSource:self];
    [_profileSummaryTable setAllowsEmptySelection:YES];

    [_profileSummaryTable setAllowsMultipleSelection:NO];

    var profileFieldColumn = [[CPTableColumn alloc] initWithIdentifier:@"profile_field"];
    [[profileFieldColumn headerView] setStringValue:@"Field"];
    [profileFieldColumn setWidth:200.0];
    [_profileSummaryTable addTableColumn:profileFieldColumn];

    var profileValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"profile_value"];
    [[profileValueColumn headerView] setStringValue:@"Value"];
    [profileValueColumn setWidth:510.0];
    [_profileSummaryTable addTableColumn:profileValueColumn];
    [_profileSummaryTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var profileSummaryScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 218.0)];
    [profileSummaryScroll setAutoresizingMask:CPViewWidthSizable];
    [profileSummaryScroll setHasVerticalScroller:YES];
    [profileSummaryScroll setAutohidesScrollers:YES];
    [profileSummaryScroll setDocumentView:_profileSummaryTable];
    [_profileRenderedView addSubview:profileSummaryScroll];

    var profileBioLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, 226.0, 120.0, 18.0)];
    [profileBioLabel setStringValue:@"Bio"];
    [profileBioLabel setEditable:NO];
    [profileBioLabel setBezeled:NO];
    [profileBioLabel setDrawsBackground:NO];
    [profileBioLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [_profileRenderedView addSubview:profileBioLabel];

    _profileBioTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(0.0, 250.0, 730.0, 208.0)
                                                         inView:_profileRenderedView];

    _profileTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)
                                                      inView:profileTab];
    [_profileTextView setHidden:YES];
    [self addTabItemWithLabel:@"Profile" contentView:profileTab];

    var mstTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [mstTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    var mstDidLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 30.0, 18.0)];
    [mstDidLabel setStringValue:@"DID:"];
    [mstDidLabel setEditable:NO];
    [mstDidLabel setBezeled:NO];
    [mstDidLabel setDrawsBackground:NO];
    [mstTab addSubview:mstDidLabel];

    _mstDidField = [[CPTextField alloc] initWithFrame:CGRectMake(42.0, 10.0, 280.0, 24.0)];
    [_mstDidField setPlaceholderString:@"did:plc:..."];

    [mstTab addSubview:_mstDidField];

    var loadMSTButton = [[CPButton alloc] initWithFrame:CGRectMake(330.0, 8.0, 80.0, 28.0)];
    [loadMSTButton setTitle:@"Load MST"];
    [loadMSTButton setTarget:self];
    [loadMSTButton setAction:@selector(handleLoadMST:)];

    [mstTab addSubview:loadMSTButton];

    var toggleMSTButton = [[CPButton alloc] initWithFrame:CGRectMake(418.0, 8.0, 95.0, 28.0)];
    [toggleMSTButton setTitle:@"Expand/Collapse"];
    [toggleMSTButton setTarget:self];
    [toggleMSTButton setAction:@selector(handleToggleMSTTree:)];

    [mstTab addSubview:toggleMSTButton];

    _mstExportFormatPopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(522.0, 10.0, 90.0, 24.0)];
    [_mstExportFormatPopup addItemsWithTitles:[@"JSON,DOT,SVG" componentsSeparatedByString:@","]];
    [mstTab addSubview:_mstExportFormatPopup];

    var exportMSTButton = [[CPButton alloc] initWithFrame:CGRectMake(620.0, 8.0, 80.0, 28.0)];
    [exportMSTButton setTitle:@"Export"];
    [exportMSTButton setTarget:self];
    [exportMSTButton setAction:@selector(handleExportMST:)];

    [mstTab addSubview:exportMSTButton];

    _mstStatsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 130.0)];
    [_mstStatsTable setDelegate:self];
    [_mstStatsTable setDataSource:self];
    [_mstStatsTable setAllowsEmptySelection:YES];

    [_mstStatsTable setAllowsMultipleSelection:NO];

    var mstMetricColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_metric"];
    [[mstMetricColumn headerView] setStringValue:@"Metric"];
    [mstMetricColumn setWidth:220.0];
    [_mstStatsTable addTableColumn:mstMetricColumn];

    var mstMetricValueColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_metric_value"];
    [[mstMetricValueColumn headerView] setStringValue:@"Value"];
    [mstMetricValueColumn setWidth:490.0];
    [_mstStatsTable addTableColumn:mstMetricValueColumn];
    [_mstStatsTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var mstStatsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(10.0, 44.0, 730.0, 130.0)];
    [mstStatsScroll setAutoresizingMask:CPViewWidthSizable];
    [mstStatsScroll setHasVerticalScroller:YES];
    [mstStatsScroll setAutohidesScrollers:YES];
    [mstStatsScroll setDocumentView:_mstStatsTable];
    [mstTab addSubview:mstStatsScroll];

    _mstTreeListView = [[CPView alloc] initWithFrame:CGRectMake(10.0, 182.0, 730.0, 320.0)];
    [_mstTreeListView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [mstTab addSubview:_mstTreeListView];

    _mstNodesTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 320.0)];
    [_mstNodesTable setDelegate:self];
    [_mstNodesTable setDataSource:self];
    [_mstNodesTable setAllowsEmptySelection:YES];
    [_mstNodesTable setAllowsMultipleSelection:NO];

    var mstNodeLevelColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_node_level"];
    [[mstNodeLevelColumn headerView] setStringValue:@"Level"];
    [mstNodeLevelColumn setWidth:60.0];
    [_mstNodesTable addTableColumn:mstNodeLevelColumn];

    var mstNodeKindColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_node_kind"];
    [[mstNodeKindColumn headerView] setStringValue:@"Kind"];
    [mstNodeKindColumn setWidth:90.0];
    [_mstNodesTable addTableColumn:mstNodeKindColumn];

    var mstNodeEntriesColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_node_entries"];
    [[mstNodeEntriesColumn headerView] setStringValue:@"Entries"];
    [mstNodeEntriesColumn setWidth:80.0];
    [_mstNodesTable addTableColumn:mstNodeEntriesColumn];

    var mstNodeLeftColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_node_left"];
    [[mstNodeLeftColumn headerView] setStringValue:@"Left"];
    [mstNodeLeftColumn setWidth:70.0];
    [_mstNodesTable addTableColumn:mstNodeLeftColumn];

    var mstNodeCidColumn = [[CPTableColumn alloc] initWithIdentifier:@"mst_node_cid"];
    [[mstNodeCidColumn headerView] setStringValue:@"CID"];
    [mstNodeCidColumn setWidth:410.0];
    [_mstNodesTable addTableColumn:mstNodeCidColumn];
    [_mstNodesTable setColumnAutoresizingStyle:CPTableViewLastColumnOnlyAutoresizingStyle];

    var mstNodesScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, 0.0, 730.0, 320.0)];
    [mstNodesScroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [mstNodesScroll setHasVerticalScroller:YES];
    [mstNodesScroll setAutohidesScrollers:YES];
    [mstNodesScroll setDocumentView:_mstNodesTable];
    [_mstTreeListView addSubview:mstNodesScroll];

    _mstTreeTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 182.0, 730.0, 320.0)
                                                      inView:mstTab];
    [_mstTreeTextView setHidden:YES];
    [self addTabItemWithLabel:@"MST Utility" contentView:mstTab];

    var utilitiesTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [utilitiesTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    _cidField = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 10.0, 320.0, 24.0)];
    [_cidField setPlaceholderString:@"CID"];
    [utilitiesTab addSubview:_cidField];

    var decodeButton = [[CPButton alloc] initWithFrame:CGRectMake(338.0, 8.0, 90.0, 28.0)];
    [decodeButton setTitle:@"Decode CID"];
    [decodeButton setTarget:self];
    [decodeButton setAction:@selector(handleCIDDecode:)];
    [utilitiesTab addSubview:decodeButton];

    var docsButton = [[CPButton alloc] initWithFrame:CGRectMake(436.0, 8.0, 100.0, 28.0)];
    [docsButton setTitle:@"Open Docs"];
    [docsButton setTarget:self];
    [docsButton setAction:@selector(handleOpenDocs:)];
    [utilitiesTab addSubview:docsButton];

    var plcExplorerButton = [[CPButton alloc] initWithFrame:CGRectMake(544.0, 8.0, 95.0, 28.0)];
    [plcExplorerButton setTitle:@"PLC Explorer"];
    [plcExplorerButton setTarget:self];
    [plcExplorerButton setAction:@selector(handleOpenPLCExplorer:)];
    [utilitiesTab addSubview:plcExplorerButton];

    var plcMetricsButton = [[CPButton alloc] initWithFrame:CGRectMake(647.0, 8.0, 85.0, 28.0)];
    [plcMetricsButton setTitle:@"PLC Metrics"];
    [plcMetricsButton setTarget:self];
    [plcMetricsButton setAction:@selector(handleOpenPLCMetrics:)];
    [utilitiesTab addSubview:plcMetricsButton];

    _utilityTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 44.0, 730.0, 458.0)
                                                      inView:utilitiesTab];
    [self addTabItemWithLabel:@"Utilities" contentView:utilitiesTab];

    var authTab = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 740.0, 520.0)];
    [authTab setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    var handleLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 12.0, 48.0, 18.0)];
    [handleLabel setStringValue:@"Handle:"];
    [handleLabel setEditable:NO];
    [handleLabel setBezeled:NO];
    [handleLabel setDrawsBackground:NO];
    [authTab addSubview:handleLabel];

    _oauthHandleField = [[CPTextField alloc] initWithFrame:CGRectMake(62.0, 10.0, 170.0, 24.0)];
    [_oauthHandleField setPlaceholderString:@"alice.example.com"];
    [authTab addSubview:_oauthHandleField];

    var resolveHandleButton = [[CPButton alloc] initWithFrame:CGRectMake(240.0, 8.0, 72.0, 28.0)];
    [resolveHandleButton setTitle:@"Resolve"];
    [resolveHandleButton setTarget:self];
    [resolveHandleButton setAction:@selector(handleResolveHandle:)];
    [authTab addSubview:resolveHandleButton];

    var loginButton = [[CPButton alloc] initWithFrame:CGRectMake(320.0, 8.0, 96.0, 28.0)];
    [loginButton setTitle:@"OAuth Login"];
    [loginButton setTarget:self];
    [loginButton setAction:@selector(handleStartOAuthLogin:)];
    [authTab addSubview:loginButton];

    var logoutButton = [[CPButton alloc] initWithFrame:CGRectMake(424.0, 8.0, 74.0, 28.0)];
    [logoutButton setTitle:@"Logout"];
    [logoutButton setTarget:self];
    [logoutButton setAction:@selector(handleLogoutOAuth:)];
    [authTab addSubview:logoutButton];

    var testSessionButton = [[CPButton alloc] initWithFrame:CGRectMake(506.0, 8.0, 92.0, 28.0)];
    [testSessionButton setTitle:@"Test Session"];
    [testSessionButton setTarget:self];
    [testSessionButton setAction:@selector(handleTestOAuthSession:)];
    [authTab addSubview:testSessionButton];

    var recentPostsButton = [[CPButton alloc] initWithFrame:CGRectMake(606.0, 8.0, 126.0, 28.0)];
    [recentPostsButton setTitle:@"Load Recent Posts"];
    [recentPostsButton setTarget:self];
    [recentPostsButton setAction:@selector(handleLoadRecentPosts:)];
    [authTab addSubview:recentPostsButton];

    var didLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 42.0, 28.0, 18.0)];
    [didLabel setStringValue:@"DID:"];
    [didLabel setEditable:NO];
    [didLabel setBezeled:NO];
    [didLabel setDrawsBackground:NO];
    [authTab addSubview:didLabel];

    _oauthDidField = [[CPTextField alloc] initWithFrame:CGRectMake(42.0, 40.0, 420.0, 24.0)];
    [_oauthDidField setEditable:NO];
    [_oauthDidField setBezeled:YES];
    [_oauthDidField setStringValue:@"(not authenticated)"];
    [authTab addSubview:_oauthDidField];

    var postLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 72.0, 32.0, 18.0)];
    [postLabel setStringValue:@"Post:"];
    [postLabel setEditable:NO];
    [postLabel setBezeled:NO];
    [postLabel setDrawsBackground:NO];
    [authTab addSubview:postLabel];

    _postTextField = [[CPTextField alloc] initWithFrame:CGRectMake(42.0, 70.0, 500.0, 24.0)];
    [_postTextField setPlaceholderString:@"Write a post (max 300 chars)"];
    [authTab addSubview:_postTextField];

    var createPostButton = [[CPButton alloc] initWithFrame:CGRectMake(550.0, 68.0, 90.0, 28.0)];
    [createPostButton setTitle:@"Create Post"];
    [createPostButton setTarget:self];
    [createPostButton setAction:@selector(handleCreatePost:)];
    [authTab addSubview:createPostButton];

    var replyLabel = [[CPTextField alloc] initWithFrame:CGRectMake(10.0, 102.0, 34.0, 18.0)];
    [replyLabel setStringValue:@"Reply:"];
    [replyLabel setEditable:NO];
    [replyLabel setBezeled:NO];
    [replyLabel setDrawsBackground:NO];
    [authTab addSubview:replyLabel];

    _postReplyField = [[CPTextField alloc] initWithFrame:CGRectMake(42.0, 100.0, 598.0, 24.0)];
    [_postReplyField setPlaceholderString:@"at://did:.../app.bsky.feed.post/... (optional)"];
    [authTab addSubview:_postReplyField];

    _authResultTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(10.0, 132.0, 730.0, 370.0)
                                                         inView:authTab];
    [self addTabItemWithLabel:@"Auth & Poster" contentView:authTab];
}

- (void)addTabItemWithLabel:(CPString)label contentView:(CPView)contentView
{
    var item = [[CPTabViewItem alloc] initWithIdentifier:label];
    [item setLabel:label];
    [item setView:contentView];
    [_detailsTabView addTabViewItem:item];
}

- (CPTextView)buildReadOnlyTextViewWithFrame:(CGRect)frame inView:(CPView)parent
{
    var scroll = [[CPScrollView alloc] initWithFrame:frame];
    [scroll setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];

    var textView = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, 0.0, frame.size.width - 20.0, frame.size.height)];
    [textView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [textView setEditable:NO];
    [textView setSelectable:YES];
    [textView setFont:[CPFont systemFontOfSize:12.0]];
    [scroll setDocumentView:textView];
    [parent addSubview:scroll];
    return textView;
}

- (void)setStatus:(CPString)message
{
    [_statusLabel setStringValue:(message || @"")];
    [_statusLabel setTextColor:[CPColor colorWithCalibratedWhite:(75.0/255.0) alpha:1.0]];
}

- (void)setErrorStatus:(CPString)message
{
    [_statusLabel setStringValue:@"Error: " + message];
    // #B91C1C = WCAG AA compliant red
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(185.0/255.0)
                                                         green:(28.0/255.0)
                                                          blue:(28.0/255.0)
                                                         alpha:1.0]];
}

- (void)setSuccessStatus:(CPString)message
{
    [_statusLabel setStringValue:message];
    // #047857 = WCAG AA compliant green
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(4.0/255.0)
                                                         green:(120.0/255.0)
                                                          blue:(87.0/255.0)
                                                         alpha:1.0]];
}

- (void)setWarningStatus:(CPString)message
{
    [_statusLabel setStringValue:@"Warning: " + message];
    // #B45309 = WCAG AA compliant orange
    [_statusLabel setTextColor:[CPColor colorWithCalibratedRed:(180.0/255.0)
                                                         green:(83.0/255.0)
                                                          blue:(9.0/255.0)
                                                         alpha:1.0]];
}

- (void)setLoadingStatus:(CPString)message
{
    [self setStatus:message];
    [self showLoadingSpinner];
}

- (void)showLoadingSpinner
{
    if (!_loadingSpinner)
    {
        _loadingSpinner = [LoadingSpinner smallSpinner];
        [_loadingSpinner setColor:@"gray"];
    }

    if (_statusLabel && _loadingSpinner)
    {
        var statusFrame = [_statusLabel frame];
        var superview = [_statusLabel superview];
        if (superview)
        {
            [_loadingSpinner removeFromSuperview];
            [_loadingSpinner setFrameOrigin:CGPointMake(
                statusFrame.origin.x + statusFrame.size.width + 6.0,
                statusFrame.origin.y + (statusFrame.size.height - 16.0) / 2.0
            )];
            [superview addSubview:_loadingSpinner];
            [_loadingSpinner startAnimating];
        }
    }
}

- (void)hideLoadingSpinner
{
    if (_loadingSpinner)
    {
        [_loadingSpinner stopAnimating];
        [_loadingSpinner removeFromSuperview];
    }
}

- (void)clearLoadingSpinner
{
    [self hideLoadingSpinner];
}

- (void)setTextView:(CPTextView)textView content:(CPString)content
{
    if (!textView)
        return;

    [textView setString:(content || @"")];
}

- (CPString)trimmedString:(CPString)value
{
    if (!value)
        return @"";

    return [value stringByTrimmingCharactersInSet:[CPCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (CPString)safeString:(id)value
{
    if (value === nil || value === undefined || value === [CPNull null])
        return @"";

    return String(value);
}

- (CPString)abbreviatedString:(id)value maxLength:(int)maxLength
{
    var stringValue = [self safeString:value];
    if (!stringValue || [stringValue length] <= maxLength || maxLength < 4)
        return stringValue;

    return [[stringValue substringToIndex:(maxLength - 3)] stringByAppendingString:@"..."];
}

- (CPString)prettyJSON:(id)object
{
    if (object === nil || object === undefined)
        return @"";

    if (typeof object === "string")
        return object;

    try
    {
        return JSON.stringify(object, null, 2);
    }
    catch (e)
    {
        return String(object);
    }
}

- (id)fieldValueRowWithField:(CPString)field value:(id)value
{
    return {
        field: [self safeString:field],
        value: [self safeString:value]
    };
}

- (CPString)singleLineSummary:(id)value maxLength:(int)maxLength
{
    var normalized = [self safeString:value];
    if (!normalized.length)
        return @"";

    normalized = normalized.replace(/\s+/g, " ");
    return [self abbreviatedString:normalized maxLength:maxLength];
}

- (CPArray)pathComponentsForATURI:(CPString)uri
{
    var raw = [self safeString:uri];
    if (!raw.length)
        return [];

    if (raw.indexOf("at://") === 0)
        raw = raw.substring(5);

    return raw.split("/");
}

- (CPString)collectionFromRecordURI:(CPString)uri
{
    var parts = [self pathComponentsForATURI:uri];
    if (!parts || parts.length < 2)
        return @"";
    return [self safeString:parts[1]];
}

- (CPString)rkeyFromRecordURI:(CPString)uri
{
    var parts = [self pathComponentsForATURI:uri];
    if (!parts || parts.length < 3)
        return @"";
    return [self safeString:parts[2]];
}

- (CPString)stableJSONString:(id)object
{
    if (object === nil || object === undefined)
        return @"";

    try
    {
        return JSON.stringify(object);
    }
    catch (e)
    {
        return [self safeString:object];
    }
}

- (CPArray)sortedKeysForObject:(id)object
{
    var keys = [];
    if (!object)
        return keys;

    for (var key in object)
    {
        if (object.hasOwnProperty && !object.hasOwnProperty(key))
            continue;
        keys.push(key);
    }
    keys.sort();
    return keys;
}

- (CPArray)normalizedArrayValue:(id)value
{
    if (value === nil || value === undefined)
        return [];
    if (value instanceof Array)
        return value;
    return [value];
}

- (CPArray)didSummaryRowsFromPayload:(id)didPayload
{
    var rows = [];
    if (!didPayload)
        return rows;

    if (didPayload.error)
    {
        rows.push([self fieldValueRowWithField:@"Error" value:didPayload.error]);
        return rows;
    }

    var aliases = [self normalizedArrayValue:didPayload.alsoKnownAs],
        services = [self normalizedArrayValue:didPayload.service],
        verificationMethods = [self normalizedArrayValue:didPayload.verificationMethod],
        primaryAlias = aliases.length ? [self safeString:aliases[0]] : @"",
        handle = primaryAlias.replace(/^at:\/\//, "");

    rows.push([self fieldValueRowWithField:@"DID" value:(didPayload.id || @"")]);
    rows.push([self fieldValueRowWithField:@"Primary Handle" value:handle]);
    rows.push([self fieldValueRowWithField:@"Alias Count" value:aliases.length]);
    rows.push([self fieldValueRowWithField:@"Service Count" value:services.length]);
    rows.push([self fieldValueRowWithField:@"Verification Methods" value:verificationMethods.length]);
    return rows;
}

- (CPArray)didItemRowsFromPayload:(id)didPayload
{
    var rows = [];
    if (!didPayload)
        return rows;

    if (didPayload.error)
    {
        rows.push({type: @"Error", label: @"Message", value: didPayload.error});
        return rows;
    }

    var aliases = [self normalizedArrayValue:didPayload.alsoKnownAs];
    for (var i = 0; i < aliases.length; i++)
        rows.push({type: @"Alias", label: ("#" + (i + 1)), value: [self safeString:aliases[i]]});

    var services = [self normalizedArrayValue:didPayload.service];
    for (var j = 0; j < services.length; j++)
    {
        var service = services[j] || {},
            label = [self safeString:service.id || ("#" + (j + 1))];
        if (service.type)
            label = label + " (" + service.type + ")";
        rows.push({type: @"Service", label: label, value: [self safeString:(service.serviceEndpoint || @"")]});
    }

    var verificationMethods = [self normalizedArrayValue:didPayload.verificationMethod];
    for (var k = 0; k < verificationMethods.length; k++)
    {
        var method = verificationMethods[k] || {},
            methodLabel = [self safeString:method.id || ("#" + (k + 1))],
            methodValue = method.publicKeyMultibase || method.publicKeyBase58 || method.controller || @"";
        rows.push({type: @"Verification", label: methodLabel, value: [self safeString:methodValue]});
    }

    var contextEntries = [self normalizedArrayValue:didPayload["@context"]];
    for (var c = 0; c < contextEntries.length; c++)
        rows.push({type: @"Context", label: ("#" + (c + 1)), value: [self safeString:contextEntries[c]]});

    if (!rows.length)
        rows.push({type: @"Info", label: @"Details", value: @"No DID detail entries returned."});
    return rows;
}

- (void)refreshDIDView
{
    var mode = [_didViewModePopup titleOfSelectedItem],
        showJSON = (mode && [mode isEqual:@"JSON"]);

    [_didRenderedView setHidden:showJSON];
    [_didTextView setHidden:!showJSON];

    if (showJSON)
    {
        [self setTextView:_didTextView content:(_currentDIDPayload ? [self prettyJSON:_currentDIDPayload] : @"")];
        return;
    }

    if (!_currentDIDPayload)
    {
        _didSummaryRows = [];
        _didItemRows = [];
        [_didSummaryTable reloadData];
        [_didItemsTable reloadData];
        return;
    }

    _didSummaryRows = [self didSummaryRowsFromPayload:_currentDIDPayload];
    _didItemRows = [self didItemRowsFromPayload:_currentDIDPayload];
    [_didSummaryTable reloadData];
    [_didItemsTable reloadData];
}

- (CPArray)normalizedPLCOpsFromPayload:(id)plcPayload
{
    if (!plcPayload)
        return [];

    if (plcPayload instanceof Array)
        return plcPayload;
    if (plcPayload.operations instanceof Array)
        return plcPayload.operations;
    if (plcPayload.log instanceof Array)
        return plcPayload.log;
    if (plcPayload.history instanceof Array)
        return plcPayload.history;
    return [];
}

- (CPArray)plcChangeLinesForOperation:(id)operation previous:(id)previous
{
    var lines = [];
    if (!operation)
        return lines;

    if (!previous)
    {
        lines.push(@"Identity created");
        return lines;
    }

    if ([self stableJSONString:(operation.alsoKnownAs || [])] !== [self stableJSONString:(previous.alsoKnownAs || [])])
        lines.push(@"Alias updated");
    if ([self stableJSONString:(operation.services || {})] !== [self stableJSONString:(previous.services || {})])
        lines.push(@"Service updated");
    if ([self stableJSONString:(operation.verificationMethods || {})] !== [self stableJSONString:(previous.verificationMethods || {})])
        lines.push(@"Verification method updated");

    var currentRotation = operation.rotationKeys || [],
        previousRotation = previous.rotationKeys || [],
        addedCount = 0,
        removedCount = 0;

    for (var i = 0; i < currentRotation.length; i++)
    {
        if (previousRotation.indexOf(currentRotation[i]) < 0)
            addedCount += 1;
    }
    for (var j = 0; j < previousRotation.length; j++)
    {
        if (currentRotation.indexOf(previousRotation[j]) < 0)
            removedCount += 1;
    }

    if (addedCount > 0)
        lines.push("Rotation keys added (" + addedCount + ")");
    if (removedCount > 0)
        lines.push("Rotation keys removed (" + removedCount + ")");

    if (!lines.length)
        lines.push(@"PLC operation updated");
    return lines;
}

- (CPArray)plcDetailRowsForOperation:(id)operation changeLines:(CPArray)changeLines
{
    var rows = [];
    if (!operation)
        return rows;

    rows.push([self fieldValueRowWithField:@"Operation Type" value:(operation.type || @"plc_operation")]);
    rows.push([self fieldValueRowWithField:@"Prev CID" value:(operation.prev || @"(none)")]);
    rows.push([self fieldValueRowWithField:@"Signature" value:[self abbreviatedString:(operation.sig || @"") maxLength:56]]);

    for (var i = 0; i < changeLines.length; i++)
        rows.push([self fieldValueRowWithField:("Change " + (i + 1)) value:changeLines[i]]);

    var aliases = operation.alsoKnownAs || [];
    for (var a = 0; a < aliases.length; a++)
        rows.push([self fieldValueRowWithField:("Alias " + (a + 1)) value:aliases[a]]);

    var serviceKeys = [self sortedKeysForObject:(operation.services || {})];
    for (var s = 0; s < serviceKeys.length; s++)
    {
        var serviceKey = serviceKeys[s],
            service = (operation.services || {})[serviceKey] || {},
            serviceValue = [self safeString:service.endpoint || @""];
        if (service.type)
            serviceValue = service.type + " @ " + serviceValue;
        rows.push([self fieldValueRowWithField:("Service " + serviceKey) value:serviceValue]);
    }

    var verificationKeys = [self sortedKeysForObject:(operation.verificationMethods || {})];
    for (var v = 0; v < verificationKeys.length; v++)
    {
        var verificationKey = verificationKeys[v],
            verificationValue = (operation.verificationMethods || {})[verificationKey];
        rows.push([self fieldValueRowWithField:("Verification " + verificationKey) value:verificationValue]);
    }

    var rotationKeys = operation.rotationKeys || [];
    for (var r = 0; r < rotationKeys.length; r++)
        rows.push([self fieldValueRowWithField:("Rotation Key " + (r + 1)) value:rotationKeys[r]]);

    return rows;
}

- (CPArray)plcOperationRowsFromPayload:(id)plcPayload
{
    var rows = [];
    if (!plcPayload)
        return rows;

    if (plcPayload.error)
    {
        var errorRows = [];
        errorRows.push([self fieldValueRowWithField:@"Error" value:plcPayload.error]);
        rows.push({
            when: @"",
            summary: @"Error",
            details: [self safeString:plcPayload.error],
            detailRows: errorRows
        });
        return rows;
    }

    var operations = [self normalizedPLCOpsFromPayload:plcPayload];
    if (!operations || !operations.length)
    {
        var infoRows = [];
        infoRows.push([self fieldValueRowWithField:@"Info" value:@"No PLC operations returned."]);
        rows.push({
            when: @"",
            summary: @"No operations",
            details: @"No PLC operations returned.",
            detailRows: infoRows
        });
        return rows;
    }

    for (var i = 0; i < operations.length; i++)
    {
        var operation = operations[i] || {},
            previous = (i + 1 < operations.length) ? operations[i + 1] : nil,
            when = operation.createdAt || operation.created_at || operation.signedAt || operation.updatedAt || ("Entry " + (i + 1)),
            changeLines = [self plcChangeLinesForOperation:operation previous:previous];

        rows.push({
            when: [self safeString:when],
            summary: [self safeString:(changeLines.length ? changeLines[0] : @"PLC operation")],
            details: [self singleLineSummary:changeLines.join(" • ") maxLength:180],
            detailRows: [self plcDetailRowsForOperation:operation changeLines:changeLines]
        });
    }

    return rows;
}

- (void)refreshPLCSelectionDetail
{
    var selectedRow = _plcOpsTable ? [_plcOpsTable selectedRow] : -1;
    if (selectedRow < 0 || selectedRow >= _plcOpRows.length)
    {
        _plcDetailRows = [];
        [_plcDetailTable reloadData];
        return;
    }

    var selected = _plcOpRows[selectedRow] || {};
    _plcDetailRows = selected.detailRows || [];
    [_plcDetailTable reloadData];
}

- (void)refreshPLCView
{
    var mode = [_plcViewModePopup titleOfSelectedItem],
        showJSON = (mode && [mode isEqual:@"JSON"]);

    [_plcRenderedView setHidden:showJSON];
    [_plcTextView setHidden:!showJSON];

    if (showJSON)
    {
        [self setTextView:_plcTextView content:(_currentPLCPayload ? [self prettyJSON:_currentPLCPayload] : @"")];
        return;
    }

    if (!_currentPLCPayload)
    {
        _plcOpRows = [];
        _plcDetailRows = [];
        [_plcOpsTable reloadData];
        [_plcDetailTable reloadData];
        return;
    }

    _plcOpRows = [self plcOperationRowsFromPayload:_currentPLCPayload];
    [_plcOpsTable reloadData];

    if (_plcOpRows.length > 0)
    {
        var selectedRow = [_plcOpsTable selectedRow];
        if (selectedRow < 0 || selectedRow >= _plcOpRows.length)
            [_plcOpsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self refreshPLCSelectionDetail];
}

- (CPString)oauthStorageKeyState
{
    return @"objj_poster_oauth_state";
}

- (CPString)oauthStorageKeyVerifier
{
    return @"objj_poster_oauth_code_verifier";
}

- (CPString)oauthStorageKeyAccessToken
{
    return @"objj_poster_access_token";
}

- (CPString)oauthStorageKeySessionDid
{
    return @"objj_poster_session_did";
}

- (CPString)oauthStorageKeyDPoPNonce
{
    return @"objj_poster_dpop_nonce";
}

- (void)setSessionStorageValue:(CPString)value forKey:(CPString)key
{
    if (!(window && window.sessionStorage && key))
        return;

    if (value === nil || value === undefined)
        window.sessionStorage.removeItem(String(key));
    else
        window.sessionStorage.setItem(String(key), String(value));
}

- (CPString)sessionStorageValueForKey:(CPString)key
{
    if (!(window && window.sessionStorage && key))
        return nil;
    return window.sessionStorage.getItem(String(key));
}

- (void)appendAuthResult:(CPString)line
{
    if (!_authResultTextView)
        return;

    var existing = [_authResultTextView string] || @"",
        next = existing && existing.length ? (existing + "\n" + line) : line;
    [self setTextView:_authResultTextView content:next];
}

- (void)setAuthSessionDid:(CPString)did
{
    _oauthSessionDid = did || nil;
    if (_oauthDidField)
    {
        if (_oauthSessionDid && _oauthSessionDid.length)
            [_oauthDidField setStringValue:_oauthSessionDid];
        else
            [_oauthDidField setStringValue:@"(not authenticated)"];
    }
}

- (void)restoreAuthSessionFromStorage
{
    _oauthAccessToken = [self sessionStorageValueForKey:[self oauthStorageKeyAccessToken]];
    [self setAuthSessionDid:[self sessionStorageValueForKey:[self oauthStorageKeySessionDid]]];
}

- (CPString)oauthIssuer
{
    if (window && window.location && window.location.origin)
        return String(window.location.origin);
    return @"";
}

- (CPString)oauthClientID
{
    return @"test-client";
}

- (CPString)oauthRedirectURI
{
    return [self oauthIssuer] + @"/ui/callback?oauth_callback=1";
}

- (CPString)randomOAuthStringWithLength:(int)length
{
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
        out = "";

    if (window && window.crypto && window.Uint32Array && window.crypto.getRandomValues)
    {
        var values = new Uint32Array(length);
        window.crypto.getRandomValues(values);
        for (var i = 0; i < length; i++)
            out += chars.charAt(values[i] % chars.length);
        return out;
    }

    for (var j = 0; j < length; j++)
        out += chars.charAt(Math.floor(Math.random() * chars.length));
    return out;
}

- (CPString)base64URLEncodeBytes:(id)bytesBuffer
{
    if (!(window && window.btoa))
        return @"";

    var bytes = new Uint8Array(bytesBuffer),
        binary = "";

    for (var i = 0; i < bytes.length; i++)
        binary += String.fromCharCode(bytes[i]);

    return window.btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

- (CPString)base64URLEncodeString:(CPString)stringValue
{
    if (!(window && window.TextEncoder))
        return @"";

    var encoder = new TextEncoder(),
        encoded = encoder.encode(String(stringValue || @""));
    return [self base64URLEncodeBytes:encoded];
}

- (void)sha256ForString:(CPString)value completion:(Function)completion
{
    if (!(window && window.crypto && window.crypto.subtle && window.TextEncoder))
    {
        completion(nil, @"WebCrypto unavailable");
        return;
    }

    var encoder = new TextEncoder(),
        encoded = encoder.encode(String(value || @""));

    window.crypto.subtle.digest("SHA-256", encoded)
        .then(function(hashBuffer)
    {
        completion(hashBuffer, nil);
    })
        .catch(function(error)
    {
        completion(nil, (error && error.message) ? error.message : @"SHA-256 failed");
    });
}

- (void)getOrCreateDPoPKeyWithCompletion:(Function)completion
{
    if (_dpopKeyPair)
    {
        completion(_dpopKeyPair, nil);
        return;
    }

    if (!(window && window.crypto && window.crypto.subtle))
    {
        completion(nil, @"WebCrypto unavailable");
        return;
    }

    window.crypto.subtle.generateKey({name: "ECDSA", namedCurve: "P-256"}, YES, ["sign"])
        .then(function(keyPair)
    {
        _dpopKeyPair = keyPair;
        completion(keyPair, nil);
    })
        .catch(function(error)
    {
        completion(nil, (error && error.message) ? error.message : @"Failed to create DPoP key");
    });
}

- (CPString)normalizedDPoPHTU:(CPString)urlString
{
    try
    {
        var u = new URL(String(urlString));
        return u.origin + u.pathname;
    }
    catch (e)
    {
        return urlString;
    }
}

- (void)makeDPoPProofWithKeyPair:(id)keyPair
                          method:(CPString)method
                             url:(CPString)url
                           nonce:(CPString)nonce
                     accessToken:(CPString)accessToken
                      completion:(Function)completion
{
    if (!(window && window.crypto && window.crypto.subtle && window.TextEncoder))
    {
        completion(nil, @"WebCrypto unavailable");
        return;
    }

    var httpMethod = String(method || @"GET"),
        htu = [self normalizedDPoPHTU:url];

    window.crypto.subtle.exportKey("jwk", keyPair.publicKey).then(function(jwk)
    {
        var header = {
                typ: "dpop+jwt",
                alg: "ES256",
                jwk: jwk
            },
            payload = {
                jti: [self randomOAuthStringWithLength:16],
                htm: httpMethod.toUpperCase(),
                htu: htu,
                iat: Math.floor(Date.now() / 1000)
            },
            finalize = function(ath)
            {
                if (nonce && nonce.length)
                    payload.nonce = nonce;
                if (ath && ath.length)
                    payload.ath = ath;

                var unsignedToken = [self base64URLEncodeString:JSON.stringify(header)] + "." + [self base64URLEncodeString:JSON.stringify(payload)];
                var signEncoder = new TextEncoder(),
                    unsignedBytes = signEncoder.encode(unsignedToken);
                window.crypto.subtle.sign({name: "ECDSA", hash: {name: "SHA-256"}},
                                          keyPair.privateKey,
                                          unsignedBytes)
                    .then(function(signature)
                {
                    completion(unsignedToken + "." + [self base64URLEncodeBytes:signature], nil);
                })
                    .catch(function(signError)
                {
                    completion(nil, (signError && signError.message) ? signError.message : @"DPoP signing failed");
                });
            };

        if (accessToken && accessToken.length)
        {
            [self sha256ForString:accessToken completion:function(hashBuffer, hashError)
            {
                if (hashError)
                {
                    completion(nil, hashError);
                    return;
                }
                finalize([self base64URLEncodeBytes:hashBuffer]);
            }];
        }
        else
        {
            finalize(nil);
        }
    }).catch(function(exportError)
    {
        completion(nil, (exportError && exportError.message) ? exportError.message : @"DPoP key export failed");
    });
}

- (id)parsedJSONFromResponseText:(CPString)text
{
    if (!text || !text.length)
        return {};

    try
    {
        return JSON.parse(text);
    }
    catch (e)
    {
        return {rawText: text};
    }
}

- (void)dpopFetchJSONWithURL:(CPString)url
                      method:(CPString)method
                     headers:(id)headers
                        body:(id)body
                 accessToken:(CPString)accessToken
                  completion:(Function)completion
{
    if (!(window && window.fetch))
    {
        completion(0, nil, @"Fetch unavailable");
        return;
    }

    [self getOrCreateDPoPKeyWithCompletion:function(keyPair, keyError)
    {
        if (keyError)
        {
            completion(0, nil, keyError);
            return;
        }

        var executeAttempt = function(allowRetry)
        {
            var nonce = [self sessionStorageValueForKey:[self oauthStorageKeyDPoPNonce]];
            [self makeDPoPProofWithKeyPair:keyPair
                                    method:method
                                       url:url
                                     nonce:nonce
                               accessToken:accessToken
                                completion:function(proof, proofError)
            {
                if (proofError)
                {
                    completion(0, nil, proofError);
                    return;
                }

                var fetchHeaders = {};
                if (headers)
                {
                    for (var key in headers)
                    {
                        if (headers.hasOwnProperty(key))
                            fetchHeaders[key] = headers[key];
                    }
                }
                fetchHeaders.DPoP = proof;

                var options = {method: String(method || @"GET"), headers: fetchHeaders};
                if (body !== nil && body !== undefined)
                    options.body = body;

                window.fetch(String(url), options).then(function(response)
                {
                    var responseNonce = response.headers ? response.headers.get("DPoP-Nonce") : nil;
                    if (responseNonce)
                        [self setSessionStorageValue:responseNonce forKey:[self oauthStorageKeyDPoPNonce]];

                    response.text().then(function(responseText)
                    {
                        var payload = [self parsedJSONFromResponseText:responseText];

                        if ((response.status === 400 || response.status === 401) && responseNonce && allowRetry)
                        {
                            executeAttempt(NO);
                            return;
                        }

                        var errorMessage = nil;
                        if (!response.ok)
                            errorMessage = (payload && (payload.error_description || payload.error || payload.message)) || ("HTTP " + response.status);

                        completion(response.status, payload, errorMessage);
                    }).catch(function()
                    {
                        completion(response.status, nil, @"Failed reading response body");
                    });
                }).catch(function(fetchError)
                {
                    completion(0, nil, (fetchError && fetchError.message) ? fetchError.message : @"Network error");
                });
            }];
        };

        executeAttempt(YES);
    }];
}

- (void)syncOAuthSessionStateToUI
{
    [self setAuthSessionDid:_oauthSessionDid];
    if (_oauthSessionDid && _oauthSessionDid.length)
    {
        [_sessionState setCurrentDID:_oauthSessionDid];
        if (_oauthDidField)
            [_oauthDidField setStringValue:_oauthSessionDid];
    }
}

- (void)handleOAuthCallbackIfPresent
{
    if (!(window && window.location && window.URLSearchParams))
        return;

    var search = String(window.location.search || @""),
        params = new URLSearchParams(search),
        code = params.get("code"),
        state = params.get("state"),
        callbackFlag = params.get("oauth_callback"),
        pathname = String(window.location.pathname || @"");

    var isExploreCallback = (pathname.indexOf("/ui/callback") >= 0) || (callbackFlag === "1");
    if (!isExploreCallback)
        return;

    var savedState = [self sessionStorageValueForKey:[self oauthStorageKeyState]],
        verifier = [self sessionStorageValueForKey:[self oauthStorageKeyVerifier]];

    if (!code || !state || !savedState || state !== savedState)
    {
        [self appendAuthResult:@"OAuth callback failed: state mismatch or missing code."];
        [self setStatus:@"OAuth callback validation failed."];
        return;
    }

    var tokenURL = [self oauthIssuer] + @"/oauth/token",
        formBody = new URLSearchParams();
    formBody.set("grant_type", "authorization_code");
    formBody.set("code", code);
    formBody.set("redirect_uri", [self oauthRedirectURI]);
    formBody.set("client_id", [self oauthClientID]);
    formBody.set("code_verifier", verifier || @"");

    [self appendAuthResult:@"Exchanging OAuth callback code for token..."];
    [self dpopFetchJSONWithURL:tokenURL
                        method:@"POST"
                       headers:{"Content-Type": "application/x-www-form-urlencoded"}
                          body:formBody
                   accessToken:nil
                    completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage || !payload || !payload.access_token)
        {
            [self appendAuthResult:("Token exchange failed: " + (errorMessage || @"missing access_token"))];
            [self setStatus:@"OAuth token exchange failed."];
            return;
        }

        _oauthAccessToken = payload.access_token;
        _oauthSessionDid = payload.sub || _oauthSessionDid;
        [self setSessionStorageValue:_oauthAccessToken forKey:[self oauthStorageKeyAccessToken]];
        if (_oauthSessionDid && _oauthSessionDid.length)
            [self setSessionStorageValue:_oauthSessionDid forKey:[self oauthStorageKeySessionDid]];

        [self setSessionStorageValue:nil forKey:[self oauthStorageKeyState]];
        [self setSessionStorageValue:nil forKey:[self oauthStorageKeyVerifier]];
        [self syncOAuthSessionStateToUI];
        [self appendAuthResult:("OAuth login complete for " + (_oauthSessionDid || @"(unknown DID)") + ".")];
        [self setStatus:@"OAuth session established."];

        if (window && window.history && window.history.replaceState)
            window.history.replaceState({}, "", "/ui");
    }];
}

- (void)startOAuthLoginWithHandle:(CPString)handle
{
    if (!(window && window.location))
    {
        [self appendAuthResult:@"OAuth start failed: window.location unavailable."];
        return;
    }

    var state = [self randomOAuthStringWithLength:32],
        verifier = [self randomOAuthStringWithLength:64];

    [self sha256ForString:verifier completion:function(hashBuffer, hashError)
    {
        if (hashError)
        {
            [self appendAuthResult:("OAuth start failed: " + hashError)];
            [self setStatus:@"OAuth start failed."];
            return;
        }

        var challenge = [self base64URLEncodeBytes:hashBuffer],
            authURL = new URL("/oauth/authorize", [self oauthIssuer]);

        [self setSessionStorageValue:state forKey:[self oauthStorageKeyState]];
        [self setSessionStorageValue:verifier forKey:[self oauthStorageKeyVerifier]];

        authURL.searchParams.set("client_id", [self oauthClientID]);
        authURL.searchParams.set("redirect_uri", [self oauthRedirectURI]);
        authURL.searchParams.set("response_type", "code");
        authURL.searchParams.set("scope", "atproto");
        authURL.searchParams.set("state", state);
        authURL.searchParams.set("code_challenge", challenge);
        authURL.searchParams.set("code_challenge_method", "S256");
        if (handle && handle.length)
            authURL.searchParams.set("login_hint", handle);

        [self appendAuthResult:("Starting OAuth login" + (handle && handle.length ? (" for " + handle) : @"") + "...")];
        [self setStatus:@"Redirecting to OAuth authorize..."];
        window.location.href = authURL.href;
    }];
}

- (void)logoutOAuthSession
{
    _oauthAccessToken = nil;
    _oauthSessionDid = nil;
    _dpopKeyPair = nil;

    [self setSessionStorageValue:nil forKey:[self oauthStorageKeyAccessToken]];
    [self setSessionStorageValue:nil forKey:[self oauthStorageKeySessionDid]];
    [self setSessionStorageValue:nil forKey:[self oauthStorageKeyState]];
    [self setSessionStorageValue:nil forKey:[self oauthStorageKeyVerifier]];
    [self setSessionStorageValue:nil forKey:[self oauthStorageKeyDPoPNonce]];
    [self syncOAuthSessionStateToUI];
    [self appendAuthResult:@"OAuth session cleared."];
    [self setStatus:@"Logged out."];
}

- (void)resolveOAuthHandle:(CPString)handle
{
    var trimmedHandle = [self trimmedString:handle];
    if (!trimmedHandle || !trimmedHandle.length || trimmedHandle.indexOf(".") < 0)
    {
        [self appendAuthResult:@"Handle resolution skipped (invalid handle format)."];
        return;
    }

    [self appendAuthResult:("Resolving handle " + trimmedHandle + "...")];
    [_apiClient getJSONWithPath:@"/com.atproto.identity.resolveHandle"
                  endpointGroup:@"xrpc"
                    queryParams:{handle: trimmedHandle}
                     completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage || !payload || !payload.did)
        {
            [self appendAuthResult:("Handle resolve failed: " + (errorMessage || @"no DID returned"))];
            return;
        }

        [self appendAuthResult:("Handle resolved to " + payload.did)];
    }];
}

- (void)testOAuthSession
{
    _oauthAccessToken = _oauthAccessToken || [self sessionStorageValueForKey:[self oauthStorageKeyAccessToken]];
    if (!_oauthAccessToken || !_oauthAccessToken.length)
    {
        [self appendAuthResult:@"No OAuth access token present. Login first."];
        [self setStatus:@"Session test failed."];
        return;
    }

    var sessionURL = [self oauthIssuer] + @"/xrpc/com.atproto.server.getSession";
    [self appendAuthResult:@"Calling com.atproto.server.getSession..."];
    [self dpopFetchJSONWithURL:sessionURL
                        method:@"GET"
                       headers:{Authorization: ("DPoP " + _oauthAccessToken)}
                          body:nil
                   accessToken:_oauthAccessToken
                    completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage)
        {
            [self appendAuthResult:("Session test failed: " + errorMessage)];
            [self setStatus:@"Session test failed."];
            return;
        }

        if (payload && payload.did)
        {
            _oauthSessionDid = payload.did;
            [self setSessionStorageValue:_oauthSessionDid forKey:[self oauthStorageKeySessionDid]];
        }
        [self syncOAuthSessionStateToUI];
        [self appendAuthResult:[self prettyJSON:payload]];
        [self setStatus:@"Session test completed."];
    }];
}

- (void)loadRecentPostsForOAuthSession
{
    var did = _oauthSessionDid || [self sessionStorageValueForKey:[self oauthStorageKeySessionDid]];
    if (!did || !did.length)
    {
        [self appendAuthResult:@"No DID for recent posts. Run session test first."];
        [self setStatus:@"Recent posts unavailable."];
        return;
    }

    [self appendAuthResult:("Loading recent posts for " + did + "...")];
    [_apiClient getJSONWithPath:@"/com.atproto.repo.listRecords"
                  endpointGroup:@"xrpc"
                    queryParams:{repo: did, collection: @"app.bsky.feed.post", limit: 5}
                     completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage)
        {
            [self appendAuthResult:("Recent posts failed: " + errorMessage)];
            [self setStatus:@"Recent posts failed."];
            return;
        }

        [self appendAuthResult:[self prettyJSON:payload]];
        [self setStatus:@"Recent posts loaded."];
    }];
}

- (void)createOAuthPostWithText:(CPString)text replyURI:(CPString)replyURI
{
    _oauthAccessToken = _oauthAccessToken || [self sessionStorageValueForKey:[self oauthStorageKeyAccessToken]];
    _oauthSessionDid = _oauthSessionDid || [self sessionStorageValueForKey:[self oauthStorageKeySessionDid]];

    if (!_oauthAccessToken || !_oauthAccessToken.length || !_oauthSessionDid || !_oauthSessionDid.length)
    {
        [self appendAuthResult:@"Create post blocked: login/session required."];
        [self setStatus:@"Create post failed."];
        return;
    }

    var trimmedText = [self trimmedString:text];
    if (!trimmedText || !trimmedText.length)
    {
        [self appendAuthResult:@"Create post blocked: post text is empty."];
        return;
    }

    if ([trimmedText length] > 300)
    {
        [self appendAuthResult:("Create post blocked: text too long (" + [trimmedText length] + "/300).")];
        return;
    }

    var createURL = [self oauthIssuer] + @"/xrpc/com.atproto.repo.createRecord",
        record = {
            $type: @"app.bsky.feed.post",
            text: trimmedText,
            createdAt: (new Date()).toISOString()
        },
        trimmedReply = [self trimmedString:replyURI];

    if (trimmedReply && [trimmedReply hasPrefix:@"at://"])
    {
        record.reply = {
            root: {uri: trimmedReply, cid: @""},
            parent: {uri: trimmedReply, cid: @""}
        };
    }

    var requestBody = JSON.stringify({
        repo: _oauthSessionDid,
        collection: @"app.bsky.feed.post",
        record: record
    });

    [self appendAuthResult:@"Creating post via com.atproto.repo.createRecord..."];
    [self dpopFetchJSONWithURL:createURL
                        method:@"POST"
                       headers:{"Content-Type": "application/json", Authorization: ("DPoP " + _oauthAccessToken)}
                          body:requestBody
                   accessToken:_oauthAccessToken
                    completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage)
        {
            [self appendAuthResult:("Create post failed: " + errorMessage)];
            [self setStatus:@"Create post failed."];
            return;
        }

        [self appendAuthResult:[self prettyJSON:payload]];
        [_postTextField setStringValue:@""];
        [_postReplyField setStringValue:@""];
        [self setStatus:@"Post created."];
    }];
}

- (void)loadAccounts
{
    [self setStatus:@"Loading accounts..."];

    [_apiClient getJSONWithPath:@"/accounts"
                  endpointGroup:@"explore"
                    queryParams:nil
                     completion:function(statusCode, payload, errorMessage)
    {
        var loadedAccounts = (payload && payload.accounts) ? payload.accounts : [];
        if (!loadedAccounts || !loadedAccounts.length)
            loadedAccounts = [];

        _accounts = loadedAccounts;
        [_accountsTable reloadData];

        if (errorMessage)
            [self setStatus:@"Failed to load accounts."];
        else
            [self setStatus:@"Loaded " + _accounts.length + " account(s)."];

        if (_currentDID)
        {
            var selectedIndex = [self indexOfAccountWithDID:_currentDID];
            if (selectedIndex >= 0)
                [_accountsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:selectedIndex]
                           byExtendingSelection:NO];
        }
        else if (_accounts.length > 0)
        {
            [_accountsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0]
                       byExtendingSelection:NO];
            [self selectAccountAtRow:0];
        }
    }];
}

- (int)indexOfAccountWithDID:(CPString)did
{
    if (!did)
        return -1;

    for (var i = 0; i < _accounts.length; i++)
    {
        var account = _accounts[i];
        if (account && account.did === did)
            return i;
    }

    return -1;
}

- (void)selectAccountAtRow:(int)row
{
    if (row < 0 || row >= _accounts.length)
        return;

    var account = _accounts[row],
        did = account ? account.did : nil;

    if (!did)
    {
        [self setStatus:@"Selected account is missing DID."];
        return;
    }

    [self loadAccountBundleForDID:did preferredHandle:(account.handle || did)];
}

- (CPArray)normalizeCollectionsFromDescribe:(id)describePayload
{
    var normalized = [];
    if (!describePayload || describePayload.error)
        return normalized;

    var collections = describePayload.collections;
    if (!collections || collections.length === undefined)
        return normalized;

    for (var i = 0; i < collections.length; i++)
    {
        var entry = collections[i];
        if (typeof entry === "string")
        {
            normalized.push({name: entry, count: ""});
            continue;
        }

        if (!entry)
            continue;

        var name = entry.collection || entry.name || entry.nsid || "",
            countValue = entry.count;

        normalized.push({
            name: name,
            count: (countValue === undefined || countValue === nil) ? "" : String(countValue)
        });
    }

    return normalized;
}

- (void)loadAccountBundleForDID:(CPString)did preferredHandle:(CPString)handle
{
    _currentDID = did;
    _currentHandle = handle || did;
    [_sessionState setCurrentDID:_currentDID];
    [_sessionState setCurrentHandle:_currentHandle];
    if (_oauthHandleField && _currentHandle && _currentHandle.length)
        [_oauthHandleField setStringValue:_currentHandle];
    if (_mstDidField)
        [_mstDidField setStringValue:(_currentDID || @"")];

    [self setStatus:@"Loading DID, PLC log, and collections..."];

    _currentDIDPayload = nil;
    _currentPLCPayload = nil;
    [self setTextView:_didTextView content:@"Loading..."];
    [self setTextView:_plcTextView content:@"Loading..."];
    _didSummaryRows = [];
    _didSummaryRows.push([self fieldValueRowWithField:@"Status" value:@"Loading DID document..."]);
    _didItemRows = [];
    [_didSummaryTable reloadData];
    [_didItemsTable reloadData];
    _plcOpRows = [];
    _plcOpRows.push({
        when: @"",
        summary: @"Loading",
        details: @"Loading PLC operation log...",
        detailRows: []
    });
    _plcDetailRows = [];
    [_plcOpsTable reloadData];
    [_plcDetailTable reloadData];

    var pending = 3,
        didPayload = nil,
        plcPayload = nil,
        describePayload = nil,
        complete = function()
        {
            pending -= 1;
            if (pending > 0)
                return;

            _currentDIDPayload = didPayload;
            _currentPLCPayload = plcPayload;
            [self setTextView:_didTextView content:[self prettyJSON:didPayload]];
            [self setTextView:_plcTextView content:[self prettyJSON:plcPayload]];
            [self refreshDIDView];
            [self refreshPLCView];

            _collections = [self normalizeCollectionsFromDescribe:describePayload];
            [_collectionsTable reloadData];

            _records = [];
            _selectedCollection = nil;
            _currentRecordPayload = nil;
            [_recordsTable reloadData];
            _recordSummaryRows = [];
            [_recordSummaryTable reloadData];
            [self setTextView:_recordBodyTextView content:@""];
            [self setTextView:_recordDetailTextView content:@""];
            [self refreshRecordDetailView];

            _currentFeedPayload = nil;
            _feedRows = [];
            _feedDetailRows = [];
            [_feedTable reloadData];
            [_feedDetailTable reloadData];
            [self setTextView:_feedTextView content:@""];
            [self refreshFeedView];

            _graphRows = [];
            _graphDetailRows = [];
            [_graphTable reloadData];
            [_graphDetailTable reloadData];

            _currentProfilePayload = nil;
            _profileSummaryRows = [];
            [_profileSummaryTable reloadData];
            [self setTextView:_profileBioTextView content:@""];
            [self setTextView:_profileTextView content:@""];
            [self refreshProfileView];

            _currentMSTTreePayload = nil;
            _currentMSTStatsPayload = nil;
            _mstExpanded = NO;
            _mstStatsRows = [];
            _mstNodeRows = [];
            [_mstStatsTable reloadData];
            [_mstNodesTable reloadData];
            [self setTextView:_mstTreeTextView content:@""];
            [self refreshMSTViews];

            if (describePayload && describePayload.error)
                [self setStatus:@"Loaded DID/PLC; failed to load collections."];
            else
                [self setStatus:@"Loaded account context for " + did + "."];

            if (_collections.length > 0)
                [_collectionsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0]
                           byExtendingSelection:NO];
        };

    [_apiClient getJSONWithPath:@"/did"
                  endpointGroup:@"explore"
                    queryParams:{did: did}
                     completion:function(statusCode, payload, errorMessage)
    {
        didPayload = payload || {error: errorMessage || "DID request failed"};
        if (errorMessage && !didPayload.error)
            didPayload.error = errorMessage;
        complete();
    }];

    [_apiClient getJSONWithPath:@"/plc-log"
                  endpointGroup:@"explore"
                    queryParams:{did: did}
                     completion:function(statusCode, payload, errorMessage)
    {
        plcPayload = payload || {error: errorMessage || "PLC request failed"};
        if (errorMessage && !plcPayload.error)
            plcPayload.error = errorMessage;
        complete();
    }];

    [_apiClient getJSONWithPath:@"/describe"
                  endpointGroup:@"explore"
                    queryParams:{did: did}
                     completion:function(statusCode, payload, errorMessage)
    {
        describePayload = payload || {error: errorMessage || "Describe request failed"};
        if (errorMessage && !describePayload.error)
            describePayload.error = errorMessage;
        complete();
    }];
}

- (void)loadRecordsForCollection:(CPString)collection
{
    if (!_currentDID)
    {
        [self setStatus:@"Select an account first."];
        return;
    }

    _selectedCollection = collection;
    [self setStatus:@"Loading records for " + collection + "..."];

    [_apiClient getJSONWithPath:@"/records"
                  endpointGroup:@"explore"
                    queryParams:{did: _currentDID, collection: collection, limit: 50}
                     completion:function(statusCode, payload, errorMessage)
    {
        var loadedRecords = (payload && payload.records) ? payload.records : [];
        if (!loadedRecords || !loadedRecords.length)
            loadedRecords = [];

        _records = loadedRecords;
        [_recordsTable reloadData];

        if (errorMessage)
            [self setStatus:@"Failed to load records for " + collection + "."];
        else
            [self setStatus:@"Loaded " + _records.length + " record(s) for " + collection + "."];

        if (_records.length > 0)
        {
            [_recordsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0]
                       byExtendingSelection:NO];
            [self loadRecordDetailForRow:0];
        }
        else
        {
            _currentRecordPayload = nil;
            _recordSummaryRows = [];
            [_recordSummaryTable reloadData];
            [self setTextView:_recordBodyTextView content:@"No records in this collection."];
            [self setTextView:_recordDetailTextView content:@"No records in this collection."];
            [self refreshRecordDetailView];
        }
    }];
}

- (void)loadRecordDetailForRow:(int)row
{
    if (row < 0 || row >= _records.length)
        return;

    var record = _records[row],
        uri = record ? record.uri : nil;

    if (!uri)
    {
        _currentRecordPayload = {error: @"Record URI missing."};
        [self refreshRecordDetailView];
        return;
    }

    [self setStatus:@"Loading record detail..."];

    [_apiClient getJSONWithPath:@"/record"
                  endpointGroup:@"explore"
                    queryParams:{uri: uri}
                     completion:function(statusCode, payload, errorMessage)
    {
        _currentRecordPayload = payload || {error: errorMessage || "Record request failed"};
        if (errorMessage && !_currentRecordPayload.error)
            _currentRecordPayload.error = errorMessage;

        [self refreshRecordDetailView];
        [self setStatus:@"Record detail loaded."];
    }];
}

- (CPArray)recordSummaryRowsForPayload:(id)recordPayload
{
    if (!recordPayload)
        return [];

    var rows = [];
    if (recordPayload.error)
    {
        rows.push([self fieldValueRowWithField:@"Error" value:recordPayload.error]);
        return rows;
    }

    var value = recordPayload.value || recordPayload,
        type = value.$type || recordPayload.$type || @"unknown",
        uri = recordPayload.uri || value.uri || @"",
        collection = recordPayload.collection || [self collectionFromRecordURI:uri],
        rkey = recordPayload.rkey || [self rkeyFromRecordURI:uri],
        createdAt = value.createdAt || recordPayload.createdAt || @"";

    rows.push([self fieldValueRowWithField:@"Type" value:type]);
    rows.push([self fieldValueRowWithField:@"URI" value:uri]);
    rows.push([self fieldValueRowWithField:@"CID" value:(recordPayload.cid || @"")]);
    rows.push([self fieldValueRowWithField:@"Collection" value:collection]);
    rows.push([self fieldValueRowWithField:@"RKey" value:rkey]);
    rows.push([self fieldValueRowWithField:@"Created At" value:createdAt]);

    if (type === @"app.bsky.feed.post")
        rows.push([self fieldValueRowWithField:@"Text Preview" value:[self singleLineSummary:value.text maxLength:180]]);
    else if (type === @"app.bsky.actor.profile")
        rows.push([self fieldValueRowWithField:@"Display Name" value:(value.displayName || @"")]);
    else if (type === @"app.bsky.feed.like" || type === @"app.bsky.feed.repost")
        rows.push([self fieldValueRowWithField:@"Subject URI" value:((value.subject && value.subject.uri) || @"")]);
    else if (type === @"app.bsky.graph.follow")
        rows.push([self fieldValueRowWithField:@"Subject DID" value:(value.subject || @"")]);

    return rows;
}

- (CPString)recordBodyForPayload:(id)recordPayload
{
    if (!recordPayload)
        return @"";

    if (recordPayload.error)
        return "Error: " + recordPayload.error;

    var value = recordPayload.value || recordPayload,
        type = value.$type || recordPayload.$type || @"unknown";

    if (type === @"app.bsky.feed.post")
        return [self safeString:value.text];

    if (type === @"app.bsky.actor.profile")
        return [self safeString:value.description];

    if (type === @"app.bsky.feed.like" || type === @"app.bsky.feed.repost")
    {
        var subjectURI = (value.subject && value.subject.uri) || @"",
            subjectCID = (value.subject && value.subject.cid) || @"";
        return "Subject URI: " + subjectURI + "\nSubject CID: " + subjectCID;
    }

    if (type === @"app.bsky.graph.follow")
        return "Following DID: " + [self safeString:value.subject];

    return [self prettyJSON:value];
}

- (void)refreshRecordDetailView
{
    var mode = [_recordModePopup titleOfSelectedItem],
        showJSON = (mode && [mode isEqual:@"JSON"]);

    [_recordRenderedView setHidden:showJSON];
    [_recordDetailTextView setHidden:!showJSON];

    if (showJSON)
    {
        [self setTextView:_recordDetailTextView content:(_currentRecordPayload ? [self prettyJSON:_currentRecordPayload] : @"")];
        return;
    }

    if (!_currentRecordPayload)
    {
        _recordSummaryRows = [];
        [_recordSummaryTable reloadData];
        [self setTextView:_recordBodyTextView content:@""];
        return;
    }

    _recordSummaryRows = [self recordSummaryRowsForPayload:_currentRecordPayload];
    [_recordSummaryTable reloadData];
    [self setTextView:_recordBodyTextView content:[self recordBodyForPayload:_currentRecordPayload]];
}

- (CPArray)feedEntriesFromPayload:(id)feedPayload mode:(CPString)mode
{
    if (!feedPayload)
        return [];

    var rows = [],
        i = 0;

    if (feedPayload.error)
    {
        var errorDetailRows = [];
        errorDetailRows.push([self fieldValueRowWithField:@"Error" value:feedPayload.error]);
        rows.push({
            type: @"Error",
            actor: @"",
            primary: [self safeString:feedPayload.error],
            createdAt: @"",
            detailRows: errorDetailRows
        });
        return rows;
    }

    if ([mode isEqual:@"Posts"])
    {
        var posts = feedPayload.posts || [];
        for (i = 0; i < posts.length; i++)
        {
            var post = posts[i] || {},
                record = post.record || {},
                actor = post.author || {};

            rows.push({
                type: @"Post",
                actor: [self safeString:(actor.handle || actor.did || @"")],
                primary: [self singleLineSummary:record.text maxLength:140],
                createdAt: [self safeString:(record.createdAt || post.indexedAt || @"")],
                detailRows: [
                    [self fieldValueRowWithField:@"Actor Handle" value:(actor.handle || @"")],
                    [self fieldValueRowWithField:@"Actor DID" value:(actor.did || @"")],
                    [self fieldValueRowWithField:@"URI" value:(post.uri || @"")],
                    [self fieldValueRowWithField:@"CID" value:(post.cid || @"")],
                    [self fieldValueRowWithField:@"Created At" value:(record.createdAt || post.indexedAt || @"")],
                    [self fieldValueRowWithField:@"Text" value:(record.text || @"")]
                ]
            });
        }
    }
    else
    {
        var source = [mode isEqual:@"Likes"] ? (feedPayload.likes || []) : (feedPayload.reposts || []),
            typeLabel = [mode isEqual:@"Likes"] ? @"Like" : @"Repost";

        for (i = 0; i < source.length; i++)
        {
            var entry = source[i] || {},
                actorInfo = entry.actor || entry.author || {},
                subject = entry.subject || {},
                subjectAuthor = subject.author || {};

            rows.push({
                type: typeLabel,
                actor: [self safeString:(actorInfo.handle || actorInfo.did || @"")],
                primary: [self singleLineSummary:(subject.uri || @"") maxLength:140],
                createdAt: [self safeString:(entry.createdAt || @"")],
                detailRows: [
                    [self fieldValueRowWithField:@"Actor Handle" value:(actorInfo.handle || @"")],
                    [self fieldValueRowWithField:@"Actor DID" value:(actorInfo.did || @"")],
                    [self fieldValueRowWithField:@"URI" value:(entry.uri || @"")],
                    [self fieldValueRowWithField:@"CID" value:(entry.cid || @"")],
                    [self fieldValueRowWithField:@"Subject URI" value:(subject.uri || @"")],
                    [self fieldValueRowWithField:@"Subject CID" value:(subject.cid || @"")],
                    [self fieldValueRowWithField:@"Subject Author" value:(subjectAuthor.handle || subjectAuthor.did || @"")],
                    [self fieldValueRowWithField:@"Created At" value:(entry.createdAt || @"")]
                ]
            });
        }
    }

    return rows;
}

- (void)refreshFeedSelectionDetail
{
    var selectedRow = _feedTable ? [_feedTable selectedRow] : -1;
    if (selectedRow < 0 || selectedRow >= _feedRows.length)
    {
        _feedDetailRows = [];
        [_feedDetailTable reloadData];
        return;
    }

    var selected = _feedRows[selectedRow] || {};
    _feedDetailRows = selected.detailRows || [];
    [_feedDetailTable reloadData];
}

- (void)refreshFeedView
{
    var viewMode = [_feedViewModePopup titleOfSelectedItem],
        showJSON = (viewMode && [viewMode isEqual:@"JSON"]);

    [_feedRenderedView setHidden:showJSON];
    [_feedTextView setHidden:!showJSON];

    if (showJSON)
    {
        [self setTextView:_feedTextView content:(_currentFeedPayload ? [self prettyJSON:_currentFeedPayload] : @"")];
        return;
    }

    if (!_currentFeedPayload)
    {
        _feedRows = [];
        _feedDetailRows = [];
        [_feedTable reloadData];
        [_feedDetailTable reloadData];
        return;
    }

    _feedRows = [self feedEntriesFromPayload:_currentFeedPayload mode:(_currentFeedMode || [_feedModePopup titleOfSelectedItem] || @"Posts")];
    [_feedTable reloadData];

    if (_feedRows.length > 0)
    {
        var selectedRow = [_feedTable selectedRow];
        if (selectedRow < 0 || selectedRow >= _feedRows.length)
            [_feedTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self refreshFeedSelectionDetail];
}

- (CPArray)profileSummaryRowsFromPayload:(id)profilePayload
{
    if (!profilePayload)
        return [];

    var rows = [];
    if (profilePayload.error)
    {
        rows.push([self fieldValueRowWithField:@"Error" value:profilePayload.error]);
        return rows;
    }

    rows.push([self fieldValueRowWithField:@"Handle" value:profilePayload.handle]);
    rows.push([self fieldValueRowWithField:@"DID" value:profilePayload.did]);
    rows.push([self fieldValueRowWithField:@"Display Name" value:profilePayload.displayName]);
    rows.push([self fieldValueRowWithField:@"Followers" value:profilePayload.followersCount]);
    rows.push([self fieldValueRowWithField:@"Following" value:profilePayload.followsCount]);
    rows.push([self fieldValueRowWithField:@"Posts" value:profilePayload.postsCount]);
    rows.push([self fieldValueRowWithField:@"Created At" value:profilePayload.createdAt]);
    rows.push([self fieldValueRowWithField:@"Avatar" value:profilePayload.avatar]);
    rows.push([self fieldValueRowWithField:@"Banner" value:profilePayload.banner]);
    return rows;
}

- (void)refreshProfileView
{
    var mode = [_profileViewModePopup titleOfSelectedItem],
        showJSON = (mode && [mode isEqual:@"JSON"]);

    [_profileRenderedView setHidden:showJSON];
    [_profileTextView setHidden:!showJSON];

    if (showJSON)
    {
        [self setTextView:_profileTextView content:(_currentProfilePayload ? [self prettyJSON:_currentProfilePayload] : @"")];
        return;
    }

    if (!_currentProfilePayload)
    {
        _profileSummaryRows = [];
        [_profileSummaryTable reloadData];
        [self setTextView:_profileBioTextView content:@""];
        return;
    }

    _profileSummaryRows = [self profileSummaryRowsFromPayload:_currentProfilePayload];
    [_profileSummaryTable reloadData];
    if (_currentProfilePayload.error)
        [self setTextView:_profileBioTextView content:("Error: " + _currentProfilePayload.error)];
    else
        [self setTextView:_profileBioTextView content:[self safeString:_currentProfilePayload.description]];
}

- (CPString)activeMSTDid
{
    var did = _mstDidField ? [self trimmedString:[_mstDidField stringValue]] : @"";
    if (did && did.length)
        return did;
    return _currentDID || @"";
}

- (CPArray)mstStatsRowsFromPayloads
{
    if (!_currentMSTStatsPayload && !_currentMSTTreePayload)
        return [];

    var rows = [];
    if (_currentMSTStatsPayload && _currentMSTStatsPayload.error)
    {
        rows.push([self fieldValueRowWithField:@"Error" value:_currentMSTStatsPayload.error]);
        return rows;
    }

    var stats = _currentMSTStatsPayload || {},
        tree = _currentMSTTreePayload || {};

    rows.push([self fieldValueRowWithField:@"DID" value:[self activeMSTDid]]);
    rows.push([self fieldValueRowWithField:@"Root CID" value:(tree.rootCID || @"")]);
    rows.push([self fieldValueRowWithField:@"Nodes" value:(stats.nodeCount !== undefined ? stats.nodeCount : tree.nodeCount)]);
    rows.push([self fieldValueRowWithField:@"Entries" value:(stats.entryCount !== undefined ? stats.entryCount : tree.entryCount)]);
    rows.push([self fieldValueRowWithField:@"Depth" value:(stats.maxDepth !== undefined ? stats.maxDepth : tree.maxDepth)]);

    if (stats.leafNodeCount !== undefined)
        rows.push([self fieldValueRowWithField:@"Leaf Nodes" value:stats.leafNodeCount]);

    return rows;
}

- (CPArray)mstNodeRowsFromTreePayload:(id)treePayload
{
    if (!treePayload)
        return [];

    var rows = [];
    if (treePayload.error)
    {
        rows.push({
            level: @"",
            kind: @"error",
            entries: @"",
            left: @"",
            cid: [self safeString:treePayload.error]
        });
        return rows;
    }

    var nodes = treePayload.nodes;
    if (!nodes || nodes.length === undefined || !nodes.length)
    {
        rows.push({
            level: @"",
            kind: @"info",
            entries: @"",
            left: @"",
            cid: @"No nodes returned."
        });
        return rows;
    }

    var limit = Math.min(nodes.length, 400);
    for (var i = 0; i < limit; i++)
    {
        var node = nodes[i] || {},
            level = (node.level === undefined || node.level === nil) ? @"?" : String(node.level),
            kind = node.kind || ((node.level === 0) ? @"leaf" : @"internal"),
            entryCount = (node.entries && node.entries.length !== undefined) ? node.entries.length : 0;

        rows.push({
            level: level,
            kind: kind,
            entries: String(entryCount),
            left: node.left ? @"yes" : @"no",
            cid: [self safeString:node.cid]
        });
    }

    if (nodes.length > limit)
    {
        rows.push({
            level: @"",
            kind: @"note",
            entries: @"",
            left: @"",
            cid: ("Showing first " + limit + " of " + nodes.length + " nodes")
        });
    }

    return rows;
}

- (void)refreshMSTViews
{
    _mstStatsRows = [self mstStatsRowsFromPayloads];
    [_mstStatsTable reloadData];

    if (!_currentMSTTreePayload)
    {
        _mstNodeRows = [];
        [_mstNodesTable reloadData];
        [_mstTreeListView setHidden:NO];
        [_mstTreeTextView setHidden:YES];
        [self setTextView:_mstTreeTextView content:@""];
        return;
    }

    _mstNodeRows = [self mstNodeRowsFromTreePayload:_currentMSTTreePayload];
    [_mstNodesTable reloadData];

    if (_mstExpanded)
    {
        [_mstTreeListView setHidden:YES];
        [_mstTreeTextView setHidden:NO];
        [self setTextView:_mstTreeTextView content:[self prettyJSON:_currentMSTTreePayload]];
    }
    else
    {
        [_mstTreeListView setHidden:NO];
        [_mstTreeTextView setHidden:YES];
        [self setTextView:_mstTreeTextView content:@""];
    }
}

- (void)loadMSTBundleForDid:(CPString)did
{
    if (!did || !did.length)
    {
        [self setStatus:@"Enter a DID first."];
        return;
    }

    if (_mstDidField)
        [_mstDidField setStringValue:did];

    [self setStatus:@"Loading MST tree and stats..."];
    _mstStatsRows = [];
    _mstStatsRows.push([self fieldValueRowWithField:@"Status" value:@"Loading..."]);
    [_mstStatsTable reloadData];
    _mstNodeRows = [];
    [_mstNodesTable reloadData];
    [self setTextView:_mstTreeTextView content:@"Loading..."];

    var encodedDid = encodeURIComponent(String(did)),
        pending = 2,
        treePayload = nil,
        statsPayload = nil,
        sawError = NO,
        complete = function()
        {
            pending -= 1;
            if (pending > 0)
                return;

            _currentMSTTreePayload = treePayload;
            _currentMSTStatsPayload = statsPayload;
            [self refreshMSTViews];

            if (treePayload && treePayload.error)
                [self setStatus:@"Failed to load MST tree."];
            else if (sawError)
                [self setStatus:@"Loaded MST tree with partial stats data."];
            else
                [self setStatus:@"Loaded MST tree and stats for " + did + "."];
        };

    [_apiClient getJSONWithPath:("/tree/" + encodedDid)
                  endpointGroup:@"mst"
                    queryParams:nil
                     completion:function(statusCode, payload, errorMessage)
    {
        treePayload = payload || {error: errorMessage || "MST tree request failed"};
        if (errorMessage && !treePayload.error)
            treePayload.error = errorMessage;
        if (treePayload.error)
            sawError = YES;
        complete();
    }];

    [_apiClient getJSONWithPath:("/stats/" + encodedDid)
                  endpointGroup:@"mst"
                    queryParams:nil
                     completion:function(statusCode, payload, errorMessage)
    {
        statsPayload = payload || {error: errorMessage || "MST stats request failed"};
        if (errorMessage && !statsPayload.error)
            statsPayload.error = errorMessage;
        if (statsPayload.error)
            sawError = YES;
        complete();
    }];
}

- (CPString)escapeForDOT:(CPString)value
{
    var stringValue = [self safeString:value];
    stringValue = stringValue.replace(/\\/g, "\\\\");
    stringValue = stringValue.replace(/"/g, "\\\"");
    return stringValue;
}

- (CPString)buildDOTFromMSTTreePayload:(id)treePayload
{
    if (!treePayload || !treePayload.nodes || treePayload.nodes.length === undefined)
        return @"digraph MST {\n  label=\"Empty MST\";\n}\n";

    var lines = [];
    lines.push("digraph MST {");
    lines.push("  rankdir=TB;");
    lines.push("  node [shape=box, fontname=\"monospace\", fontsize=10];");

    var nodes = treePayload.nodes || [];
    for (var i = 0; i < nodes.length; i++)
    {
        var node = nodes[i] || {},
            cid = [self safeString:node.cid];
        if (!cid.length)
            continue;

        var level = (node.level === nil || node.level === undefined) ? @"?" : String(node.level),
            kind = node.kind || ((node.level === 0) ? @"leaf" : @"internal"),
            entryCount = (node.entries && node.entries.length !== undefined) ? node.entries.length : 0,
            label = "L" + level + " " + kind + "\\n" + [self abbreviatedString:cid maxLength:22] + "\\nentries=" + entryCount;

        lines.push("  \"" + [self escapeForDOT:cid] + "\" [label=\"" + label + "\"];");
    }

    for (var j = 0; j < nodes.length; j++)
    {
        var sourceNode = nodes[j] || {},
            sourceCID = [self safeString:sourceNode.cid];
        if (!sourceCID.length)
            continue;

        if (sourceNode.left)
        {
            lines.push("  \"" + [self escapeForDOT:sourceCID] + "\" -> \"" + [self escapeForDOT:sourceNode.left] + "\" [label=\"left\"];");
        }

        var entries = sourceNode.entries || [];
        for (var k = 0; k < entries.length; k++)
        {
            var entry = entries[k] || {};
            if (entry.tree)
            {
                var entryLabel = [self abbreviatedString:(entry.fullKey || entry.key || @"entry") maxLength:18];
                lines.push("  \"" + [self escapeForDOT:sourceCID] + "\" -> \"" + [self escapeForDOT:entry.tree] + "\" [label=\"" + [self escapeForDOT:entryLabel] + "\"];");
            }
        }
    }

    if (treePayload.rootCID)
    {
        lines.push("  root [shape=diamond, label=\"root\"];");
        lines.push("  root -> \"" + [self escapeForDOT:treePayload.rootCID] + "\";");
    }

    lines.push("}");
    return lines.join("\n") + "\n";
}

- (CPString)localMSTExportPayloadForFormat:(CPString)format
{
    if (!_currentMSTTreePayload)
        return nil;

    var normalizedFormat = [(format || @"JSON") lowercaseString];
    if ([normalizedFormat isEqual:@"dot"])
        return [self buildDOTFromMSTTreePayload:_currentMSTTreePayload];
    if ([normalizedFormat isEqual:@"svg"])
    {
        var dot = [self buildDOTFromMSTTreePayload:_currentMSTTreePayload],
            escapedDot = dot.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1200\" height=\"700\">"
             + "<rect x=\"0\" y=\"0\" width=\"1200\" height=\"700\" fill=\"#ffffff\" stroke=\"#111111\"/>"
             + "<text x=\"20\" y=\"30\" font-family=\"monospace\" font-size=\"14\">MST export (local SVG placeholder)</text>"
             + "<text x=\"20\" y=\"54\" font-family=\"monospace\" font-size=\"12\">DOT content:</text>"
             + "<foreignObject x=\"20\" y=\"68\" width=\"1160\" height=\"610\"><div xmlns=\"http://www.w3.org/1999/xhtml\" style=\"font-family: monospace; font-size: 11px; white-space: pre-wrap; color: #222;\">"
             + escapedDot
             + "</div></foreignObject></svg>";
    }

    return [self prettyJSON:_currentMSTTreePayload];
}

- (CPString)localMSTExportFileExtensionForFormat:(CPString)format
{
    var normalizedFormat = [(format || @"JSON") lowercaseString];
    if ([normalizedFormat isEqual:@"dot"])
        return @"dot";
    if ([normalizedFormat isEqual:@"svg"])
        return @"svg";
    return @"json";
}

- (CPString)localMSTExportMimeTypeForFormat:(CPString)format
{
    var normalizedFormat = [(format || @"JSON") lowercaseString];
    if ([normalizedFormat isEqual:@"dot"])
        return @"text/plain;charset=utf-8";
    if ([normalizedFormat isEqual:@"svg"])
        return @"image/svg+xml;charset=utf-8";
    return @"application/json;charset=utf-8";
}

- (void)downloadText:(CPString)text
            fileName:(CPString)fileName
            mimeType:(CPString)mimeType
{
    if (!(window && window.document && window.Blob && window.URL && window.URL.createObjectURL))
        return;

    var blob = new Blob([String(text || @"")], {type: String(mimeType || @"text/plain;charset=utf-8")}),
        objectURL = window.URL.createObjectURL(blob),
        doc = window.document,
        anchor = doc.createElement("a");

    anchor.href = objectURL;
    anchor.download = String(fileName || @"download.txt");
    doc.body.appendChild(anchor);
    anchor.click();
    doc.body.removeChild(anchor);
    window.setTimeout(function()
    {
        window.URL.revokeObjectURL(objectURL);
    }, 0);
}

- (void)exportMSTForDid:(CPString)did format:(CPString)format
{
    if (!_currentMSTTreePayload)
    {
        [self setStatus:@"Load MST data first."];
        [self setTextView:_utilityTextView content:@"No MST payload loaded. Click Load MST first."];
        return;
    }

    var exportDid = did && did.length ? did : [self activeMSTDid],
        normalizedFormat = [(format || @"JSON") lowercaseString],
        exportPayload = [self localMSTExportPayloadForFormat:normalizedFormat],
        extension = [self localMSTExportFileExtensionForFormat:normalizedFormat],
        mimeType = [self localMSTExportMimeTypeForFormat:normalizedFormat],
        safeDid = [self safeString:exportDid].replace(/[^a-zA-Z0-9._-]/g, "_"),
        fileName = ("mst-" + (safeDid.length ? safeDid : "export") + "." + extension);

    [self downloadText:exportPayload fileName:fileName mimeType:mimeType];
    [self setTextView:_utilityTextView content:exportPayload];
    [self setStatus:@"MST export generated locally (" + normalizedFormat + ")."];
}

- (CPString)plcBaseURL
{
    if (!(window && window.location))
        return @"https://plc.directory";

    var loc = window.location,
        host = String(loc.hostname || ""),
        protocol = String(loc.protocol || "https:");

    if (host.length >= 11 && host.slice(host.length - 11) === "garazyk.xyz")
        return protocol + "//plc.garazyk.xyz";

    if (host.length)
        return protocol + "//" + host + ":4000";

    return @"https://plc.directory";
}

- (void)openPLCURL:(CPString)url label:(CPString)label
{
    if (window && window.open)
        window.open(String(url), "_blank");

    [self setTextView:_utilityTextView content:("Opened " + label + ":\n" + url)];
    [self setStatus:@"Opened " + label + " in a new tab."];
}

- (void)loadFeedForCurrentMode
{
    if (!_currentDID)
    {
        [self setStatus:@"Select an account first."];
        return;
    }

    var mode = [_feedModePopup titleOfSelectedItem] || @"Posts",
        endpoint = @"/feed-posts";

    if ([mode isEqual:@"Likes"])
        endpoint = @"/feed-likes";
    else if ([mode isEqual:@"Reposts"])
        endpoint = @"/feed-reposts";

    [self setStatus:@"Loading " + mode + "..."];

    [_apiClient getJSONWithPath:endpoint
                  endpointGroup:@"explore"
                    queryParams:{did: _currentDID, limit: 30}
                     completion:function(statusCode, payload, errorMessage)
    {
        _currentFeedMode = mode;
        _currentFeedPayload = payload || {error: errorMessage || "Feed request failed"};
        if (errorMessage && !_currentFeedPayload.error)
            _currentFeedPayload.error = errorMessage;

        [self refreshFeedView];

        if (_currentFeedPayload.error)
            [self setStatus:@"Failed to load " + mode + "."];
        else
        {
            var loadedCount = 0;
            if ([mode isEqual:@"Posts"])
                loadedCount = (_currentFeedPayload.posts && _currentFeedPayload.posts.length) ? _currentFeedPayload.posts.length : 0;
            else if ([mode isEqual:@"Likes"])
                loadedCount = (_currentFeedPayload.likes && _currentFeedPayload.likes.length) ? _currentFeedPayload.likes.length : 0;
            else
                loadedCount = (_currentFeedPayload.reposts && _currentFeedPayload.reposts.length) ? _currentFeedPayload.reposts.length : 0;
            [self setStatus:@"Loaded " + loadedCount + " " + [mode lowercaseString] + "."];
        }
    }];
}

- (void)loadGraphFollows
{
    if (!_currentDID)
    {
        [self setStatus:@"Select an account first."];
        return;
    }

    [self setStatus:@"Loading graph follows..."];

    [_apiClient getJSONWithPath:@"/graph-follows"
                  endpointGroup:@"explore"
                    queryParams:{did: _currentDID, limit: 100}
                     completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage)
        {
            _graphRows = [{handle: @"", did: @"", displayName: @"", createdAt: @"", avatar: @"", error: errorMessage}];
            [_graphTable reloadData];
            _graphDetailRows = [];
            _graphDetailRows.push([self fieldValueRowWithField:@"Error" value:errorMessage]);
            [_graphDetailTable reloadData];
            [self setStatus:@"Failed to load graph follows."];
            return;
        }

        _graphRows = (payload && payload.actors) ? payload.actors : [];
        if (!_graphRows || !_graphRows.length)
            _graphRows = [];
        [_graphTable reloadData];

        if (_graphRows.length > 0)
            [_graphTable selectRowIndexes:[CPIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        else
        {
            _graphDetailRows = [];
            _graphDetailRows.push([self fieldValueRowWithField:@"Info" value:@"No follows returned."]);
            [_graphDetailTable reloadData];
        }

        [self refreshGraphDetailView];
        [self setStatus:@"Loaded " + _graphRows.length + " follow entries."];
    }];
}

- (void)refreshGraphDetailView
{
    var selectedRow = _graphTable ? [_graphTable selectedRow] : -1;
    if (selectedRow < 0 || selectedRow >= _graphRows.length)
    {
        _graphDetailRows = [];
        [_graphDetailTable reloadData];
        return;
    }

    var actor = _graphRows[selectedRow] || {};
    _graphDetailRows = [];
    if (actor.error)
        _graphDetailRows.push([self fieldValueRowWithField:@"Error" value:actor.error]);
    else
    {
        _graphDetailRows.push([self fieldValueRowWithField:@"Handle" value:actor.handle]);
        _graphDetailRows.push([self fieldValueRowWithField:@"DID" value:actor.did]);
        _graphDetailRows.push([self fieldValueRowWithField:@"Display Name" value:actor.displayName]);
        _graphDetailRows.push([self fieldValueRowWithField:@"Created At" value:actor.createdAt]);
        _graphDetailRows.push([self fieldValueRowWithField:@"Avatar" value:actor.avatar]);
    }
    [_graphDetailTable reloadData];
}

- (void)loadActorProfile
{
    if (!_currentDID)
    {
        [self setStatus:@"Select an account first."];
        return;
    }

    [self setStatus:@"Loading actor profile..."];

    [_apiClient getJSONWithPath:@"/actor-profile"
                  endpointGroup:@"explore"
                    queryParams:{did: _currentDID}
                     completion:function(statusCode, payload, errorMessage)
    {
        _currentProfilePayload = payload || {error: errorMessage || "Actor profile request failed"};
        if (errorMessage && !_currentProfilePayload.error)
            _currentProfilePayload.error = errorMessage;

        [self refreshProfileView];

        if (_currentProfilePayload.error)
            [self setStatus:@"Failed to load actor profile."];
        else
            [self setStatus:@"Actor profile loaded."];
    }];
}

- (int)base32ValueForCharacter:(CPString)character
{
    if (!character || ![character length])
        return -1;

    var c = [character lowercaseString],
        alphabet = @"abcdefghijklmnopqrstuvwxyz234567",
        index = [alphabet rangeOfString:c].location;

    if (index === CPNotFound)
        return -1;

    return index;
}

- (CPArray)decodeBase32StringToBytes:(CPString)value
{
    if (!value)
        return nil;

    var bytes = [],
        buffer = 0,
        bits = 0;

    for (var i = 0; i < [value length]; i++)
    {
        var ch = [value substringWithRange:CPMakeRange(i, 1)];
        if ([ch isEqual:@"-"] || [ch isEqual:@" "] || [ch isEqual:@"\n"] || [ch isEqual:@"\r"] || [ch isEqual:@"\t"])
            continue;

        var digit = [self base32ValueForCharacter:ch];
        if (digit < 0)
            return nil;

        buffer = (buffer * 32) + digit;
        bits += 5;

        while (bits >= 8)
        {
            bits -= 8;
            var divisor = Math.pow(2, bits),
                nextByte = Math.floor(buffer / divisor);
            bytes.push(nextByte);
            buffer = buffer - (nextByte * divisor);
        }
    }

    return bytes;
}

- (id)readVarintFromBytes:(CPArray)bytes offset:(int)offset
{
    var value = 0,
        shift = 0,
        index = offset;

    while (index < bytes.length)
    {
        var currentByte = bytes[index];
        var lowBits = currentByte;
        while (lowBits >= 128)
            lowBits = lowBits - 128;
        value += lowBits * Math.pow(2, shift);
        index += 1;

        if (currentByte < 128)
            return {value: value, nextOffset: index};

        shift += 7;
        if (shift > 35)
            return nil;
    }

    return nil;
}

- (CPString)cidCodecNameForCode:(int)code
{
    if (code === 0x55)
        return @"raw";
    if (code === 0x70)
        return @"dag-pb";
    if (code === 0x71)
        return @"dag-cbor";
    if (code === 0x72 || code === 0x129)
        return @"dag-json";
    return @"unknown";
}

- (CPString)cidHashNameForCode:(int)code
{
    if (code === 0x11)
        return @"SHA-1";
    if (code === 0x12)
        return @"SHA-256";
    if (code === 0x13)
        return @"SHA-512";
    if (code === 0xB220)
        return @"Blake2b-256";
    if (code === 0xB240)
        return @"Blake2b-512";
    return @"unknown";
}

- (CPString)byteArrayToHexWithSpaces:(CPArray)bytes
{
    if (!bytes || !bytes.length)
        return @"";

    var parts = [];
    for (var i = 0; i < bytes.length; i++)
    {
        var hex = bytes[i].toString(16);
        if (hex.length < 2)
            hex = "0" + hex;
        parts.push(hex);
    }
    return parts.join(" ");
}

- (CPString)byteArrayToHexNoSpaces:(CPArray)bytes
{
    if (!bytes || !bytes.length)
        return @"";

    var parts = [];
    for (var i = 0; i < bytes.length; i++)
    {
        var hex = bytes[i].toString(16);
        if (hex.length < 2)
            hex = "0" + hex;
        parts.push(hex);
    }
    return parts.join("");
}

- (id)decodeCIDLocally:(CPString)cid
{
    if (!cid || [cid length] < 2)
        return {error: @"Invalid CID: too short"};

    var multibase = [cid substringWithRange:CPMakeRange(0, 1)],
        encoded = [cid substringFromIndex:1];

    if (![multibase lowercaseString] || ![[multibase lowercaseString] isEqual:@"b"])
        return {error: @"Unsupported CID multibase (expected base32 'b' prefix)"};

    var bytes = [self decodeBase32StringToBytes:encoded];
    if (!bytes || !bytes.length)
        return {error: @"Invalid CID: failed to decode base32"};

    var versionVarint = [self readVarintFromBytes:bytes offset:0];
    if (!versionVarint)
        return {error: @"Invalid CID: failed to parse version"};

    var version = versionVarint.value,
        offset = versionVarint.nextOffset,
        codecCode = nil,
        hashCode = nil,
        hashSize = nil;

    if (version !== 1)
        return {error: @"Unsupported CID version: " + version + " (only CIDv1 base32 supported)"};

    var codecVarint = [self readVarintFromBytes:bytes offset:offset];
    if (!codecVarint)
        return {error: @"Invalid CID: failed to parse codec"};
    codecCode = codecVarint.value;
    offset = codecVarint.nextOffset;

    var hashVarint = [self readVarintFromBytes:bytes offset:offset];
    if (!hashVarint)
        return {error: @"Invalid CID: failed to parse hash algorithm"};
    hashCode = hashVarint.value;
    offset = hashVarint.nextOffset;

    var sizeVarint = [self readVarintFromBytes:bytes offset:offset];
    if (!sizeVarint)
        return {error: @"Invalid CID: failed to parse digest length"};
    hashSize = sizeVarint.value;
    offset = sizeVarint.nextOffset;

    var digest = bytes.slice(offset);
    if (hashSize !== digest.length)
    {
        return {
            error: @"Invalid CID: digest length mismatch",
            expected: hashSize,
            actual: digest.length
        };
    }

    return {
        input: cid,
        multibase: multibase,
        version: version,
        codecCode: codecCode,
        codecName: [self cidCodecNameForCode:codecCode],
        hashCode: hashCode,
        hashName: [self cidHashNameForCode:hashCode],
        hashSize: hashSize,
        digestHex: [self byteArrayToHexNoSpaces:digest],
        rawByteLength: bytes.length,
        rawBytesHex: [self byteArrayToHexWithSpaces:bytes]
    };
}

- (CPString)renderCIDDecodeResult:(id)decoded
{
    if (!decoded)
        return @"";

    if (decoded.error)
        return "Error: " + decoded.error;

    var lines = [];
    lines.push("CID Decode");
    lines.push("Input: " + [self safeString:decoded.input]);
    lines.push("Version: " + [self safeString:decoded.version]);
    lines.push("Multibase: " + [self safeString:decoded.multibase]);
    lines.push("Codec: 0x" + [self safeString:decoded.codecCode.toString(16)] + " (" + [self safeString:decoded.codecName] + ")");
    lines.push("Hash Algorithm: 0x" + [self safeString:decoded.hashCode.toString(16)] + " (" + [self safeString:decoded.hashName] + ")");
    lines.push("Hash Size: " + [self safeString:decoded.hashSize] + " bytes");
    lines.push("Digest: " + [self safeString:decoded.digestHex]);
    lines.push("Byte Length: " + [self safeString:decoded.rawByteLength] + " bytes");
    lines.push("");
    lines.push("Raw Bytes (hex):");
    lines.push([self safeString:decoded.rawBytesHex]);
    return lines.join("\n");
}

- (void)decodeCID
{
    var cid = [self trimmedString:[_cidField stringValue]];
    if (!cid || !cid.length)
    {
        [self setStatus:@"Enter a CID first."];
        return;
    }

    [self setStatus:@"Decoding CID..."];

    var decode = [self decodeCIDLocally:cid];
    if (decode.error)
    {
        [self setTextView:_utilityTextView content:("Error: " + decode.error)];
        [self setStatus:@"CID decode failed."];
        return;
    }

    [self setTextView:_utilityTextView content:[self renderCIDDecodeResult:decode]];
    [self setStatus:@"CID decoded locally."];
}

- (void)openAPIDocs
{
    if (window && window.open)
        window.open("/api/pds/docs", "_blank");

    [self setStatus:@"Opened API docs in a new tab."];
}

#pragma mark - Actions

- (void)handleRefreshAccounts:(id)sender
{
    [self loadAccounts];
}

- (void)handleFocusSearch:(id)sender
{
    if (_lookupField && [_lookupField window])
        [[_lookupField window] makeFirstResponder:_lookupField];
}

- (void)handleLookup:(id)sender
{
    var input = [self trimmedString:[_lookupField stringValue]];
    if (!input || !input.length)
    {
        [self setStatus:@"Enter a DID or handle to lookup."];
        return;
    }

    var query = [input hasPrefix:@"did:"] ? {did: input} : {handle: input};
    [self setStatus:@"Looking up " + input + "..."];

    [_apiClient getJSONWithPath:@"/lookup"
                  endpointGroup:@"explore"
                    queryParams:query
                     completion:function(statusCode, payload, errorMessage)
    {
        if (errorMessage || !payload || !payload.did)
        {
            [self setStatus:@"Lookup failed."];
            return;
        }

        var did = payload.did,
            handle = payload.handle || did,
            existingRow = [self indexOfAccountWithDID:did];

        if (existingRow < 0)
        {
            _accounts.push({did: did, handle: handle});
            [_accountsTable reloadData];
            existingRow = _accounts.length - 1;
        }

        [_accountsTable selectRowIndexes:[CPIndexSet indexSetWithIndex:existingRow]
                   byExtendingSelection:NO];
        [self loadAccountBundleForDID:did preferredHandle:handle];
    }];
}

- (void)handleLoadSelectedCollection:(id)sender
{
    var selectedRow = [_collectionsTable selectedRow];
    if (selectedRow < 0 && _collections.length > 0)
        selectedRow = 0;

    if (selectedRow < 0 || selectedRow >= _collections.length)
    {
        [self setStatus:@"Select a collection first."];
        return;
    }

    var collection = _collections[selectedRow];
    [self loadRecordsForCollection:(collection.name || @"")];
}

- (void)handleDidViewModeChanged:(id)sender
{
    [self refreshDIDView];
}

- (void)handlePLCViewModeChanged:(id)sender
{
    [self refreshPLCView];
}

- (void)handleRecordModeChanged:(id)sender
{
    [self refreshRecordDetailView];
}

- (void)handleLoadFeed:(id)sender
{
    [self loadFeedForCurrentMode];
}

- (void)handleFeedViewModeChanged:(id)sender
{
    [self refreshFeedView];
}

- (void)handleLoadGraph:(id)sender
{
    [self loadGraphFollows];
}

- (void)handleLoadProfile:(id)sender
{
    [self loadActorProfile];
}

- (void)handleProfileViewModeChanged:(id)sender
{
    [self refreshProfileView];
}

- (void)handleLoadMST:(id)sender
{
    [self loadMSTBundleForDid:[self activeMSTDid]];
}

- (void)handleToggleMSTTree:(id)sender
{
    if (!_currentMSTTreePayload)
    {
        [self setStatus:@"Load MST data first."];
        return;
    }

    _mstExpanded = !_mstExpanded;
    [self refreshMSTViews];
    [self setStatus:(_mstExpanded ? @"MST tree expanded (JSON view)." : @"MST tree collapsed (table view).")];
}

- (void)handleExportMST:(id)sender
{
    [self exportMSTForDid:[self activeMSTDid] format:[_mstExportFormatPopup titleOfSelectedItem]];
}

- (void)handleCIDDecode:(id)sender
{
    [self decodeCID];
}

- (void)handleOpenDocs:(id)sender
{
    [self openAPIDocs];
}

- (void)handleOpenPLCExplorer:(id)sender
{
    [self openPLCURL:[self plcBaseURL] label:@"PLC explorer"];
}

- (void)handleOpenPLCMetrics:(id)sender
{
    [self openPLCURL:([self plcBaseURL] + @"/_metrics") label:@"PLC metrics"];
}

- (void)handleResolveHandle:(id)sender
{
    [self resolveOAuthHandle:[_oauthHandleField stringValue]];
}

- (void)handleStartOAuthLogin:(id)sender
{
    [self startOAuthLoginWithHandle:[self trimmedString:[_oauthHandleField stringValue]]];
}

- (void)handleLogoutOAuth:(id)sender
{
    [self logoutOAuthSession];
}

- (void)handleTestOAuthSession:(id)sender
{
    [self testOAuthSession];
}

- (void)handleLoadRecentPosts:(id)sender
{
    [self loadRecentPostsForOAuthSession];
}

- (void)handleCreatePost:(id)sender
{
    [self createOAuthPostWithText:[_postTextField stringValue]
                         replyURI:[_postReplyField stringValue]];
}

#pragma mark - CPTableView Data Source

- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    if (tableView === _accountsTable)
        return _accounts ? _accounts.length : 0;
    if (tableView === _collectionsTable)
        return _collections ? _collections.length : 0;
    if (tableView === _recordsTable)
        return _records ? _records.length : 0;
    if (tableView === _didSummaryTable)
        return _didSummaryRows ? _didSummaryRows.length : 0;
    if (tableView === _didItemsTable)
        return _didItemRows ? _didItemRows.length : 0;
    if (tableView === _plcOpsTable)
        return _plcOpRows ? _plcOpRows.length : 0;
    if (tableView === _plcDetailTable)
        return _plcDetailRows ? _plcDetailRows.length : 0;
    if (tableView === _recordSummaryTable)
        return _recordSummaryRows ? _recordSummaryRows.length : 0;
    if (tableView === _feedTable)
        return _feedRows ? _feedRows.length : 0;
    if (tableView === _feedDetailTable)
        return _feedDetailRows ? _feedDetailRows.length : 0;
    if (tableView === _graphTable)
        return _graphRows ? _graphRows.length : 0;
    if (tableView === _graphDetailTable)
        return _graphDetailRows ? _graphDetailRows.length : 0;
    if (tableView === _profileSummaryTable)
        return _profileSummaryRows ? _profileSummaryRows.length : 0;
    if (tableView === _mstStatsTable)
        return _mstStatsRows ? _mstStatsRows.length : 0;
    if (tableView === _mstNodesTable)
        return _mstNodeRows ? _mstNodeRows.length : 0;
    return 0;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (tableView === _accountsTable)
    {
        var account = _accounts[row];
        return account ? (account.handle || account.did || @"") : @"";
    }

    if (tableView === _collectionsTable)
    {
        var collection = _collections[row];
        if (!collection)
            return @"";

        if ([[tableColumn identifier] isEqual:@"count"])
            return collection.count || @"";
        return collection.name || @"";
    }

    if (tableView === _recordsTable)
    {
        var record = _records[row];
        if (!record)
            return @"";

        var identifier = [tableColumn identifier];
        if ([identifier isEqual:@"rkey"])
            return record.rkey || [self rkeyFromRecordURI:record.uri] || @"";
        if ([identifier isEqual:@"cid"])
            return record.cid || @"";
        if ([identifier isEqual:@"uri"])
            return record.uri || @"";
    }

    if (tableView === _didSummaryTable)
    {
        var didSummaryRow = _didSummaryRows[row] || {},
            didSummaryIdentifier = [tableColumn identifier];
        if ([didSummaryIdentifier isEqual:@"did_summary_field"])
            return didSummaryRow.field || @"";
        if ([didSummaryIdentifier isEqual:@"did_summary_value"])
            return didSummaryRow.value || @"";
    }

    if (tableView === _didItemsTable)
    {
        var didItemRow = _didItemRows[row] || {},
            didItemIdentifier = [tableColumn identifier];
        if ([didItemIdentifier isEqual:@"did_item_type"])
            return didItemRow.type || @"";
        if ([didItemIdentifier isEqual:@"did_item_label"])
            return didItemRow.label || @"";
        if ([didItemIdentifier isEqual:@"did_item_value"])
            return didItemRow.value || @"";
    }

    if (tableView === _plcOpsTable)
    {
        var plcOpRow = _plcOpRows[row] || {},
            plcOpIdentifier = [tableColumn identifier];
        if ([plcOpIdentifier isEqual:@"plc_op_when"])
            return plcOpRow.when || @"";
        if ([plcOpIdentifier isEqual:@"plc_op_summary"])
            return plcOpRow.summary || @"";
        if ([plcOpIdentifier isEqual:@"plc_op_details"])
            return plcOpRow.details || @"";
    }

    if (tableView === _plcDetailTable)
    {
        var plcDetailRow = _plcDetailRows[row] || {},
            plcDetailIdentifier = [tableColumn identifier];
        if ([plcDetailIdentifier isEqual:@"plc_detail_field"])
            return plcDetailRow.field || @"";
        if ([plcDetailIdentifier isEqual:@"plc_detail_value"])
            return plcDetailRow.value || @"";
    }

    if (tableView === _recordSummaryTable)
    {
        var recordRow = _recordSummaryRows[row] || {},
            recordIdentifier = [tableColumn identifier];
        if ([recordIdentifier isEqual:@"record_field"])
            return recordRow.field || @"";
        if ([recordIdentifier isEqual:@"record_value"])
            return recordRow.value || @"";
    }

    if (tableView === _feedTable)
    {
        var feedRow = _feedRows[row] || {},
            feedIdentifier = [tableColumn identifier];
        if ([feedIdentifier isEqual:@"feed_type"])
            return feedRow.type || @"";
        if ([feedIdentifier isEqual:@"feed_actor"])
            return feedRow.actor || @"";
        if ([feedIdentifier isEqual:@"feed_primary"])
            return feedRow.primary || @"";
        if ([feedIdentifier isEqual:@"feed_created"])
            return feedRow.createdAt || @"";
    }

    if (tableView === _feedDetailTable)
    {
        var feedDetailRow = _feedDetailRows[row] || {},
            feedDetailIdentifier = [tableColumn identifier];
        if ([feedDetailIdentifier isEqual:@"feed_detail_field"])
            return feedDetailRow.field || @"";
        if ([feedDetailIdentifier isEqual:@"feed_detail_value"])
            return feedDetailRow.value || @"";
    }

    if (tableView === _graphTable)
    {
        var graphRow = _graphRows[row] || {},
            graphIdentifier = [tableColumn identifier];
        if ([graphIdentifier isEqual:@"graph_handle"])
            return graphRow.handle || @"";
        if ([graphIdentifier isEqual:@"graph_did"])
            return graphRow.did || @"";
        if ([graphIdentifier isEqual:@"graph_display_name"])
            return graphRow.displayName || @"";
        if ([graphIdentifier isEqual:@"graph_created"])
            return graphRow.createdAt || @"";
    }

    if (tableView === _graphDetailTable)
    {
        var graphDetailRow = _graphDetailRows[row] || {},
            graphDetailIdentifier = [tableColumn identifier];
        if ([graphDetailIdentifier isEqual:@"graph_detail_field"])
            return graphDetailRow.field || @"";
        if ([graphDetailIdentifier isEqual:@"graph_detail_value"])
            return graphDetailRow.value || @"";
    }

    if (tableView === _profileSummaryTable)
    {
        var profileRow = _profileSummaryRows[row] || {},
            profileIdentifier = [tableColumn identifier];
        if ([profileIdentifier isEqual:@"profile_field"])
            return profileRow.field || @"";
        if ([profileIdentifier isEqual:@"profile_value"])
            return profileRow.value || @"";
    }

    if (tableView === _mstStatsTable)
    {
        var mstStatsRow = _mstStatsRows[row] || {},
            mstStatsIdentifier = [tableColumn identifier];
        if ([mstStatsIdentifier isEqual:@"mst_metric"])
            return mstStatsRow.field || @"";
        if ([mstStatsIdentifier isEqual:@"mst_metric_value"])
            return mstStatsRow.value || @"";
    }

    if (tableView === _mstNodesTable)
    {
        var mstNodeRow = _mstNodeRows[row] || {},
            mstNodeIdentifier = [tableColumn identifier];
        if ([mstNodeIdentifier isEqual:@"mst_node_level"])
            return mstNodeRow.level || @"";
        if ([mstNodeIdentifier isEqual:@"mst_node_kind"])
            return mstNodeRow.kind || @"";
        if ([mstNodeIdentifier isEqual:@"mst_node_entries"])
            return mstNodeRow.entries || @"";
        if ([mstNodeIdentifier isEqual:@"mst_node_left"])
            return mstNodeRow.left || @"";
        if ([mstNodeIdentifier isEqual:@"mst_node_cid"])
            return mstNodeRow.cid || @"";
    }

    return @"";
}

#pragma mark - CPTableView Delegate

- (void)tableViewSelectionDidChange:(CPNotification)notification
{
    var tableView = [notification object];

    if (tableView === _accountsTable)
    {
        var accountRow = [_accountsTable selectedRow];
        if (accountRow >= 0)
            [self selectAccountAtRow:accountRow];
        return;
    }

    if (tableView === _collectionsTable)
    {
        var collectionRow = [_collectionsTable selectedRow];
        if (collectionRow >= 0 && collectionRow < _collections.length)
            _selectedCollection = _collections[collectionRow].name || @"";
        return;
    }

    if (tableView === _recordsTable)
    {
        var recordRow = [_recordsTable selectedRow];
        if (recordRow >= 0)
            [self loadRecordDetailForRow:recordRow];
        return;
    }

    if (tableView === _feedTable)
    {
        [self refreshFeedSelectionDetail];
        return;
    }

    if (tableView === _plcOpsTable)
    {
        [self refreshPLCSelectionDetail];
        return;
    }

    if (tableView === _graphTable)
    {
        [self refreshGraphDetailView];
        return;
    }
}

@end
