/*
 * CPAccessibilityPolyfill.j
 * CappuccinoUI
 *
 * Accessibility API polyfill - adds accessibility methods to Cappuccino classes.
 * Must be imported AFTER AppKit is loaded.
 */

@import <Foundation/Foundation.j>
@import <AppKit/AppKit.j>

#if PLATFORM(DOM)

/*
 * CPView Accessibility Category
 */
@implementation CPView (CPAccessibility)

- (void)setAccessibilityLabel:(CPString)aLabel
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-label", aLabel ? String(aLabel) : "");
    }
}

- (CPString)accessibilityLabel
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-label");
        return val || @"";
    }
    return nil;
}

- (void)setAccessibilityHint:(CPString)aHint
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-describedby", aHint ? String(aHint) : "");
    }
}

- (CPString)accessibilityHint
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-describedby");
        return val || @"";
    }
    return nil;
}

@end

/*
 * CPTextField Accessibility Category
 */
@implementation CPTextField (CPAccessibility)

- (void)setAccessibilityLabel:(CPString)aLabel
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-label", aLabel ? String(aLabel) : "");
    }
}

- (CPString)accessibilityLabel
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-label");
        return val || @"";
    }
    return nil;
}

- (void)setAccessibilityHint:(CPString)aHint
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-describedby", aHint ? String(aHint) : "");
    }
}

- (CPString)accessibilityHint
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-describedby");
        return val || @"";
    }
    return nil;
}

@end

/*
 * CPButton Accessibility Category
 */
@implementation CPButton (CPAccessibility)

- (void)setAccessibilityLabel:(CPString)aLabel
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-label", aLabel ? String(aLabel) : "");
    }
}

- (CPString)accessibilityLabel
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-label");
        return val || @"";
    }
    return nil;
}

- (void)setAccessibilityHint:(CPString)aHint
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-describedby", aHint ? String(aHint) : "");
    }
}

- (CPString)accessibilityHint
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-describedby");
        return val || @"";
    }
    return nil;
}

@end

/*
 * CPTableView Accessibility Category  
 */
@implementation CPTableView (CPAccessibility)

- (void)setAccessibilityLabel:(CPString)aLabel
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-label", aLabel ? String(aLabel) : "");
    }
}

- (CPString)accessibilityLabel
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-label");
        return val || @"";
    }
    return nil;
}

- (void)setAccessibilityHint:(CPString)aHint
{
    if (self._DOMElement) {
        self._DOMElement.setAttribute("aria-describedby", aHint ? String(aHint) : "");
    }
}

- (CPString)accessibilityHint
{
    if (self._DOMElement) {
        var val = self._DOMElement.getAttribute("aria-describedby");
        return val || @"";
    }
    return nil;
}

@end

#endif