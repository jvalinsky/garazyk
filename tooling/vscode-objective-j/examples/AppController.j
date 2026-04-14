/*
 * AppController.j — Comprehensive Objective-J example
 * Tests all grammar features
 */

@import <Foundation/CPObject.j>
@import <AppKit/CPView.j>
@import <AppKit/CPWindow.j>
@import "PersonModel.j"

// Forward declarations
@class CPWindow
@class CPNotificationCenter

@global AppControllerDidFinishNotification
@global CPApp

@typedef PersonType
PersonTypeNormal  = 0;
PersonTypeAdmin   = 1;

#pragma mark - Protocol Definition

@protocol AppDelegate <CPObject>

@required
- (void)applicationDidFinishLaunching:(CPNotification)aNotification;
- (void)applicationWillTerminate:(CPNotification)aNotification;

@optional
- (BOOL)applicationShouldTerminate:(CPApplication)sender;

@end

#pragma mark - Main Controller

@implementation AppController : CPObject <AppDelegate, CPCoding>
{
    CPWindow        _mainWindow @accessors(property=mainWindow);
    @outlet CPView  _contentView;
    CPString        _title @accessors;
    BOOL            _isReady;
    id              _delegate;
    id <AppDelegate> _appDelegate;
    int             _count;
    unsigned        _flags;
    CPArray         _items @accessors(getter=items, readonly);
    CPDictionary    _config;
}

#pragma mark - Class Methods

+ (id)sharedController
{
    return [[self alloc] init];
}

+ (CPString)defaultTitle
{
    return @"My Cappuccino App";
}

#pragma mark - Initialization

- (id)init
{
    self = [super init];

    if (self)
    {
        _title = [AppController defaultTitle];
        _isReady = NO;
        _count = 0;
        _items = [];
        _config = @{
            @"background-color": [CPNull null],
            @"border-width": 1.0,
            @"corner-radius": 3.0
        };
    }

    return self;
}

- (id)initWithTitle:(CPString)aTitle delegate:(id <AppDelegate>)aDelegate
{
    self = [super init];

    if (self)
    {
        _title = aTitle;
        _delegate = aDelegate;
        _isReady = NO;
    }

    return self;
}

#pragma mark - Application Lifecycle

- (void)applicationDidFinishLaunching:(CPNotification)aNotification
{
    var frame = CGRectMake(0, 0, 800, 600),
        origin = CGPointMake(100, 100),
        size = CGSizeMake(800, 600);

    _mainWindow = [[CPWindow alloc] initWithContentRect:frame
                                             styleMask:CPTitledWindowMask | CPClosableWindowMask | CPResizableWindowMask];

    _contentView = [_mainWindow contentView];

    // Create a label
    var label = [[CPTextField alloc] initWithFrame:CGRectMake(10, 10, 200, 30)];
    [label setStringValue:_title];
    [label setFont:[CPFont boldSystemFontOfSize:14.0]];
    [label setTextColor:[CPColor whiteColor]];
    [_contentView addSubview:label];

    // Create a button
    var button = [[CPButton alloc] initWithFrame:CGRectMake(10, 50, 100, 32)];
    [button setTitle:@"Click Me"];
    [button setTarget:self];
    [button setAction:@selector(buttonClicked:)];
    [_contentView addSubview:button];

    // Table view setup
    var scrollView = [[CPScrollView alloc] initWithFrame:CGRectMake(10, 100, 400, 300)];
    var tableView = [[CPTableView alloc] initWithFrame:CGRectMakeZero()];
    [tableView setDataSource:self];
    [tableView setDelegate:self];
    [scrollView setDocumentView:tableView];
    [_contentView addSubview:scrollView];

    [_mainWindow orderFront:self];

    _isReady = YES;

    [[CPNotificationCenter defaultCenter] postNotificationName:AppControllerDidFinishNotification
                                                        object:self
                                                      userInfo:nil];

    // Test width/height CG functions
    var w = CGRectGetWidth(frame);
    var h = CGRectGetHeight(frame);
    var midX = CGRectGetMidX(frame);
    var intersects = CGRectIntersectsRect(frame, CGRectMake(0, 0, 10, 10));
}

- (void)applicationWillTerminate:(CPNotification)aNotification
{
    console.log("App terminating");
}

#pragma mark - Actions

- (@action)buttonClicked:(id)sender
{
    var items = @{
        @"name": @"Cappuccino",
        @"version": @"1.0"
    };

    alert("Button clicked! App: " + [items objectForKey:@"name"]);

    if ([_delegate respondsToSelector:@selector(controllerDidClick:)])
        [_delegate controllerDidClick:self];

    // @ref/@deref usage
    var errorMsg = @"",
        errorRef = @ref(errorMsg);
    @deref(errorRef) = @"Something went wrong";
    console.log(@deref(errorRef));
}

#pragma mark - Exception Handling

- (void)riskyOperation
{
    @try
    {
        [self performSelectorWithUnknown:_cmd];
    }
    @catch (e)
    {
        console.error("Caught exception: " + e);
    }
    @finally
    {
        console.log("Cleanup complete");
    }
}

#pragma mark - CPTableView DataSource

- (int)numberOfRowsInTableView:(CPTableView)aTableView
{
    return [_items count];
}

- (id)tableView:(CPTableView)aTableView objectValueForTableColumn:(CPTableColumn)aColumn row:(int)aRow
{
    return [_items objectAtIndex:aRow];
}

#pragma mark - Accessors

- (void)setDelegate:(id)aDelegate
{
    _delegate = aDelegate;
}

- (BOOL)isReady
{
    return _isReady;
}

#pragma mark - Private

- (void)_updateUI
{
    if (!_isReady)
        return;

    var i, count = [_items count];
    for (i = 0; i < count; i++)
    {
        var item = [_items objectAtIndex:i];
        console.log(`Item ${i}: ${item}`);
    }

    // Arrow function (JS superset)
    var filtered = _items.filter(item => item !== nil);

    // Modern JS
    var doubled = _items.map((item) => {
        return item * 2;
    });

    // Optional chaining and nullish coalescing
    var name = _delegate?.name ?? @"Unknown";

    // Destructuring
    var {width, height} = {width: 100, height: 200};

    // Regex
    var pattern = /^[A-Z]\w+$/gi;
    var isMatch = pattern.test(_title);

    // Numeric literals
    var hex = 0xFF;
    var bin = 0b1010;
    var oct = 0o755;
    var big = 1_000_000;
    var sci = 1.5e-3;

    // Spread
    var combined = [..._items, ...filtered];

    // Async (if used in modern ObjJ contexts)
    // async function fetchData() { await somePromise; }
}

@end

#pragma mark - Category

@implementation CPString (AppAdditions)

- (CPString)truncatedToLength:(int)maxLength
{
    if ([self length] <= maxLength)
        return self;

    return [[self substringToIndex:maxLength] stringByAppendingString:@"..."];
}

- (CPString)reversed
{
    var reversedString = "",
        index = [self length];

    while (index--)
        reversedString += [self characterAtIndex:index];

    return reversedString;
}

@end
