/*
 * LoadingSpinner.j
 * CappuccinoUI
 *
 * In-place loading spinner with CSS animation.
 * Uses CSS class defined in index.html.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

@implementation LoadingSpinner : CPView
{
    DOMElement _spinnerElement;
    BOOL _isAnimating;
}

+ (LoadingSpinner)smallSpinner
{
    return [[LoadingSpinner alloc] initWithFrame:CGRectMake(0.0, 0.0, 16.0, 16.0)];
}

+ (LoadingSpinner)largeSpinner
{
    var spinner = [[LoadingSpinner alloc] initWithFrame:CGRectMake(0.0, 0.0, 24.0, 24.0)];
    [spinner setLarge:YES];
    return spinner;
}

+ (LoadingSpinner)spinnerWithColor:(CPString)color
{
    var spinner = [self smallSpinner];
    [spinner setColor:color];
    return spinner;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        _isAnimating = NO;
        [self _createSpinnerElement];
    }
    return self;
}

- (void)_createSpinnerElement
{
    // Create a DOM element with the spinner class
    _spinnerElement = document.createElement("div");
    _spinnerElement.className = "cappuccino-spinner";
    _spinnerElement.style.width = [self bounds].size.width + "px";
    _spinnerElement.style.height = [self bounds].size.height + "px";

    // Add to DOM
    var domElement = [self _DOMElement];
    if (domElement)
        domElement.appendChild(_spinnerElement);
}

- (void)setLarge:(BOOL)large
{
    if (_spinnerElement)
    {
        if (large)
        {
            _spinnerElement.className = "cappuccino-spinner cappuccino-spinner-large";
            [self setFrameSize:CGSizeMake(24.0, 24.0)];
        }
        else
        {
            _spinnerElement.className = "cappuccino-spinner";
            [self setFrameSize:CGSizeMake(16.0, 16.0)];
        }
    }
}

- (void)setColor:(CPString)color
{
    if (_spinnerElement)
    {
        // color can be "gray", "blue", "white", or a hex value
        var borderColor = "#ccc";
        var borderTopColor = "#555";

        if (color === "blue")
        {
            borderColor = "rgba(59, 130, 246, 0.3)";
            borderTopColor = "#3B82F6";
        }
        else if (color === "white")
        {
            borderColor = "rgba(255, 255, 255, 0.3)";
            borderTopColor = "#FFFFFF";
        }
        else if (color && color.charAt(0) === "#")
        {
            borderTopColor = color;
            borderColor = color + "4D"; // 30% opacity
        }

        _spinnerElement.style.borderColor = borderColor;
        _spinnerElement.style.borderTopColor = borderTopColor;
    }
}

- (void)startAnimating
{
    _isAnimating = YES;
    [self setHidden:NO];
}

- (void)stopAnimating
{
    _isAnimating = NO;
    [self setHidden:YES];
}

- (BOOL)isAnimating
{
    return _isAnimating;
}

// Show spinner next to a view (like a status label)
+ (LoadingSpinner)showSpinnerNextToView:(CPView)view offset:(float)offset
{
    var viewFrame = [view frame];
    var viewSuperview = [view superview];

    if (!viewSuperview)
        return nil;

    var spinner = [LoadingSpinner smallSpinner];
    var spinnerFrame = CGRectMake(
        viewFrame.origin.x + viewFrame.size.width + offset,
        viewFrame.origin.y + (viewFrame.size.height - 16.0) / 2.0,
        16.0,
        16.0
    );
    [spinner setFrame:spinnerFrame];
    [viewSuperview addSubview:spinner];
    [spinner startAnimating];

    return spinner;
}

+ (LoadingSpinner)showSpinnerAfterView:(CPView)view
{
    return [self showSpinnerNextToView:view offset:6.0];
}

@end

/*
 * StatusHelper category for common status operations.
 * Add to CPTextField via category.
 */

@implementation CPTextField (StatusHelper)

- (void)setErrorStatus:(CPString)message
{
    [self setStringValue:@"Error: " + message];
    [self setTextColor:[CPColor colorWithCalibratedRed:(185.0/255.0)
                                                 green:(28.0/255.0)
                                                  blue:(28.0/255.0)
                                                 alpha:1.0]];
}

- (void)setSuccessStatus:(CPString)message
{
    [self setStringValue:message];
    [self setTextColor:[CPColor colorWithCalibratedRed:(4.0/255.0)
                                                 green:(120.0/255.0)
                                                  blue:(87.0/255.0)
                                                 alpha:1.0]];
}

- (void)setWarningStatus:(CPString)message
{
    [self setStringValue:@"Warning: " + message];
    [self setTextColor:[CPColor colorWithCalibratedRed:(180.0/255.0)
                                                 green:(83.0/255.0)
                                                  blue:(9.0/255.0)
                                                 alpha:1.0]];
}

- (void)setInfoStatus:(CPString)message
{
    [self setStringValue:message];
    [self setTextColor:[CPColor colorWithCalibratedWhite:(75.0/255.0) alpha:1.0]];
}

@end
