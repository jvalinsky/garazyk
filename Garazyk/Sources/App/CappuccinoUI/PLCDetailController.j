/*
 * PLCDetailController.j
 * CappuccinoUI
 *
 * DID document viewer - displays identity details,
 * services, verification methods, and raw document.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"
@import "EmptyStateView.j"

@implementation PLCDetailController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    EmptyStateView _emptyState;
    CPTextField _didLabel;
    CPScrollView _contentScrollView;
    CPView _contentView;

    CPDictionary _didDocument;
    CPArray _operationLog;
    CPString _currentDID;
}

- (id)initWithSessionState:(SessionState)sessionState apiClient:(UIAPIClient)apiClient
{
    self = [super init];
    if (self)
    {
        _sessionState = sessionState;
        _apiClient = apiClient;
        _didDocument = nil;
        _operationLog = nil;
        _currentDID = nil;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];
    [_rootView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

    // Title
    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 400.0, 28.0)];
    [title setStringValue:@"Identity Details"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];
    [_rootView addSubview:title];

    // DID label
    _didLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 800.0, 24.0)];
    [_didLabel setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [_didLabel setEditable:NO];
    [_didLabel setBezeled:NO];
    [_didLabel setDrawsBackground:NO];
    [_didLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_didLabel setTextColor:[CPColor colorWithCalibratedRed:0.2 green:0.4 blue:0.8 alpha:1.0]];
    [_didLabel setStringValue:@"Select a DID to view details"];
    [_rootView addSubview:_didLabel];

    // Status label
    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 68.0, 600.0, 20.0)];
    [_statusLabel setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@""];
    [_rootView addSubview:_statusLabel];

    // Content area
    _contentScrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 96.0, 1040.0, 580.0)];
    [_contentScrollView setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];
    [_contentScrollView setHasHorizontalScroller:NO];
    [_contentScrollView setHasVerticalScroller:YES];
    [_contentScrollView setAutohidesScrollers:YES];
    _contentView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 580.0)];
    [_contentView setWantsLayer:YES];
    [_contentScrollView setDocumentView:_contentView];
    [_rootView addSubview:_contentScrollView];

    return _rootView;
}

- (void)loadDID:(CPString)did
{
    _currentDID = did;
    [_didLabel setStringValue:did];
    [_statusLabel setStringValue:@"Loading..."];
    [self hideEmptyState];

    // Clear content (iterate in reverse for safety)
    var subviews = [_contentView subviews];
    for (var i = subviews.length - 1; i >= 0; i--) {
        [subviews[i] removeFromSuperview];
    }

    // Fetch DID document and operation log in parallel
    var pending = 2;
    var errorOccurred = NO;
    var checkComplete = function() {
        pending--;
        if (pending === 0 && !errorOccurred) {
            [self renderDocument];
        }
    };

    [_apiClient fetch:@"GET" path:@"/" + did params:nil completion:function(response, error) {
        if (error) {
            [_statusLabel setStringValue:@"Error loading DID: " + error.localizedDescription];
            errorOccurred = YES;
            [self showEmptyStateWithIcon:EmptyStateIconCloudOff
                                  message:@"Could not reach PLC for " + did + ". " + error.localizedDescription];
            return;
        }
        _didDocument = response;
        checkComplete();
    }];

    [_apiClient fetch:@"GET" path:@"/" + did + "/log" params:nil completion:function(response, error) {
        if (error) {
            _operationLog = [];
        } else {
            _operationLog = response || [];
        }
        checkComplete();
    }];
}

#pragma mark - Empty State Helpers

- (void)showEmptyStateWithIcon:(CPString)icon message:(CPString)message
{
    if (!_rootView)
        return;

    if (!_emptyState)
        _emptyState = [[EmptyStateView alloc] initWithFrame:[_contentScrollView bounds]
                                                        icon:icon
                                                     message:message
                                                  actionTitle:@"Try Again"
                                                actionHandler:function() { [self loadDID:_currentDID]; }];

    [_emptyState setIcon:icon];
    [_emptyState setMessage:message];

    var frame = [_rootView bounds];
    if (_contentScrollView)
        frame = [_contentScrollView frame];
        
    [_emptyState setFrame:frame];
    [_emptyState showInView:_rootView];
}

- (void)hideEmptyState
{
    if (_emptyState)
        [_emptyState hide];
}

- (void)renderDocument
{
    if (!_didDocument) {
        [_statusLabel setStringValue:@"No document found"];
        return;
    }

    [_statusLabel setStringValue:@"Loaded"];

    var yOffset = 0.0;

    // Identifies As section
    yOffset = [self renderHandlesSection:yOffset];

    // Services section
    yOffset = [self renderServicesSection:yOffset];

    // Verification Methods section
    yOffset = [self renderVerificationMethodsSection:yOffset];

    // Operation count
    yOffset = [self renderOperationCount:yOffset];

    // Raw JSON
    yOffset = [self renderRawJSON:yOffset];

    var contentWidth = [self contentWidthForLayout];
    [_contentView setFrame:CGRectMake(0.0, 0.0, contentWidth, yOffset + 12.0)];
}

- (float)renderHandlesSection:(float)yOffset
{
    var handles = _didDocument[@"alsoKnownAs"] || [];
    var hasHandles = handles.length > 0,
        contentWidth = [self contentWidthForLayout];

    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Identifies As"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_contentView addSubview:sectionLabel];
    yOffset += 24.0;

    if (hasHandles) {
        var handlesText = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 24.0 * handles.length)];
        [handlesText setEditable:NO];
        [handlesText setBezeled:NO];
        [handlesText setDrawsBackground:NO];
        [handlesText setFont:[CPFont systemFontOfSize:12.0]];

        var handlesStr = "";
        for (var i = 0; i < handles.length; i++) {
            var h = handles[i];
            // Format: at://handle -> @handle
            if (h.indexOf("at://") === 0) {
                h = "@" + h.substring(5);
            }
            handlesStr += h + "\n";
        }
        [handlesText setStringValue:handlesStr];
        [_contentView addSubview:handlesText];
        yOffset += 24.0 * handles.length + 8.0;
    } else {
        var noHandles = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 24.0)];
        [noHandles setStringValue:@"No handles registered"];
        [noHandles setEditable:NO];
        [noHandles setBezeled:NO];
        [noHandles setDrawsBackground:NO];
        [noHandles setFont:[CPFont systemFontOfSize:12.0]];
        [noHandles setTextColor:[CPColor grayColor]];
        [_contentView addSubview:noHandles];
        yOffset += 32.0;
    }

    return yOffset;
}

- (float)renderServicesSection:(float)yOffset
{
    var services = _didDocument[@"service"] || [],
        contentWidth = [self contentWidthForLayout];

    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Services"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_contentView addSubview:sectionLabel];
    yOffset += 24.0;

    if (services.length > 0) {
        for (var i = 0; i < services.length; i++) {
            var svc = services[i];
            var svcId = svc[@"id"] || "";
            var svcType = svc[@"type"] || "";
            var endpoint = svc[@"serviceEndpoint"] || "";
            if (typeof endpoint !== "string" && endpoint[@"uri"]) {
                endpoint = endpoint[@"uri"];
            }

            // Extract short ID
            var shortId = svcId;
            if (svcId.indexOf("#") !== -1) {
                shortId = svcId.split("#")[1];
            }

            var row = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 18.0)];
            [row setStringValue:shortId + " | " + svcType + " | " + endpoint];
            [row setEditable:NO];
            [row setBezeled:NO];
            [row setDrawsBackground:NO];
            [row setFont:[CPFont systemFontOfSize:11.0]];
            [_contentView addSubview:row];
            yOffset += 22.0;
        }
    } else {
        var noServices = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 24.0)];
        [noServices setStringValue:@"No services registered"];
        [noServices setEditable:NO];
        [noServices setBezeled:NO];
        [noServices setDrawsBackground:NO];
        [noServices setFont:[CPFont systemFontOfSize:12.0]];
        [noServices setTextColor:[CPColor grayColor]];
        [_contentView addSubview:noServices];
        yOffset += 32.0;
    }

    return yOffset;
}

- (float)renderVerificationMethodsSection:(float)yOffset
{
    var methods = _didDocument[@"verificationMethod"] || [],
        contentWidth = [self contentWidthForLayout];

    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Verification Methods"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_contentView addSubview:sectionLabel];
    yOffset += 24.0;

    for (var i = 0; i < methods.length; i++) {
        var method = methods[i];
        var methodId = method[@"id"] || "";
        var methodType = method[@"type"] || "";
        var pubkey = method[@"publicKeyMultibase"] || method[@"publicKeyHex"] || "N/A";

        // Extract short ID
        var shortId = methodId;
        if (methodId.indexOf("#") !== -1) {
            shortId = methodId.split("#")[1];
        }

        // Truncate long keys
        if (pubkey.length > 40) {
            pubkey = pubkey.substring(0, 40) + "...";
        }

        var row = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 18.0)];
        [row setStringValue:shortId + " | " + methodType + " | " + pubkey];
        [row setEditable:NO];
        [row setBezeled:NO];
        [row setDrawsBackground:NO];
        [row setFont:[CPFont systemFontOfSize:11.0] withFamily:@"Monaco"];
        [_contentView addSubview:row];
        yOffset += 22.0;
    }

    return yOffset + 16.0;
}

- (float)renderOperationCount:(float)yOffset
{
    var opCount = _operationLog ? _operationLog.length : 0;

    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Operations"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_contentView addSubview:sectionLabel];
    yOffset += 24.0;

    var countText = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, 200.0, 18.0)];
    [countText setStringValue:opCount + " operations in history"];
    [countText setEditable:NO];
    [countText setBezeled:NO];
    [countText setDrawsBackground:NO];
    [countText setFont:[CPFont systemFontOfSize:12.0]];
    [_contentView addSubview:countText];
    yOffset += 32.0;

    return yOffset;
}

- (float)renderRawJSON:(float)yOffset
{
    var contentWidth = [self contentWidthForLayout];
    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, yOffset, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Raw DID Document"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_contentView addSubview:sectionLabel];
    yOffset += 24.0;

    var jsonString = JSON.stringify(_didDocument, null, 2);

    var rawView = [[CPTextView alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 200.0)];
    [rawView setString:jsonString];
    [rawView setEditable:NO];
    [rawView setFont:[CPFont systemFontOfSize:10.0] withFamily:@"Monaco"];
    [rawView setTextColor:[CPColor colorWithCalibratedWhite:0.2 alpha:1.0]];
    [rawView setBackgroundColor:[CPColor colorWithCalibratedWhite:0.97 alpha:1.0]];
    [rawView setAutoresizingMask:CPViewWidthSizable];

    var scroll = [[CPScrollView alloc] initWithFrame:CGRectMake(0.0, yOffset, contentWidth, 200.0)];
    [scroll setAutoresizingMask:CPViewWidthSizable];
    [scroll setDocumentView:rawView];
    [scroll setHasHorizontalScroller:NO];
    [scroll setHasVerticalScroller:YES];
    [_contentView addSubview:scroll];
    yOffset += 216.0;

    return yOffset;
}

- (float)contentWidthForLayout
{
    var width = 800.0;
    if (_contentScrollView)
        width = [_contentScrollView bounds].size.width - 20.0;
    return width > 320.0 ? width : 320.0;
}

@end
