/*
 * MSTController.j
 * CappuccinoUI
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation MSTController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    CPTextField _searchField;
    CPTextField _selectedAccountLabel;
    CPTableView _accountsTable;
    CPPopUpButton _viewModePopup;
    CPPopUpButton _exportFormatPopup;
    CPTextView _statsTextView;
    CPTextView _treeTextView;

    CPArray _accounts;
    CPArray _filteredAccounts;
    id _currentTreePayload;
    id _currentStatsPayload;
    CPString _currentDID;
    CPString _currentViewMode;
    float _zoomScale;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _accounts = [];
        _filteredAccounts = [];
        _currentTreePayload = nil;
        _currentStatsPayload = nil;
        _currentDID = nil;
        _currentViewMode = @"tree";
        _zoomScale = 1.0;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 900.0, 28.0)];
    [title setStringValue:@"MST Viewer"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 1040.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Idle"];

    var searchLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 74.0, 50.0, 18.0)];
    [searchLabel setStringValue:@"Search:"];
    [searchLabel setEditable:NO];
    [searchLabel setBezeled:NO];
    [searchLabel setDrawsBackground:NO];

    _searchField = [[CPTextField alloc] initWithFrame:CGRectMake(72.0, 70.0, 210.0, 24.0)];
    [_searchField setPlaceholderString:@"handle or DID"];

    var searchButton = [[CPButton alloc] initWithFrame:CGRectMake(290.0, 68.0, 72.0, 28.0)];
    [searchButton setTitle:@"Search"];
    [searchButton setTarget:self];
    [searchButton setAction:@selector(handleSearchAccounts:)];

    var clearButton = [[CPButton alloc] initWithFrame:CGRectMake(368.0, 68.0, 60.0, 28.0)];
    [clearButton setTitle:@"Clear"];
    [clearButton setTarget:self];
    [clearButton setAction:@selector(handleClearSearch:)];

    var loadAccountsButton = [[CPButton alloc] initWithFrame:CGRectMake(436.0, 68.0, 116.0, 28.0)];
    [loadAccountsButton setTitle:@"Load Accounts"];
    [loadAccountsButton setTarget:self];
    [loadAccountsButton setAction:@selector(handleLoadAccounts:)];

    var accountsLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 106.0, 120.0, 18.0)];
    [accountsLabel setStringValue:@"Accounts"];
    [accountsLabel setEditable:NO];
    [accountsLabel setBezeled:NO];
    [accountsLabel setDrawsBackground:NO];
    [accountsLabel setFont:[CPFont boldSystemFontOfSize:12.0]];

    _accountsTable = [[CPTableView alloc] initWithFrame:CGRectMake(0.0, 0.0, 300.0, 538.0)];
    [_accountsTable setDelegate:self];
    [_accountsTable setDataSource:self];
    [_accountsTable setAllowsEmptySelection:YES];
    [_accountsTable setAllowsMultipleSelection:NO];

    var accountHandleColumn = [[CPTableColumn alloc] initWithIdentifier:@"account_handle"];
    [[accountHandleColumn headerView] setStringValue:@"Handle"];
    [accountHandleColumn setWidth:140.0];
    [_accountsTable addTableColumn:accountHandleColumn];

    var accountDidColumn = [[CPTableColumn alloc] initWithIdentifier:@"account_did"];
    [[accountDidColumn headerView] setStringValue:@"DID"];
    [accountDidColumn setWidth:160.0];
    [_accountsTable addTableColumn:accountDidColumn];

    var accountsScroll = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 130.0, 300.0, 540.0)];
    [accountsScroll setHasVerticalScroller:YES];
    [accountsScroll setAutohidesScrollers:YES];
    [accountsScroll setDocumentView:_accountsTable];

    _selectedAccountLabel = [[CPTextField alloc] initWithFrame:CGRectMake(340.0, 74.0, 720.0, 18.0)];
    [_selectedAccountLabel setEditable:NO];
    [_selectedAccountLabel setBezeled:NO];
    [_selectedAccountLabel setDrawsBackground:NO];
    [_selectedAccountLabel setStringValue:@"Selected: (none)"];

    var viewModeLabel = [[CPTextField alloc] initWithFrame:CGRectMake(340.0, 106.0, 66.0, 18.0)];
    [viewModeLabel setStringValue:@"View Mode:"];
    [viewModeLabel setEditable:NO];
    [viewModeLabel setBezeled:NO];
    [viewModeLabel setDrawsBackground:NO];

    _viewModePopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(408.0, 102.0, 96.0, 24.0)];
    [_viewModePopup addItemsWithTitles:[@"tree,list" componentsSeparatedByString:@","]];
    [_viewModePopup setTarget:self];
    [_viewModePopup setAction:@selector(handleViewModeChanged:)];

    var loadTreeButton = [[CPButton alloc] initWithFrame:CGRectMake(512.0, 100.0, 120.0, 28.0)];
    [loadTreeButton setTitle:@"Load Tree + Stats"];
    [loadTreeButton setTarget:self];
    [loadTreeButton setAction:@selector(handleLoadSelectedMST:)];

    _exportFormatPopup = [[CPPopUpButton alloc] initWithFrame:CGRectMake(640.0, 102.0, 86.0, 24.0)];
    [_exportFormatPopup addItemsWithTitles:[@"json,dot,svg" componentsSeparatedByString:@","]];

    var exportButton = [[CPButton alloc] initWithFrame:CGRectMake(734.0, 100.0, 76.0, 28.0)];
    [exportButton setTitle:@"Export"];
    [exportButton setTarget:self];
    [exportButton setAction:@selector(handleExport:)];

    var zoomInButton = [[CPButton alloc] initWithFrame:CGRectMake(818.0, 100.0, 36.0, 28.0)];
    [zoomInButton setTitle:@"+"];
    [zoomInButton setTarget:self];
    [zoomInButton setAction:@selector(handleZoomIn:)];

    var zoomOutButton = [[CPButton alloc] initWithFrame:CGRectMake(860.0, 100.0, 36.0, 28.0)];
    [zoomOutButton setTitle:@"-"];
    [zoomOutButton setTarget:self];
    [zoomOutButton setAction:@selector(handleZoomOut:)];

    var zoomResetButton = [[CPButton alloc] initWithFrame:CGRectMake(902.0, 100.0, 64.0, 28.0)];
    [zoomResetButton setTitle:@"Reset"];
    [zoomResetButton setTarget:self];
    [zoomResetButton setAction:@selector(handleZoomReset:)];

    _statsTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(340.0, 130.0, 720.0, 130.0)
                                                    inView:_rootView];
    _treeTextView = [self buildReadOnlyTextViewWithFrame:CGRectMake(340.0, 268.0, 720.0, 402.0)
                                                   inView:_rootView];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];
    [_rootView addSubview:searchLabel];
    [_rootView addSubview:_searchField];
    [_rootView addSubview:searchButton];
    [_rootView addSubview:clearButton];
    [_rootView addSubview:loadAccountsButton];
    [_rootView addSubview:accountsLabel];
    [_rootView addSubview:accountsScroll];
    [_rootView addSubview:_selectedAccountLabel];
    [_rootView addSubview:viewModeLabel];
    [_rootView addSubview:_viewModePopup];
    [_rootView addSubview:loadTreeButton];
    [_rootView addSubview:_exportFormatPopup];
    [_rootView addSubview:exportButton];
    [_rootView addSubview:zoomInButton];
    [_rootView addSubview:zoomOutButton];
    [_rootView addSubview:zoomResetButton];

    [self applyZoomScale];
    [self loadAccounts];

    return _rootView;
}

- (CPTextView)buildReadOnlyTextViewWithFrame:(CGRect)frame inView:(CPView)parent
{
    var textView = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, 0.0, frame.size.width, frame.size.height)];
    [textView setEditable:NO];
    [textView setSelectable:YES];
    [textView setString:@""];
    [textView setFont:[CPFont systemFontOfSize:12.0]];

    var scroll = [[CPScrollView alloc] initWithFrame:frame];
    [scroll setHasVerticalScroller:YES];
    [scroll setAutohidesScrollers:YES];
    [scroll setDocumentView:textView];
    [parent addSubview:scroll];

    return textView;
}

- (void)setStatus:(CPString)message
{
    [_statusLabel setStringValue:(message || @"")];
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
    return String(value).replace(/^\s+|\s+$/g, "");
}

- (CPString)safeString:(id)value
{
    if (value === nil || value === undefined)
        return @"";
    if (typeof value === "string")
        return value;
    return String(value);
}

- (CPString)abbreviatedString:(id)value maxLength:(int)maxLength
{
    var stringValue = [self safeString:value];
    if (!stringValue || stringValue.length <= maxLength)
        return stringValue;
    return stringValue.substring(0, maxLength - 3) + "...";
}

- (CPString)prettyJSON:(id)object
{
    if (object === nil || object === undefined)
        return @"";

    try
    {
        return JSON.stringify(object, null, 2);
    }
    catch (e)
    {
        return String(object);
    }
}

- (void)applyAccountFilter
{
    var query = [[self trimmedString:[_searchField stringValue]] lowercaseString];
    if (!query || query.length === 0)
    {
        _filteredAccounts = _accounts.slice(0);
        [_accountsTable reloadData];
        return;
    }

    _filteredAccounts = [];
    for (var i = 0; i < _accounts.length; i++)
    {
        var account = _accounts[i];
        if (!account)
            continue;

        var handle = (account.handle || @"").toLowerCase(),
            did = (account.did || @"").toLowerCase();

        if (handle.indexOf(query) >= 0 || did.indexOf(query) >= 0)
            _filteredAccounts.push(account);
    }

    [_accountsTable reloadData];
}

- (void)loadAccounts
{
    [self setStatus:@"Loading MST accounts..."];
    [_apiClient getJSONWithPath:@"/accounts"
                  endpointGroup:@"mst"
                    queryParams:nil
                     completion:function(statusCode, payload, errorMessage)
                     {
                         if (errorMessage || !(statusCode >= 200 && statusCode < 300))
                         {
                             [self setStatus:[@"Failed to load accounts: " stringByAppendingString:(errorMessage || @"Unknown error")]];
                             _accounts = [];
                             _filteredAccounts = [];
                             [_accountsTable reloadData];
                             return;
                         }

                         _accounts = (payload && payload.accounts) ? payload.accounts : [];
                         [self applyAccountFilter];
                         [self setStatus:[@"Loaded MST accounts: " stringByAppendingString:String(_accounts.length)]];
                     }];
}

- (id)selectedAccount
{
    var row = [_accountsTable selectedRow];
    if (row < 0 || row >= _filteredAccounts.length)
        return nil;
    return _filteredAccounts[row];
}

- (void)updateSelectedAccountLabel
{
    if (!_currentDID || _currentDID.length === 0)
    {
        [_selectedAccountLabel setStringValue:@"Selected: (none)"];
        return;
    }

    var handle = nil;
    for (var i = 0; i < _accounts.length; i++)
    {
        var account = _accounts[i];
        if (account && account.did === _currentDID)
        {
            handle = account.handle;
            break;
        }
    }

    var summary = handle ? (handle + " (" + _currentDID + ")") : _currentDID;
    [_selectedAccountLabel setStringValue:@"Selected: " + summary];
}

- (CPString)renderMSTStatsSummary
{
    if (!_currentStatsPayload && !_currentTreePayload)
        return @"";

    if (_currentStatsPayload && _currentStatsPayload.error)
        return @"Error: " + _currentStatsPayload.error;

    var stats = _currentStatsPayload || {},
        tree = _currentTreePayload || {},
        lines = [];

    lines.push("DID: " + [self safeString:_currentDID]);
    lines.push("Nodes: " + [self safeString:(stats.nodeCount !== undefined ? stats.nodeCount : tree.nodeCount)]);
    lines.push("Entries: " + [self safeString:(stats.entryCount !== undefined ? stats.entryCount : tree.entryCount)]);
    lines.push("Depth: " + [self safeString:(stats.maxDepth !== undefined ? stats.maxDepth : tree.maxDepth)]);

    if (stats.leafNodeCount !== undefined)
        lines.push("Leaf Nodes: " + [self safeString:stats.leafNodeCount]);
    if (stats.balanceFactor !== undefined)
        lines.push("Balance Factor: " + [self safeString:stats.balanceFactor]);
    if (tree.rootCID)
        lines.push("Root CID: " + [self safeString:tree.rootCID]);

    lines.push("");
    lines.push("Raw stats:");
    lines.push([self prettyJSON:stats]);
    return lines.join("\n");
}

- (CPString)renderMSTTreeSummary:(id)treePayload
{
    if (!treePayload)
        return @"";
    if (treePayload.error)
        return @"Error: " + treePayload.error;

    var nodes = treePayload.nodes;
    if (!nodes || nodes.length === undefined)
        return [self prettyJSON:treePayload];

    var lines = [];
    lines.push("MST Tree Summary");
    lines.push("Root CID: " + [self safeString:treePayload.rootCID]);
    lines.push("Nodes: " + [self safeString:treePayload.nodeCount]);
    lines.push("Entries: " + [self safeString:treePayload.entryCount]);
    lines.push("Depth: " + [self safeString:treePayload.maxDepth]);
    lines.push("");
    lines.push("Nodes (first " + Math.min(nodes.length, 140) + "):");

    for (var i = 0; i < nodes.length && i < 140; i++)
    {
        var node = nodes[i] || {},
            level = (node.level === nil || node.level === undefined) ? @"?" : String(node.level),
            kind = node.kind || ((node.level === 0) ? @"leaf" : @"internal"),
            entryCount = (node.entries && node.entries.length !== undefined) ? node.entries.length : 0;

        lines.push((i + 1) + ". L" + level
                 + " " + kind
                 + " entries=" + entryCount
                 + " left=" + (node.left ? "yes" : "no")
                 + " cid=" + [self abbreviatedString:node.cid maxLength:24]);
    }

    if (nodes.length > 140)
        lines.push("... " + (nodes.length - 140) + " additional node(s) omitted.");

    return lines.join("\n");
}

- (CPString)renderMSTListSummary:(id)treePayload
{
    if (!treePayload)
        return @"";
    if (treePayload.error)
        return @"Error: " + treePayload.error;

    var nodes = treePayload.nodes;
    if (!nodes || nodes.length === undefined)
        return [self prettyJSON:treePayload];

    var lines = [];
    lines.push("MST Node List");
    lines.push("=============");
    lines.push("");

    for (var i = 0; i < nodes.length && i < 60; i++)
    {
        var node = nodes[i] || {},
            level = (node.level === nil || node.level === undefined) ? @"?" : String(node.level),
            entries = node.entries || [];

        lines.push("Node " + (i + 1) + ": " + [self safeString:node.cid]);
        lines.push("  level=" + level + " kind=" + [self safeString:node.kind || @"unknown"]);
        lines.push("  left=" + [self safeString:node.left]);
        lines.push("  entries=" + [self safeString:entries.length]);

        for (var j = 0; j < entries.length && j < 6; j++)
        {
            var entry = entries[j] || {};
            lines.push("    - key=" + [self safeString:(entry.fullKey || entry.key)]
                     + " value=" + [self abbreviatedString:entry.value maxLength:22]
                     + " tree=" + [self abbreviatedString:entry.tree maxLength:22]);
        }

        if (entries.length > 6)
            lines.push("    ... " + (entries.length - 6) + " more entries");

        lines.push("");
    }

    if (nodes.length > 60)
        lines.push("... " + (nodes.length - 60) + " additional nodes omitted.");

    return lines.join("\n");
}

- (void)refreshMSTViews
{
    [self setTextView:_statsTextView content:[self renderMSTStatsSummary]];

    if (!_currentTreePayload)
    {
        [self setTextView:_treeTextView content:@""];
        return;
    }

    if ([_currentViewMode isEqual:@"list"])
        [self setTextView:_treeTextView content:[self renderMSTListSummary:_currentTreePayload]];
    else
        [self setTextView:_treeTextView content:[self renderMSTTreeSummary:_currentTreePayload]];
}

- (void)loadMSTForDid:(CPString)did
{
    var trimmedDid = [self trimmedString:did];
    if (!trimmedDid || trimmedDid.length === 0)
    {
        [self setStatus:@"Select an account first."];
        return;
    }

    _currentDID = trimmedDid;
    [self updateSelectedAccountLabel];

    [self setStatus:@"Loading MST tree and stats..."];
    [self setTextView:_statsTextView content:@"Loading stats..."];
    [self setTextView:_treeTextView content:@"Loading tree..."];

    var encodedDid = encodeURIComponent(String(trimmedDid)),
        pending = 2,
        treePayload = nil,
        statsPayload = nil,
        sawError = NO,
        complete = function()
        {
            pending -= 1;
            if (pending > 0)
                return;

            _currentTreePayload = treePayload;
            _currentStatsPayload = statsPayload;
            [self refreshMSTViews];

            if (treePayload && treePayload.error)
                [self setStatus:@"Failed to load MST tree."];
            else if (sawError)
                [self setStatus:@"Loaded MST tree with partial stats data."];
            else
                [self setStatus:@"Loaded MST tree and stats for " + trimmedDid + "."];
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

- (void)applyZoomScale
{
    var fontSize = 12.0 * _zoomScale;
    if (fontSize < 8.0)
        fontSize = 8.0;
    if (fontSize > 24.0)
        fontSize = 24.0;

    if (_treeTextView)
        [_treeTextView setFont:[CPFont systemFontOfSize:fontSize]];
    if (_statsTextView)
        [_statsTextView setFont:[CPFont systemFontOfSize:fontSize]];
}

- (void)downloadText:(CPString)text fileName:(CPString)fileName mimeType:(CPString)mimeType
{
    if (!(window && window.document && window.Blob && window.URL && window.URL.createObjectURL))
        return;

    var blob = new Blob([String(text || @"")], {type: String(mimeType || @"text/plain;charset=utf-8")}),
        objectURL = window.URL.createObjectURL(blob),
        doc = window.document,
        anchor = doc.createElement("a");

    anchor.href = objectURL;
    anchor.download = String(fileName || @"mst-export.txt");
    doc.body.appendChild(anchor);
    anchor.click();
    doc.body.removeChild(anchor);
    window.setTimeout(function()
    {
        window.URL.revokeObjectURL(objectURL);
    }, 0);
}

- (void)exportMSTForCurrentDidWithFormat:(CPString)format
{
    if (!_currentDID || _currentDID.length === 0)
    {
        [self setStatus:@"Select and load an account first."];
        return;
    }

    var normalizedFormat = [(format || @"json") lowercaseString],
        encodedDid = encodeURIComponent(String(_currentDID)),
        urlString = [_apiClient URLStringForPath:("/export/" + encodedDid)
                                    endpointGroup:@"mst"
                                     queryParams:{format: normalizedFormat}],
        xhr = new XMLHttpRequest();

    [self setStatus:@"Exporting MST (" + normalizedFormat + ")..."];
    xhr.open("GET", String(urlString), YES);
    xhr.setRequestHeader("Accept", "application/json, text/plain");
    xhr.onreadystatechange = function()
    {
        if (xhr.readyState !== 4)
            return;

        if (xhr.status < 200 || xhr.status >= 300)
        {
            var errorPayload = nil;
            try
            {
                errorPayload = JSON.parse(xhr.responseText || "{}");
            }
            catch (e)
            {
            }
            var message = (errorPayload && (errorPayload.error || errorPayload.message)) || ("HTTP " + xhr.status);
            [self setStatus:@"MST export failed: " + message];
            return;
        }

        var responseText = xhr.responseText || "",
            extension = normalizedFormat,
            mimeType = @"text/plain;charset=utf-8",
            exportText = responseText;

        if ([normalizedFormat isEqual:@"json"])
        {
            mimeType = @"application/json;charset=utf-8";
            try
            {
                exportText = JSON.stringify(JSON.parse(responseText), null, 2);
            }
            catch (e)
            {
            }
        }
        else if ([normalizedFormat isEqual:@"dot"])
        {
            extension = @"dot";
            mimeType = @"text/plain;charset=utf-8";
        }
        else if ([normalizedFormat isEqual:@"svg"])
        {
            extension = @"dot";
            mimeType = @"text/plain;charset=utf-8";
            try
            {
                var parsed = JSON.parse(responseText);
                if (parsed && parsed.content)
                    exportText = parsed.content;
            }
            catch (e)
            {
            }
        }

        var safeDid = [self safeString:_currentDID].replace(/[^a-zA-Z0-9._-]/g, "_"),
            fileName = "mst-" + (safeDid.length ? safeDid : "export") + "." + extension;
        [self downloadText:exportText fileName:fileName mimeType:mimeType];
        [self setStatus:@"Export downloaded: " + fileName];
    };

    xhr.onerror = function()
    {
        [self setStatus:@"MST export failed: network error"];
    };

    xhr.send(null);
}

#pragma mark - Actions

- (void)handleSearchAccounts:(id)sender
{
    [self applyAccountFilter];
}

- (void)handleClearSearch:(id)sender
{
    [_searchField setStringValue:@""];
    [self applyAccountFilter];
}

- (void)handleLoadAccounts:(id)sender
{
    [self loadAccounts];
}

- (void)handleViewModeChanged:(id)sender
{
    _currentViewMode = [_viewModePopup titleOfSelectedItem] || @"tree";
    [self refreshMSTViews];
}

- (void)handleLoadSelectedMST:(id)sender
{
    var account = [self selectedAccount];
    if (!account)
    {
        [self setStatus:@"Select an account first."];
        return;
    }

    [self loadMSTForDid:(account.did || @"")];
}

- (void)handleExport:(id)sender
{
    [self exportMSTForCurrentDidWithFormat:[_exportFormatPopup titleOfSelectedItem]];
}

- (void)handleZoomIn:(id)sender
{
    _zoomScale = Math.min(2.5, _zoomScale + 0.15);
    [self applyZoomScale];
    [self setStatus:@"Zoom: " + Math.round(_zoomScale * 100) + "%"];
}

- (void)handleZoomOut:(id)sender
{
    _zoomScale = Math.max(0.5, _zoomScale - 0.15);
    [self applyZoomScale];
    [self setStatus:@"Zoom: " + Math.round(_zoomScale * 100) + "%"];
}

- (void)handleZoomReset:(id)sender
{
    _zoomScale = 1.0;
    [self applyZoomScale];
    [self setStatus:@"Zoom reset to 100%"];
}

#pragma mark - CPTableView Data Source

- (int)numberOfRowsInTableView:(CPTableView)tableView
{
    if (tableView === _accountsTable)
        return _filteredAccounts.length;
    return 0;
}

- (id)tableView:(CPTableView)tableView objectValueForTableColumn:(CPTableColumn)tableColumn row:(int)row
{
    if (tableView !== _accountsTable)
        return @"";

    var account = _filteredAccounts[row],
        identifier = [tableColumn identifier];
    if ([identifier isEqual:@"account_handle"])
        return account ? (account.handle || @"") : @"";
    if ([identifier isEqual:@"account_did"])
        return account ? [self abbreviatedString:(account.did || @"") maxLength:32] : @"";
    return @"";
}

#pragma mark - CPTableView Delegate

- (void)tableViewSelectionDidChange:(CPNotification)notification
{
    var tableView = [notification object];
    if (tableView !== _accountsTable)
        return;

    var account = [self selectedAccount];
    if (!account)
    {
        _currentDID = nil;
        [self updateSelectedAccountLabel];
        return;
    }

    _currentDID = account.did || nil;
    [self updateSelectedAccountLabel];
    [self loadMSTForDid:_currentDID];
}

@end
