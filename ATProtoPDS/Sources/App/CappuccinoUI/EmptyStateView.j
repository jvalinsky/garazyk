/*
 * EmptyStateView.j
 * CappuccinoUI
 *
 * Empty state placeholder with Material icon and message.
 * For use in tables and lists when no data is available.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

@implementation EmptyStateView : CPView
{
    CPTextField _iconLabel;
    CPTextField _messageLabel;
    CPButton _actionButton;
}

// Material icon codes (from MaterialIcons-Regular.ijsmap)
var EmptyStateIcons = {
    "person_outline": "\ue7fd",
    "folder_open": "\ue2c8",
    "chat_bubble_outline": "\ue0cb",
    "people_outline": "\ue7fc",
    "report_problem": "\ue160",
    "mail_outline": "\ue0be",
    "cloud_off": "\ue2c0",
    "event_busy": "\ue616",
    "history": "\ue88a",
    "inbox": "\ue156",
    "search": "\ue8b6",
    "description": "\ue88c",
    "dns": "\ue875"
};

+ (EmptyStateView)emptyStateWithIcon:(CPString)iconName
                              message:(CPString)message
                              inView:(CPView)parent
{
    var frame = [parent bounds];
    var emptyState = [[EmptyStateView alloc] initWithFrame:frame
                                                       icon:iconName
                                                    message:message
                                                 actionTitle:nil
                                               actionHandler:nil];
    [parent addSubview:emptyState];
    return emptyState;
}

+ (EmptyStateView)emptyStateWithIcon:(CPString)iconName
                              message:(CPString)message
                         actionTitle:(CPString)actionTitle
                       actionHandler:(Function)handler
                              inView:(CPView)parent
{
    var frame = [parent bounds];
    var emptyState = [[EmptyStateView alloc] initWithFrame:frame
                                                       icon:iconName
                                                    message:message
                                                 actionTitle:actionTitle
                                               actionHandler:handler];
    [parent addSubview:emptyState];
    return emptyState;
}

- (id)initWithFrame:(CGRect)frame
                icon:(CPString)iconName
             message:(CPString)message
          actionTitle:(CPString)actionTitle
        actionHandler:(Function)handler
{
    self = [super initWithFrame:frame];
    if (self)
    {
        [self setAutoresizesSubviews:YES];
        [self setAutoresizingMask:CPViewWidthSizable | CPViewHeightSizable];

        // Background
        [self setBackgroundColor:[CPColor colorWithCalibratedWhite:0.98 alpha:1.0]];

        // Icon using Material Icons font
        _iconLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, 0.0, 48.0, 48.0)];
        [_iconLabel setFont:[CPFont fontWithName:@"Material Icons" size:48.0]];

        var iconChar = EmptyStateIcons[iconName];
        if (!iconChar)
            iconChar = EmptyStateIcons["inbox"]; // Default icon
        [_iconLabel setStringValue:iconChar];

        [_iconLabel setTextColor:[CPColor colorWithCalibratedWhite:0.6 alpha:1.0]];
        [_iconLabel setEditable:NO];
        [_iconLabel setBezeled:NO];
        [_iconLabel setDrawsBackground:NO];
        [_iconLabel setAlignment:CPCenterTextAlignment];
        [_iconLabel setAutoresizingMask:CPViewMinXMargin | CPViewMaxXMargin | CPViewMinYMargin];
        [_iconLabel setAccessibilityLabel:@"Empty state icon"];

        // Message
        _messageLabel = [[CPTextField alloc] initWithFrame:CGRectMake(0.0, 0.0, frame.size.width - 40.0, 40.0)];
        [_messageLabel setStringValue:message || "No items found"];
        [_messageLabel setFont:[CPFont systemFontOfSize:14.0]];
        [_messageLabel setTextColor:[CPColor colorWithCalibratedWhite:0.4 alpha:1.0]];
        [_messageLabel setEditable:NO];
        [_messageLabel setBezeled:NO];
        [_messageLabel setDrawsBackground:NO];
        [_messageLabel setAlignment:CPCenterTextAlignment];
        [_messageLabel setLineBreakMode:CPLineBreakByWordWrapping];
        [_messageLabel setAutoresizingMask:CPViewWidthSizable | CPViewMinYMargin];
        [_messageLabel setAccessibilityLabel:@"Empty state message"];

        [self addSubview:_iconLabel];
        [self addSubview:_messageLabel];

        // Action button (optional)
        if (actionTitle && handler)
        {
            _actionButton = [[CPButton alloc] initWithFrame:CGRectMake(0.0, 0.0, 140.0, 28.0)];
            [_actionButton setTitle:actionTitle];
            [_actionButton setTarget:self];
            [_actionButton setAction:@selector(handleAction:)];
            [_actionButton setAutoresizingMask:CPViewMinXMargin | CPViewMaxXMargin | CPViewMinYMargin];
            [_actionButton setAccessibilityLabel:actionTitle];
            [self addSubview:_actionButton];

            // Store handler
            _actionHandler = handler;
        }

        // Layout
        [self layoutSubviews];
    }
    return self;
}

- (void)layoutSubviews
{
    var frame = [self bounds];
    var centerX = frame.size.width / 2.0;
    var totalHeight = 48.0 + 16.0 + 40.0; // icon + gap + message
    if (_actionButton)
        totalHeight += 36.0; // button + gap

    var startY = (frame.size.height - totalHeight) / 2.0;

    [_iconLabel setFrameOrigin:CGPointMake(centerX - 24.0, startY)];
    [_messageLabel setFrame:CGRectMake(20.0, startY + 60.0, frame.size.width - 40.0, 40.0)];

    if (_actionButton)
    {
        [_actionButton setFrameOrigin:CGPointMake(centerX - 70.0, startY + 110.0)];
    }
}

- (void)resizeWithOldSuperviewSize:(CGSize)size
{
    [super resizeWithOldSuperviewSize:size];
    [self layoutSubviews];
}

- (void)setMessage:(CPString)message
{
    [_messageLabel setStringValue:message || "No items found"];
}

- (void)setIcon:(CPString)iconName
{
    var iconChar = EmptyStateIcons[iconName];
    if (!iconChar)
        iconChar = EmptyStateIcons["inbox"];
    [_iconLabel setStringValue:iconChar];
}

- (void)handleAction:(id)sender
{
    if (_actionHandler)
        _actionHandler();
}

// Remove from parent view
- (void)removeFromView
{
    [self removeFromSuperview];
}

// Hide/Show convenience
- (void)showInView:(CPView)parent
{
    [self setFrame:[parent bounds]];
    [parent addSubview:self];
}

- (void)hide
{
    [self removeFromSuperview];
}

@end


// Icon name constants for convenience
EmptyStateIconPerson = "person_outline";
EmptyStateIconFolder = "folder_open";
EmptyStateIconChat = "chat_bubble_outline";
EmptyStateIconPeople = "people_outline";
EmptyStateIconReport = "report_problem";
EmptyStateIconMail = "mail_outline";
EmptyStateIconCloudOff = "cloud_off";
EmptyStateIconEvent = "event_busy";
EmptyStateIconHistory = "history";
EmptyStateIconInbox = "inbox";
EmptyStateIconSearch = "search";
EmptyStateIconDoc = "description";
EmptyStateIconDns = "dns";
