/*
 * PLCMetricsController.j
 * CappuccinoUI
 *
 * Prometheus metrics dashboard for PLC server.
 * Parses metrics text and displays cache stats, verification stats, etc.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation PLCMetricsController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;

    // Metric labels
    CPTextField _requestsLabel;
    CPTextField _operationsLabel;
    CPTextField _errorsLabel;
    CPTextField _latencyLabel;

    CPTextField _memcacheHitsLabel;
    CPTextField _memcacheMissesLabel;
    CPTextField _memcacheRatioLabel;
    CPView _memcacheBar;

    CPTextField _diskHitsLabel;
    CPTextField _diskMissesLabel;
    CPTextField _diskRatioLabel;
    CPView _diskBar;

    CPTextField _verSuccessLabel;
    CPTextField _verFailLabel;

    CPDictionary _lastMetrics;
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
        _lastMetrics = nil;
        _isRunning = NO;
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
    [title setStringValue:@"PLC Metrics"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];
    [_rootView addSubview:title];

    // Status label
    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 600.0, 20.0)];
    [_statusLabel setAutoresizingMask:CPViewWidthSizable | CPViewMaxYMargin];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Loading..."];
    [_rootView addSubview:_statusLabel];

    // Controls
    [self buildControlsInView:_rootView];

    // Metrics sections
    [self buildServerStatsInView:_rootView];
    [self buildCacheStatsInView:_rootView];
    [self buildVerificationStatsInView:_rootView];

    // Load initial metrics
    [self fetchMetrics];
    [self startAutoRefresh];

    return _rootView;
}

- (void)buildControlsInView:(CPView)parent
{
    var refreshButton = [[CPButton alloc] initWithFrame:CGRectMake(20.0, 68.0, 80.0, 28.0)];
    [refreshButton setTitle:@"Refresh"];
    [refreshButton setTarget:self];
    [refreshButton setAction:@selector(handleRefresh:)];
    [parent addSubview:refreshButton];

    var stopStartButton = [[CPButton alloc] initWithFrame:CGRectMake(110.0, 68.0, 100.0, 28.0)];
    [stopStartButton setTitle:@"Stop Refresh"];
    [stopStartButton setTag:@"stopStartButton"];
    [stopStartButton setTarget:self];
    [stopStartButton setAction:@selector(handleToggleRefresh:)];
    [parent addSubview:stopStartButton];
}

- (void)buildServerStatsInView:(CPView)parent
{
    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 110.0, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Server Statistics"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [parent addSubview:sectionLabel];

    var y = 134.0;
    var rowHeight = 22.0;
    var labelWidth = 300.0;

    // Requests
    _requestsLabel = [self createLabelAndValue:@"Requests:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    // Operations
    _operationsLabel = [self createLabelAndValue:@"Operations:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    // Errors
    _errorsLabel = [self createLabelAndValue:@"Errors:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    // Latency
    _latencyLabel = [self createLabelAndValue:@"Avg Latency:" parent:parent y:y labelWidth:labelWidth];

    // Box around section
    var box = [[CPBox alloc] initWithFrame:CGRectMake(15.0, 105.0, 510.0, 100.0)];
    [box setBorderType:CPLineBorder];
    [box setBorderColor:[CPColor colorWithCalibratedWhite:0.85 alpha:1.0]];
    [parent addSubview:box];
}

- (void)buildCacheStatsInView:(CPView)parent
{
    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 220.0, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Cache Statistics"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [parent addSubview:sectionLabel];

    var y = 244.0;
    var rowHeight = 22.0;
    var labelWidth = 300.0;

    // Memory cache
    var memcacheLabel = [[CPTextField alloc] initWithFrame:CGRectMake(30.0, y, 120.0, 18.0)];
    [memcacheLabel setStringValue:@"Memory Cache"];
    [memcacheLabel setEditable:NO];
    [memcacheLabel setBezeled:NO];
    [memcacheLabel setDrawsBackground:NO];
    [memcacheLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [parent addSubview:memcacheLabel];
    y += 22.0;

    _memcacheHitsLabel = [self createLabelAndValue:@"Hits:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    _memcacheMissesLabel = [self createLabelAndValue:@"Misses:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    _memcacheRatioLabel = [self createLabelAndValue:@"Hit Rate:" parent:parent y:y labelWidth:labelWidth];

    // Memory cache bar
    _memcacheBar = [[CPView alloc] initWithFrame:CGRectMake(330.0, y - 18.0, 200.0, 16.0)];
    [_memcacheBar setBackgroundColor:[CPColor colorWithCalibratedWhite:0.9 alpha:1.0]];
    [parent addSubview:_memcacheBar];
    y += 30.0;

    // Disk cache
    var diskLabel = [[CPTextField alloc] initWithFrame:CGRectMake(30.0, y, 120.0, 18.0)];
    [diskLabel setStringValue:@"Disk Cache"];
    [diskLabel setEditable:NO];
    [diskLabel setBezeled:NO];
    [diskLabel setDrawsBackground:NO];
    [diskLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [parent addSubview:diskLabel];
    y += 22.0;

    _diskHitsLabel = [self createLabelAndValue:@"Hits:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    _diskMissesLabel = [self createLabelAndValue:@"Misses:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    _diskRatioLabel = [self createLabelAndValue:@"Hit Rate:" parent:parent y:y labelWidth:labelWidth];

    // Disk cache bar
    _diskBar = [[CPView alloc] initWithFrame:CGRectMake(330.0, y - 18.0, 200.0, 16.0)];
    [_diskBar setBackgroundColor:[CPColor colorWithCalibratedWhite:0.9 alpha:1.0]];
    [parent addSubview:_diskBar];
    y += 30.0;

    // Box around section
    var box = [[CPBox alloc] initWithFrame:CGRectMake(15.0, 215.0, 540.0, 230.0)];
    [box setBorderType:CPLineBorder];
    [box setBorderColor:[CPColor colorWithCalibratedWhite:0.85 alpha:1.0]];
    [parent addSubview:box];
}

- (void)buildVerificationStatsInView:(CPView)parent
{
    var sectionLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 460.0, 200.0, 18.0)];
    [sectionLabel setStringValue:@"Verification Statistics"];
    [sectionLabel setEditable:NO];
    [sectionLabel setBezeled:NO];
    [sectionLabel setDrawsBackground:NO];
    [sectionLabel setFont:[CPFont boldSystemFontOfSize:14.0]];
    [parent addSubview:sectionLabel];

    var y = 484.0;
    var rowHeight = 22.0;
    var labelWidth = 300.0;

    _verSuccessLabel = [self createLabelAndValue:@"Successes:" parent:parent y:y labelWidth:labelWidth];
    y += rowHeight;

    _verFailLabel = [self createLabelAndValue:@"Failures:" parent:parent y:y labelWidth:labelWidth];

    // Box around section
    var box = [[CPBox alloc] initWithFrame:CGRectMake(15.0, 455.0, 510.0, 85.0)];
    [box setBorderType:CPLineBorder];
    [box setBorderColor:[CPColor colorWithCalibratedWhite:0.85 alpha:1.0]];
    [parent addSubview:box];
}

- (CPTextField)createLabelAndValue:(CPString)labelText parent:(CPView)parent y:(float)y labelWidth:(float)labelWidth
{
    var label = [[CPTextField alloc] initWithFrame:CGRectMake(40.0, y, labelWidth - 60.0, 18.0)];
    [label setStringValue:labelText];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setFont:[CPFont systemFontOfSize:12.0]];
    [parent addSubview:label];

    var value = [[CPTextField alloc] initWithFrame:CGRectMake(labelWidth, y, 150.0, 18.0)];
    [value setStringValue:@"-"];
    [value setEditable:NO];
    [value setBezeled:NO];
    [value setDrawsBackground:NO];
    [value setFont:[CPFont boldSystemFontOfSize:12.0]];
    [value setAlignment:CPRightTextAlignment];
    [parent addSubview:value];

    // Store tag on value for later retrieval
    [value setTag:labelText];

    return value;
}

#pragma mark - Data Loading

- (void)fetchMetrics
{
    [_apiClient fetchRaw:@"GET" path:@"/_metrics" params:nil completion:function(response, error) {
        if (error) {
            [_statusLabel setStringValue:@"Error: " + error.localizedDescription];
            return;
        }

        // Parse Prometheus text format
        var metrics = [self parsePrometheus:response];
        [self renderMetrics:metrics];
    }];
}

- (CPDictionary)parsePrometheus:(CPString)text
{
    var metrics = {};
    var lines = text.split("\n");

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        if (line.length === 0 || line[0] === "#") continue;

        var parts = line.split(" ");
        if (parts.length >= 2) {
            var key = parts[0];
            var value = parseFloat(parts[1]);
            metrics[key] = value;
        }
    }

    return metrics;
}

- (void)renderMetrics:(CPDictionary)metrics
{
    var get = function(key) { return metrics[key] || 0; };

    // Server stats
    [_requestsLabel setStringValue:String(get("plc_http_requests_total"))];
    [_operationsLabel setStringValue:String(get("plc_operations_plc_operation_total"))];
    [_errorsLabel setStringValue:String(get("plc_http_errors_total"))];
    [_latencyLabel setStringValue:get("plc_resolution_latency_milliseconds").toFixed(2) + " ms"];

    // Memory cache
    var memHits = get("plc_memcache_hits_total");
    var memMisses = get("plc_memcache_misses_total");
    var memRatio = (memHits + memMisses) > 0 ? Math.round((memHits / (memHits + memMisses)) * 100) : 0;

    [_memcacheHitsLabel setStringValue:String(memHits)];
    [_memcacheMissesLabel setStringValue:String(memMisses)];
    [_memcacheRatioLabel setStringValue:memRatio + "%"];

    // Disk cache
    var diskHits = get("plc_cache_hits_total");
    var diskMisses = get("plc_cache_misses_total");
    var diskRatio = (diskHits + diskMisses) > 0 ? Math.round((diskHits / (diskHits + diskMisses)) * 100) : 0;

    [_diskHitsLabel setStringValue:String(diskHits)];
    [_diskMissesLabel setStringValue:String(diskMisses)];
    [_diskRatioLabel setStringValue:diskRatio + "%"];

    // Verification
    [_verSuccessLabel setStringValue:String(get("plc_verification_successes_total"))];
    [_verFailLabel setStringValue:String(get("plc_verification_failures_total"))];

    [_statusLabel setStringValue:@"Updated " + new Date().toLocaleTimeString()];

    // Update cache bars (visual representation)
    // Note: Cappuccino doesn't have easy progress bars, so we use colored views
}

#pragma mark - Auto Refresh

- (void)startAutoRefresh
{
    if (_isRunning) return;
    _isRunning = YES;

    _refreshTimer = [CPTimer scheduledTimerWithTimeInterval:5.0
                                                   target:self
                                                 selector:@selector(fetchMetrics)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)stopAutoRefresh
{
    if (!_isRunning) return;
    _isRunning = NO;

    if (_refreshTimer) {
        [_refreshTimer invalidate];
        _refreshTimer = nil;
    }
}

#pragma mark - Actions

- (void)handleRefresh:(id)sender
{
    [self fetchMetrics];
}

- (void)handleToggleRefresh:(id)sender
{
    var button = sender;

    if (_isRunning) {
        [self stopAutoRefresh];
        [button setTitle:@"Start Refresh"];
    } else {
        [self startAutoRefresh];
        [button setTitle:@"Stop Refresh"];
    }
}

@end
