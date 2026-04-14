/*
 * PLCTimelineController.j
 * CappuccinoUI
 *
 * Operation timeline viewer - displays PLC operation history
 * with diff visualization between operations.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation PLCTimelineController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;
    CPTextField _didLabel;
    CPScrollView _scrollView;
    CPView _timelineView;

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
        _operationLog = [];
        _currentDID = nil;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    // Title
    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 400.0, 28.0)];
    [title setStringValue:@"Operation Timeline"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];
    [_rootView addSubview:title];

    // DID label
    _didLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 800.0, 24.0)];
    [_didLabel setEditable:NO];
    [_didLabel setBezeled:NO];
    [_didLabel setDrawsBackground:NO];
    [_didLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [_didLabel setTextColor:[CPColor colorWithCalibratedRed:0.2 green:0.4 blue:0.8 alpha:1.0]];
    [_didLabel setStringValue:@"Select a DID to view timeline"];
    [_rootView addSubview:_didLabel];

    // Status label
    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 68.0, 600.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@""];
    [_rootView addSubview:_statusLabel];

    // Timeline scroll view
    _scrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(20.0, 96.0, 1040.0, 580.0)];
    [_scrollView setHasHorizontalScroller:NO];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setAutohidesScroller:YES];

    _timelineView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1020.0, 100.0)];
    [_scrollView setDocumentView:_timelineView];
    [_rootView addSubview:_scrollView];

    return _rootView;
}

- (void)loadDID:(CPString)did
{
    _currentDID = did;
    [_didLabel setStringValue:did];
    [_statusLabel setStringValue:@"Loading timeline..."];

    // Clear timeline
    var subviews = [_timelineView subviews];
    for (var i = 0; i < subviews.length; i++) {
        [subviews[i] removeFromSuperview];
    }

    [_apiClient fetch:@"GET" path:@"/" + did + "/log" params:nil completion:function(response, error) {
        if (error) {
            [_statusLabel setStringValue:@"Error loading timeline: " + error.localizedDescription];
            return;
        }

        _operationLog = response || [];
        [_statusLabel setStringValue:_operationLog.length + " operations"];

        [self renderTimeline];
    }];
}

- (void)renderTimeline
{
    if (_operationLog.length === 0) {
        var emptyLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 20.0, 400.0, 24.0)];
        [emptyLabel setStringValue:@"No operations found"];
        [emptyLabel setEditable:NO];
        [emptyLabel setBezeled:NO];
        [emptyLabel setDrawsBackground:NO];
        [emptyLabel setFont:[CPFont systemFontOfSize:14.0]];
        [emptyLabel setTextColor:[CPColor grayColor]];
        [_timelineView addSubview:emptyLabel];
        return;
    }

    // Sort by date (oldest first)
    var sortedLog = [[CPArray alloc] init];
    var logArray = _operationLog;

    // Sort by createdAt
    var sorted = logArray.sort(function(a, b) {
        var dateA = new Date(a.createdAt || 0);
        var dateB = new Date(b.createdAt || 0);
        return dateA - dateB;
    });

    var yOffset = 20.0;
    var prevOp = nil;

    for (var i = 0; i < sorted.length; i++) {
        var entry = sorted[i];
        var op = entry.op || entry;
        var date = entry.createdAt || "Unknown Date";
        var cid = entry.cid || "N/A";
        var isGenesis = !op.prev;

        // Timeline marker
        var marker = [[CPView alloc] initWithFrame:CGRectMake(20.0, yOffset + 5.0, 12.0, 12.0)];
        [marker setBackgroundColor:[CPColor colorWithCalibratedRed:0.3 green:0.5 blue:0.8 alpha:1.0]];
        // Make circular
        [marker setFrame:CGRectMake(20.0, yOffset + 5.0, 12.0, 12.0)];
        [marker setWantsLayer:YES];
        [_timelineView addSubview:marker];

        // Vertical line (except last)
        if (i < sorted.length - 1) {
            var line = [[CPView alloc] initWithFrame:CGRectMake(25.0, yOffset + 20.0, 2.0, 60.0)];
            [line setBackgroundColor:[CPColor colorWithCalibratedWhite:0.8 alpha:1.0]];
            [_timelineView addSubview:line];
        }

        // Date label
        var dateLabel = [[CPTextField alloc] initWithFrame:CGRectMake(40.0, yOffset, 300.0, 18.0)];
        [dateLabel setStringValue:date];
        [dateLabel setEditable:NO];
        [dateLabel setBezeled:NO];
        [dateLabel setDrawsBackground:NO];
        [dateLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
        [_timelineView addSubview:dateLabel];
        yOffset += 22.0;

        // CID label
        var cidLabel = [[CPTextField alloc] initWithFrame:CGRectMake(40.0, yOffset, 400.0, 16.0)];
        var shortCid = cid.length > 30 ? cid.substring(0, 30) + "..." : cid;
        [cidLabel setStringValue:@"CID: " + shortCid];
        [cidLabel setEditable:NO];
        [cidLabel setBezeled:NO];
        [cidLabel setDrawsBackground:NO];
        [cidLabel setFont:[CPFont systemFontOfSize:10.0] withFamily:@"Monaco"];
        [cidLabel setTextColor:[CPColor grayColor]];
        [_timelineView addSubview:cidLabel];
        yOffset += 20.0;

        // Diff content
        if (isGenesis) {
            yOffset = [self renderGenesisOperation:op yOffset:yOffset];
        } else {
            var changes = [self computeDiff:prevOp newOp:op];
            yOffset = [self renderChanges:changes yOffset:yOffset];
        }

        // Raw op (collapsible - simplified as always shown)
        var rawLabel = [[CPTextField alloc] initWithFrame:CGRectMake(60.0, yOffset, 800.0, 80.0)];
        [rawLabel setStringValue:JSON.stringify(op, null, 2)];
        [rawLabel setEditable:NO];
        [rawLabel setBezeled:NO];
        [rawLabel setDrawsBackground:YES];
        [rawLabel setBackgroundColor:[CPColor colorWithCalibratedWhite:0.97 alpha:1.0]];
        [rawLabel setFont:[CPFont systemFontOfSize:9.0] withFamily:@"Monaco"];
        [_timelineView addSubview:rawLabel];
        yOffset += 90.0;

        prevOp = op;
    }

    // Resize timeline view
    [_timelineView setFrame:CGRectMake(0.0, 0.0, 1020.0, yOffset + 20.0)];
}

- (float)renderGenesisOperation:(id)op yOffset:(float)yOffset
{
    var genLabel = [[CPTextField alloc] initWithFrame:CGRectMake(40.0, yOffset, 400.0, 18.0)];
    [genLabel setStringValue:@"Identity Created"];
    [genLabel setEditable:NO];
    [genLabel setBezeled:NO];
    [genLabel setDrawsBackground:NO];
    [genLabel setFont:[CPFont boldSystemFontOfSize:11.0]];
    [genLabel setTextColor:[CPColor colorWithCalibratedRed:0.2 green:0.6 blue:0.3 alpha:1.0]];
    [_timelineView addSubview:genLabel];
    yOffset += 22.0;

    // Initial handles
    var handles = op.alsoKnownAs || [];
    var handlesLabel = [[CPTextField alloc] initWithFrame:CGRectMake(60.0, yOffset, 400.0, 16.0)];
    [handlesLabel setStringValue:@"Handles: " + (handles.length > 0 ? handles.join(", ") : "None")];
    [handlesLabel setEditable:NO];
    [handlesLabel setBezeled:NO];
    [handlesLabel setDrawsBackground:NO];
    [handlesLabel setFont:[CPFont systemFontOfSize:10.0]];
    [_timelineView addSubview:handlesLabel];
    yOffset += 18.0;

    // Initial services
    var services = op.services || {};
    var serviceKeys = Object.keys(services);
    var servicesLabel = [[CPTextField alloc] initWithFrame:CGRectMake(60.0, yOffset, 400.0, 16.0)];
    [servicesLabel setStringValue:@"Services: " + (serviceKeys.length > 0 ? serviceKeys.join(", ") : "None")];
    [servicesLabel setEditable:NO];
    [servicesLabel setBezeled:NO];
    [servicesLabel setDrawsBackground:NO];
    [servicesLabel setFont:[CPFont systemFontOfSize:10.0]];
    [_timelineView addSubview:servicesLabel];
    yOffset += 18.0;

    // Initial keys
    var keys = op.rotationKeys || [];
    var keysLabel = [[CPTextField alloc] initWithFrame:CGRectMake(60.0, yOffset, 400.0, 16.0)];
    [keysLabel setStringValue:keys.length + " rotation keys"];
    [keysLabel setEditable:NO];
    [keysLabel setBezeled:NO];
    [keysLabel setDrawsBackground:NO];
    [keysLabel setFont:[CPFont systemFontOfSize:10.0]];
    [_timelineView addSubview:keysLabel];
    yOffset += 24.0;

    return yOffset;
}

- (CPArray)computeDiff:(id)oldOp newOp:(id)newOp
{
    var changes = [];

    // Handle changes
    var oldHandles = oldOp.alsoKnownAs || [];
    var newHandles = newOp.alsoKnownAs || [];
    if (JSON.stringify(oldHandles) !== JSON.stringify(newHandles)) {
        [changes addObject:@{
            @"type": @"handle",
            @"title": @"Handle updated",
            @"old": oldHandles,
            @"new": newHandles
        }];
    }

    // Service changes
    var oldServices = oldOp.services || {};
    var newServices = newOp.services || {};
    if (JSON.stringify(oldServices) !== JSON.stringify(newServices)) {
        var svcChanges = [];
        var allKeys = Object.keys({...oldServices, ...newServices});
        for (var i = 0; i < allKeys.length; i++) {
            var k = allKeys[i];
            if (!oldServices[k]) {
                [svcChanges addObject:@{@"action": @"added", @"key": k, @"val": newServices[k]}];
            } else if (!newServices[k]) {
                [svcChanges addObject:@{@"action": @"removed", @"key": k, @"val": oldServices[k]}];
            } else if (JSON.stringify(oldServices[k]) !== JSON.stringify(newServices[k])) {
                [svcChanges addObject:@{@"action": @"updated", @"key": k, @"val": newServices[k], @"oldVal": oldServices[k]}];
            }
        }
        [changes addObject:@{@"type": @"service", @"title": @"Services updated", @"items": svcChanges}];
    }

    // Rotation key changes
    var oldKeys = oldOp.rotationKeys || [];
    var newKeys = newOp.rotationKeys || [];
    if (JSON.stringify(oldKeys) !== JSON.stringify(newKeys)) {
        [changes addObject:@{@"type": @"keys", @"title": @"Rotation keys updated", @"old": oldKeys, @"new": newKeys}];
    }

    // Verification method changes
    var oldVM = oldOp.verificationMethods || {};
    var newVM = newOp.verificationMethods || {};
    if (JSON.stringify(oldVM) !== JSON.stringify(newVM)) {
        var vmChanges = [];
        var all = Object.keys({...oldVM, ...newVM});
        for (var i = 0; i < all.length; i++) {
            var k = all[i];
            if (!oldVM[k]) {
                [vmChanges addObject:@{@"action": @"added", @"key": k, @"val": newVM[k]}];
            } else if (!newVM[k]) {
                [vmChanges addObject:@{@"action": @"removed", @"key": k, @"val": oldVM[k]}];
            } else if (JSON.stringify(oldVM[k]) !== JSON.stringify(newVM[k])) {
                [vmChanges addObject:@{@"action": @"updated", @"key": k, @"val": newVM[k]}];
            }
        }
        [changes addObject:@{@"type": @"vm", @"title": @"Verification methods updated", @"items": vmChanges}];
    }

    return changes;
}

- (float)renderChanges:(CPArray)changes yOffset:(float)yOffset
{
    if (changes.length === 0) {
        var noChange = [[CPTextField alloc] initWithFrame:CGRectMake(40.0, yOffset, 400.0, 16.0)];
        [noChange setStringValue:@"No changes (checkpoint)"];
        [noChange setEditable:NO];
        [noChange setBezeled:NO];
        [noChange setDrawsBackground:NO];
        [noChange setFont:[CPFont systemFontOfSize:10.0]];
        [noChange setTextColor:[CPColor grayColor]];
        [_timelineView addSubview:noChange];
        return yOffset + 24.0;
    }

    for (var i = 0; i < changes.length; i++) {
        var change = changes[i];

        var title = change[@"title"];
        var changeLabel = [[CPTextField alloc] initWithFrame:CGRectMake(40.0, yOffset, 400.0, 16.0)];
        [changeLabel setStringValue:title];
        [changeLabel setEditable:NO];
        [changeLabel setBezeled:NO];
        [changeLabel setDrawsBackground:NO];
        [changeLabel setFont:[CPFont boldSystemFontOfSize:11.0]];
        [changeLabel setTextColor:[CPColor colorWithCalibratedRed:0.8 green:0.4 blue:0.2 alpha:1.0]];
        [_timelineView addSubview:changeLabel];
        yOffset += 20.0;

        // Handle type-specific rendering
        var type = change[@"type"];
        if (type === @"handle") {
            var oldHandles = change[@"old"] || [];
            var newHandles = change[@"new"] || [];
            var oldLabel = [[CPTextField alloc] initWithFrame:CGRectMake(60.0, yOffset, 400.0, 14.0)];
            [oldLabel setStringValue:@"- " + oldHandles.join(", ")];
            [oldLabel setEditable:NO];
            [oldLabel setBezeled:NO];
            [oldLabel setDrawsBackground:NO];
            [oldLabel setFont:[CPFont systemFontOfSize:10.0]];
            [oldLabel setTextColor:[CPColor colorWithCalibratedRed:0.8 green:0.2 blue:0.2 alpha:1.0]];
            [_timelineView addSubview:oldLabel];
            yOffset += 16.0;

            var newLabel = [[CPTextField alloc] initWithFrame:CGRectMake(60.0, yOffset, 400.0, 14.0)];
            [newLabel setStringValue:@"+ " + newHandles.join(", ")];
            [newLabel setEditable:NO];
            [newLabel setBezeled:NO];
            [newLabel setDrawsBackground:NO];
            [newLabel setFont:[CPFont systemFontOfSize:10.0]];
            [newLabel setTextColor:[CPColor colorWithCalibratedRed:0.2 green:0.6 blue:0.3 alpha:1.0]];
            [_timelineView addSubview:newLabel];
            yOffset += 20.0;
        }
    }

    return yOffset;
}

@end
