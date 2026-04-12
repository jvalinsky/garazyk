/*
 * RelayDashboardController.j
 * CappuccinoUI
 *
 * Relay metrics dashboard with connection overview,
 * event throughput, and validation statistics.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>
@import "SessionState.j"
@import "UIAPIClient.j"

@implementation RelayDashboardController : CPObject
{
    SessionState _sessionState;
    UIAPIClient _apiClient;
    CPView _rootView;

    CPTextField _statusLabel;

    // Metric cards
    CPTextField _upstreamLabel;
    CPTextField _downstreamLabel;
    CPTextField _eventsRateLabel;
    CPTextField _droppedLabel;

    // Event stats labels
    CPTextField _eventsReceivedLabel;
    CPTextField _eventsValidatedLabel;
    CPTextField _eventsForwardedLabel;
    CPTextField _eventsDroppedLabel;

    // Validation stats labels
    CPTextField _mstSuccessLabel;
    CPTextField _mstFailureLabel;
    CPTextField _sigSuccessLabel;
    CPTextField _sigFailureLabel;

    // Sequence and reconnect
    CPTextField _sequenceLabel;
    CPTextField _reconnectLabel;

    CPArray _lastMetrics;
    int _eventsThisSecond;
    int _lastEventsReceived;
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
        _eventsThisSecond = 0;
        _lastEventsReceived = 0;
        _isRunning = NO;
    }
    return self;
}

- (CPView)rootView
{
    if (_rootView)
        return _rootView;

    _rootView = [[CPView alloc] initWithFrame:CGRectMake(0.0, 0.0, 1080.0, 700.0)];

    var title = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 16.0, 900.0, 28.0)];
    [title setStringValue:@"Relay Dashboard"];
    [title setEditable:NO];
    [title setBezeled:NO];
    [title setDrawsBackground:NO];
    [title setFont:[CPFont boldSystemFontOfSize:20.0]];

    _statusLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, 44.0, 1040.0, 20.0)];
    [_statusLabel setEditable:NO];
    [_statusLabel setBezeled:NO];
    [_statusLabel setDrawsBackground:NO];
    [_statusLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_statusLabel setStringValue:@"Loading metrics..."];
    [_statusLabel setAccessibilityLabel:@"Status message"];

    // Connection cards row
    [self buildConnectionCardsInView:_rootView atY:80.0];

    // Event stats section
    [self buildEventStatsInView:_rootView atY:200.0];

    // Validation stats section
    [self buildValidationStatsInView:_rootView atY:360.0];

    // Sequence info section
    [self buildSequenceInfoInView:_rootView atY:480.0];

    // Control buttons
    var refreshBtn = [[CPButton alloc] initWithFrame:CGRectMake(20.0, 560.0, 100.0, 28.0)];
    [refreshBtn setTitle:@"Refresh Now"];
    [refreshBtn setTarget:self];
    [refreshBtn setAction:@selector(handleRefresh:)];
    [refreshBtn setAccessibilityLabel:@"Refresh metrics"];
    [refreshBtn setAccessibilityHint:@"Reload relay metrics from server"];

    var autoRefreshBtn = [[CPButton alloc] initWithFrame:CGRectMake(130.0, 560.0, 120.0, 28.0)];
    [autoRefreshBtn setTitle:@"Auto Refresh: ON"];
    [autoRefreshBtn setTag:@"autoRefreshBtn"];
    [autoRefreshBtn setTarget:self];
    [autoRefreshBtn setAction:@selector(handleToggleAutoRefresh:)];
    [autoRefreshBtn setAccessibilityLabel:@"Toggle auto refresh"];
    [autoRefreshBtn setAccessibilityHint:@"Enable or disable automatic metric refresh"];

    [_rootView addSubview:title];
    [_rootView addSubview:_statusLabel];
    [_rootView addSubview:refreshBtn];
    [_rootView addSubview:autoRefreshBtn];

    // Start auto-refresh
    [self startAutoRefresh];

    return _rootView;
}

- (void)buildConnectionCardsInView:(CPView)parent atY:(float)startY
{
    var cardWidth = 240.0,
        cardHeight = 90.0,
        gap = 20.0,
        startX = 20.0;

    // Upstream card
    var upstreamCard = [self buildMetricCardWithTitle:@"Upstreams"
                                              value:@"0"
                                           frame:CGRectMake(startX, startY, cardWidth, cardHeight)
                                             color:[CPColor colorWithCalibratedRed:0.2 green:0.6 blue:1.0 alpha:1.0]];
    _upstreamLabel = [upstreamCard viewWithTag:@"valueLabel"];

    // Downstream card
    var downstreamCard = [self buildMetricCardWithTitle:@"Downstreams"
                                                 value:@"0"
                                              frame:CGRectMake(startX + cardWidth + gap, startY, cardWidth, cardHeight)
                                                color:[CPColor colorWithCalibratedRed:0.2 green:0.8 blue:0.4 alpha:1.0]];
    _downstreamLabel = [downstreamCard viewWithTag:@"valueLabel"];

    // Events/sec card
    var eventsCard = [self buildMetricCardWithTitle:@"Events/sec"
                                             value:@"0"
                                          frame:CGRectMake(startX + 2 * (cardWidth + gap), startY, cardWidth, cardHeight)
                                            color:[CPColor colorWithCalibratedRed:0.8 green:0.5 blue:0.2 alpha:1.0]];
    _eventsRateLabel = [eventsCard viewWithTag:@"valueLabel"];

    // Dropped card
    var droppedCard = [self buildMetricCardWithTitle:@"Total Dropped"
                                             value:@"0"
                                          frame:CGRectMake(startX + 3 * (cardWidth + gap), startY, cardWidth, cardHeight)
                                            color:[CPColor colorWithCalibratedRed:0.8 green:0.2 blue:0.2 alpha:1.0]];
    _droppedLabel = [droppedCard viewWithTag:@"valueLabel"];
}

- (CPView)buildMetricCardWithTitle:(CPString)title value:(CPString)value frame:(CGRect)frame color:(CPColor)color
{
    var card = [[CPView alloc] initWithFrame:frame];
    [card setWantsLayer:YES];
    [card setBackgroundColor:[CPColor colorWithCalibratedWhite:0.95 alpha:1.0]];
    [card setLayerBorderWidth:1.0];
    [card setLayerBorderColor:[CPColor colorWithCalibratedWhite:0.85 alpha:1.0]];
    [card setLayerCornerRadius:8.0];

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

- (void)buildEventStatsInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 200.0, 24.0)];
    [sectionTitle setStringValue:@"Event Statistics"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    // Stats table
    var tableData = [
        {label: @"Received:", tag: @"eventsReceived"},
        {label: @"Validated:", tag: @"eventsValidated"},
        {label: @"Forwarded:", tag: @"eventsForwarded"},
        {label: @"Dropped:", tag: @"eventsDropped"}
    ];

    var y = startY + 30.0;
    for (var i = 0; i < tableData.length; i++)
    {
        var row = tableData[i];
        var labelField = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, y, 120.0, 22.0)];
        [labelField setStringValue:row.label];
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
        [valueField setTag:row.tag];
        [parent addSubview:valueField];

        y += 26.0;
    }

    _eventsReceivedLabel = [parent viewWithTag:@"eventsReceived"];
    _eventsValidatedLabel = [parent viewWithTag:@"eventsValidated"];
    _eventsForwardedLabel = [parent viewWithTag:@"eventsForwarded"];
    _eventsDroppedLabel = [parent viewWithTag:@"eventsDropped"];
}

- (void)buildValidationStatsInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 200.0, 24.0)];
    [sectionTitle setStringValue:@"Validation"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    // MST Validation row
    var mstLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY + 34.0, 80.0, 22.0)];
    [mstLabel setStringValue:@"MST:"];
    [mstLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [mstLabel setEditable:NO];
    [mstLabel setBezeled:NO];
    [mstLabel setDrawsBackground:NO];
    [parent addSubview:mstLabel];

    _mstSuccessLabel = [[CPTextField alloc] initWithFrame:CGRectMake(100.0, startY + 34.0, 150.0, 22.0)];
    [_mstSuccessLabel setStringValue:@"✓ 0"];
    [_mstSuccessLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_mstSuccessLabel setTextColor:[CPColor colorWithCalibratedRed:0.2 green:0.6 blue:0.2 alpha:1.0]];
    [_mstSuccessLabel setEditable:NO];
    [_mstSuccessLabel setBezeled:NO];
    [_mstSuccessLabel setDrawsBackground:NO];
    [parent addSubview:_mstSuccessLabel];

    _mstFailureLabel = [[CPTextField alloc] initWithFrame:CGRectMake(260.0, startY + 34.0, 150.0, 22.0)];
    [_mstFailureLabel setStringValue:@"✗ 0"];
    [_mstFailureLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_mstFailureLabel setTextColor:[CPColor colorWithCalibratedRed:0.8 green:0.2 blue:0.2 alpha:1.0]];
    [_mstFailureLabel setEditable:NO];
    [_mstFailureLabel setBezeled:NO];
    [_mstFailureLabel setDrawsBackground:NO];
    [parent addSubview:_mstFailureLabel];

    // Signature Validation row
    var sigLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY + 60.0, 80.0, 22.0)];
    [sigLabel setStringValue:@"Signature:"];
    [sigLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [sigLabel setEditable:NO];
    [sigLabel setBezeled:NO];
    [sigLabel setDrawsBackground:NO];
    [parent addSubview:sigLabel];

    _sigSuccessLabel = [[CPTextField alloc] initWithFrame:CGRectMake(100.0, startY + 60.0, 150.0, 22.0)];
    [_sigSuccessLabel setStringValue:@"✓ 0"];
    [_sigSuccessLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_sigSuccessLabel setTextColor:[CPColor colorWithCalibratedRed:0.2 green:0.6 blue:0.2 alpha:1.0]];
    [_sigSuccessLabel setEditable:NO];
    [_sigSuccessLabel setBezeled:NO];
    [_sigSuccessLabel setDrawsBackground:NO];
    [parent addSubview:_sigSuccessLabel];

    _sigFailureLabel = [[CPTextField alloc] initWithFrame:CGRectMake(260.0, startY + 60.0, 150.0, 22.0)];
    [_sigFailureLabel setStringValue:@"✗ 0"];
    [_sigFailureLabel setFont:[CPFont systemFontOfSize:12.0]];
    [_sigFailureLabel setTextColor:[CPColor colorWithCalibratedRed:0.8 green:0.2 blue:0.2 alpha:1.0]];
    [_sigFailureLabel setEditable:NO];
    [_sigFailureLabel setBezeled:NO];
    [_sigFailureLabel setDrawsBackground:NO];
    [parent addSubview:_sigFailureLabel];
}

- (void)buildSequenceInfoInView:(CPView)parent atY:(float)startY
{
    var sectionTitle = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY, 200.0, 24.0)];
    [sectionTitle setStringValue:@"Sequence & Connections"];
    [sectionTitle setFont:[CPFont boldSystemFontOfSize:14.0]];
    [sectionTitle setEditable:NO];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [parent addSubview:sectionTitle];

    var seqLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY + 30.0, 100.0, 22.0)];
    [seqLabel setStringValue:@"Current Seq:"];
    [seqLabel setFont:[CPFont systemFontOfSize:12.0]];
    [seqLabel setEditable:NO];
    [seqLabel setBezeled:NO];
    [seqLabel setDrawsBackground:NO];
    [parent addSubview:seqLabel];

    _sequenceLabel = [[CPTextField alloc] initWithFrame:CGRectMake(120.0, startY + 30.0, 200.0, 22.0)];
    [_sequenceLabel setStringValue:@"0"];
    [_sequenceLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [_sequenceLabel setEditable:NO];
    [_sequenceLabel setBezeled:NO];
    [_sequenceLabel setDrawsBackground:NO];
    [parent addSubview:_sequenceLabel];

    var reconnectLabel = [[CPTextField alloc] initWithFrame:CGRectMake(20.0, startY + 56.0, 100.0, 22.0)];
    [reconnectLabel setStringValue:@"Reconnects:"];
    [reconnectLabel setFont:[CPFont systemFontOfSize:12.0]];
    [reconnectLabel setEditable:NO];
    [reconnectLabel setBezeled:NO];
    [reconnectLabel setDrawsBackground:NO];
    [parent addSubview:reconnectLabel];

    _reconnectLabel = [[CPTextField alloc] initWithFrame:CGRectMake(120.0, startY + 56.0, 200.0, 22.0)];
    [_reconnectLabel setStringValue:@"0"];
    [_reconnectLabel setFont:[CPFont boldSystemFontOfSize:12.0]];
    [_reconnectLabel setEditable:NO];
    [_reconnectLabel setBezeled:NO];
    [_reconnectLabel setDrawsBackground:NO];
    [parent addSubview:_reconnectLabel];
}

#pragma mark - Data Loading

- (void)loadMetrics
{
    [_apiClient getJSONWithPath:@"/metrics"
                  endpointGroup:@"relay"
                    queryParams:nil
                     completion:function(statusCode, payload, errorMessage)
                     {
                         if (errorMessage)
                         {
                             [_statusLabel setStringValue:@"Error: " + errorMessage];
                             return;
                         }

                         if (payload && payload.metrics)
                         {
                             [self updateMetricsDisplay:payload.metrics];
                             [_statusLabel setStringValue:@"Updated " + new Date().toLocaleTimeString()];
                         }
                     }];
}

- (void)updateMetricsDisplay:(id)metrics
{
    if (!metrics)
        return;

    // Calculate events/sec
    var currentReceived = parseInt(metrics.eventsReceived) || 0;
    if (_lastMetrics)
    {
        _eventsThisSecond = currentReceived - _lastEventsReceived;
    }
    _lastEventsReceived = currentReceived;
    _lastMetrics = metrics;

    // Update connection cards
    [_upstreamLabel setStringValue:String(metrics.upstreamConnections || 0)];
    [_downstreamLabel setStringValue:String(metrics.downstreamConnections || 0)];
    [_eventsRateLabel setStringValue:String(_eventsThisSecond)];
    [_droppedLabel setStringValue:String(metrics.eventsDropped || 0)];

    // Update event stats
    [_eventsReceivedLabel setStringValue:self.formatNumber(metrics.eventsReceived)];
    [_eventsValidatedLabel setStringValue:self.formatNumber(metrics.eventsValidated)];
    [_eventsForwardedLabel setStringValue:self.formatNumber(metrics.eventsForwarded)];
    [_eventsDroppedLabel setStringValue:self.formatNumber(metrics.eventsDropped)];

    // Update validation stats
    [_mstSuccessLabel setStringValue:@"✓ " + self.formatNumber(metrics.mstValidationSuccess)];
    [_mstFailureLabel setStringValue:@"✗ " + self.formatNumber(metrics.mstValidationFailure)];
    [_sigSuccessLabel setStringValue:@"✓ " + self.formatNumber(metrics.signatureValidationSuccess)];
    [_sigFailureLabel setStringValue:@"✗ " + self.formatNumber(metrics.signatureValidationFailure)];

    // Update sequence info
    [_sequenceLabel setStringValue:self.formatNumber(metrics.currentSequence)];
    [_reconnectLabel setStringValue:String(metrics.reconnectionCount || 0)];
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
    [self loadMetrics];

    if (!(window && window.setInterval))
        return;

    _refreshTimer = window.setInterval(function()
    {
        if (_isRunning)
            [self loadMetrics];
    }, 1000);
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
    [self loadMetrics];
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

@end
