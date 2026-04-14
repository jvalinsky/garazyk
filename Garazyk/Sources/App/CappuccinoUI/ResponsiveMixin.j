/*
 * ResponsiveMixin.j
 * CappuccinoUI
 *
 * Provides responsive breakpoint constants and resize observation utilities
 * for Automatic Layout adaptation across different viewport sizes.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

@global CPViewFrameDidChangeNotification

@implementation ResponsiveMixin : CPObject
{
}

+ (CPString)currentBreakpointForWidth:(float)width
{
    if (width < 600.0)
        return @"mobile";
    else if (width < 900.0)
        return @"tablet";
    else
        return @"desktop";
}

+ (CPArray)cardsLayoutForWidth:(float)width cardCount:(int)count cardHeight:(float)cardHeight gap:(float)gap startX:(float)startX startY:(float)startY
{
    var cardWidth = 240.0;
    var maxColumns = count;
    if (width > startX + gap)
        maxColumns = parseInt((width - startX - gap) / (cardWidth + gap));
    if (maxColumns < 1) maxColumns = 1;
    
    var column = 0;
    var row = 0;
    var results = [];
    
    for (var i = 0; i < count; i++)
    {
        var x = startX + column * (cardWidth + gap);
        var y = startY + row * (cardHeight + gap);
        results.push(CGRectMake(x, y, cardWidth, cardHeight));
        
        column++;
        if (column >= maxColumns)
        {
            column = 0;
            row++;
        }
    }
    
    return results;
}

+ (float)calculateSectionHeightForWidth:(float)width fixedHeight:(float)fixedHeight minWidth:(float)minWidth
{
    if (width < minWidth)
        return fixedHeight + 40.0;
    return fixedHeight;
}

@end