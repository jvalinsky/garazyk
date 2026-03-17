/*
 * SessionStateTest.j
 * CappuccinoUI Tests
 */

@import <Foundation/Foundation.j>
@import <OJUnit/OJTestCase.j>
@import "../SessionState.j"

@implementation SessionStateTest : OJTestCase
{
}

- (void)testInitSetsAdminAuthenticatedToNO
{
    var state = [[SessionState alloc] init];
    [self assertFalse:[state adminAuthenticated]
              message:@"adminAuthenticated should default to NO"];
}

- (void)testInitLeavesCurrentDIDNil
{
    var state = [[SessionState alloc] init];
    [self assertNull:[state currentDID]
             message:@"currentDID should be nil after init"];
}

- (void)testInitLeavesCurrentHandleNil
{
    var state = [[SessionState alloc] init];
    [self assertNull:[state currentHandle]
             message:@"currentHandle should be nil after init"];
}

- (void)testSetCurrentDID
{
    var state = [[SessionState alloc] init];
    [state setCurrentDID:@"did:plc:abc123"];
    [self assert:[state currentDID] equals:@"did:plc:abc123"
         message:@"currentDID should round-trip through accessor"];
}

- (void)testSetCurrentHandle
{
    var state = [[SessionState alloc] init];
    [state setCurrentHandle:@"alice.example.com"];
    [self assert:[state currentHandle] equals:@"alice.example.com"
         message:@"currentHandle should round-trip through accessor"];
}

- (void)testSetAdminAuthenticated
{
    var state = [[SessionState alloc] init];
    [state setAdminAuthenticated:YES];
    [self assertTrue:[state adminAuthenticated]
             message:@"adminAuthenticated should be YES after setting to YES"];
}

- (void)testAdminAuthenticatedToggle
{
    var state = [[SessionState alloc] init];
    [state setAdminAuthenticated:YES];
    [state setAdminAuthenticated:NO];
    [self assertFalse:[state adminAuthenticated]
              message:@"adminAuthenticated should be NO after toggling back"];
}

- (void)testIndependentInstances
{
    var s1 = [[SessionState alloc] init],
        s2 = [[SessionState alloc] init];

    [s1 setCurrentDID:@"did:plc:aaa"];
    [s2 setCurrentDID:@"did:plc:bbb"];

    [self assert:[s1 currentDID] equals:@"did:plc:aaa"
         message:@"s1 DID should not be affected by s2"];
    [self assert:[s2 currentDID] equals:@"did:plc:bbb"
         message:@"s2 DID should not be affected by s1"];
}

@end
