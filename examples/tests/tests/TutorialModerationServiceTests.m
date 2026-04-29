#import <XCTest/XCTest.h>
#import "TutorialModerationService.h"

@interface TutorialModerationServiceTests : XCTestCase
@property (nonatomic, strong) NSString *dbPath;
@property (nonatomic, strong) TutorialModerationService *service;
@end

@implementation TutorialModerationServiceTests

- (void)setUp {
    [super setUp];
    self.dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"mod_test_%@", [[NSUUID UUID] UUIDString]]];
    self.service = [[TutorialModerationService alloc] initWithDatabasePath:self.dbPath];
}

- (void)tearDown {
    self.service = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.dbPath error:nil];
    [super tearDown];
}

#pragma mark - Reports

- (void)testSubmitReport {
    NSError *error = nil;
    int64_t reportId = [self.service submitReport:@"did:web:localhost:~bob"
                                       subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                                      reporterDID:@"did:web:localhost:~alice"
                                       reasonType:@"com.atproto.moderation.defs#reasonSpam"
                                          comment:@"This is spam"
                                            error:&error];
    XCTAssertGreaterThan(reportId, 0, @"Report should be submitted with valid ID");
    XCTAssertNil(error);
}

- (void)testSubmitMultipleReports {
    [self.service submitReport:@"did:web:localhost:~bob"
                   subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                  reporterDID:@"did:web:localhost:~alice"
                   reasonType:@"com.atproto.moderation.defs#reasonSpam"
                      comment:nil
                        error:nil];
    NSError *error = nil;
    int64_t reportId2 = [self.service submitReport:@"did:web:localhost:~bob"
                                        subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                                       reporterDID:@"did:web:localhost:~carol"
                                        reasonType:@"com.atproto.moderation.defs#reasonAdult"
                                           comment:@"NSFW"
                                             error:&error];
    XCTAssertGreaterThan(reportId2, 0, @"Second report should succeed");
    XCTAssertNil(error);
}

#pragma mark - Labels

- (void)testAddLabel {
    NSError *error = nil;
    BOOL applied = [self.service addLabel:@"did:web:localhost:~bob"
                               subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                               labelValue:@"spam"
                                labeledBy:@"did:web:localhost:~moderator"
                                    error:&error];
    XCTAssertTrue(applied, @"Label should be applied");
    XCTAssertNil(error);
}

- (void)testAddNegationLabel {
    NSError *error = nil;
    BOOL applied = [self.service addLabel:@"did:web:localhost:~bob"
                               subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                               labelValue:@"!warn"
                                labeledBy:@"did:web:localhost:~moderator"
                                    error:&error];
    XCTAssertTrue(applied, @"Negation label should be applied");
}

#pragma mark - Subject Status

- (void)testGetSubject {
    [self.service submitReport:@"did:web:localhost:~bob"
                   subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                  reporterDID:@"did:web:localhost:~alice"
                   reasonType:@"com.atproto.moderation.defs#reasonSpam"
                      comment:nil
                        error:nil];

    NSError *error = nil;
    TutorialModerationSubject *subject = [self.service getSubject:@"did:web:localhost:~bob"
                                                       subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                                                            error:&error];
    XCTAssertNotNil(subject, @"Should return subject");
    XCTAssertNotNil(subject.reviewState, @"Should have review state");
}

#pragma mark - Review State Machine

- (void)testTransitionNoneToReview {
    [self.service submitReport:@"did:web:localhost:~bob"
                   subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/xyz"
                  reporterDID:@"did:web:localhost:~alice"
                   reasonType:@"com.atproto.moderation.defs#reasonSpam"
                      comment:nil
                        error:nil];

    NSError *error = nil;
    BOOL transitioned = [self.service updateReviewState:@"did:web:localhost:~bob"
                                            subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/xyz"
                                              newState:@"review"
                                                  error:&error];
    XCTAssertTrue(transitioned, @"Transition from none to review should succeed");
    XCTAssertNil(error);

    TutorialModerationSubject *subject = [self.service getSubject:@"did:web:localhost:~bob"
                                                       subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/xyz"
                                                            error:nil];
    XCTAssertEqualObjects(subject.reviewState, @"review", @"State should be review");
}

- (void)testFullStateMachineCycle {
    NSString *subjectDID = @"did:web:localhost:~bob";
    NSString *subjectURI = @"at://did:web:localhost:~bob/app.bsky.feed.post/cycle";

    // none -> review
    [self.service submitReport:subjectDID subjectURI:subjectURI reporterDID:@"did:web:localhost:~alice" reasonType:@"com.atproto.moderation.defs#reasonSpam" comment:nil error:nil];
    [self.service updateReviewState:subjectDID subjectURI:subjectURI newState:@"review" error:nil];

    // review -> escalated
    [self.service updateReviewState:subjectDID subjectURI:subjectURI newState:@"escalated" error:nil];
    TutorialModerationSubject *subject = [self.service getSubject:subjectDID subjectURI:subjectURI error:nil];
    XCTAssertEqualObjects(subject.reviewState, @"escalated");

    // escalated -> resolved
    [self.service updateReviewState:subjectDID subjectURI:subjectURI newState:@"resolved" error:nil];
    subject = [self.service getSubject:subjectDID subjectURI:subjectURI error:nil];
    XCTAssertEqualObjects(subject.reviewState, @"resolved");
}

- (void)testAppealReopensCase {
    NSString *subjectDID = @"did:web:localhost:~bob";
    NSString *subjectURI = @"at://did:web:localhost:~bob/app.bsky.feed.post/appeal";

    [self.service submitReport:subjectDID subjectURI:subjectURI reporterDID:@"did:web:localhost:~alice" reasonType:@"com.atproto.moderation.defs#reasonSpam" comment:nil error:nil];
    [self.service updateReviewState:subjectDID subjectURI:subjectURI newState:@"review" error:nil];
    [self.service updateReviewState:subjectDID subjectURI:subjectURI newState:@"resolved" error:nil];

    // Appeal should reopen (resolved -> review)
    NSError *error = nil;
    BOOL appealed = [self.service updateReviewState:subjectDID subjectURI:subjectURI newState:@"review" error:&error];
    XCTAssertTrue(appealed, @"Appeal should reopen the case");
    XCTAssertNil(error);

    TutorialModerationSubject *subject = [self.service getSubject:subjectDID subjectURI:subjectURI error:nil];
    XCTAssertEqualObjects(subject.reviewState, @"review", @"State should be back to review after appeal");
}

- (void)testListReportsForSubject {
    [self.service submitReport:@"did:web:localhost:~bob"
                   subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                  reporterDID:@"did:web:localhost:~alice"
                   reasonType:@"com.atproto.moderation.defs#reasonSpam"
                      comment:nil
                        error:nil];
    [self.service submitReport:@"did:web:localhost:~bob"
                   subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                  reporterDID:@"did:web:localhost:~carol"
                   reasonType:@"com.atproto.moderation.defs#reasonAdult"
                      comment:@"NSFW"
                        error:nil];

    NSError *error = nil;
    NSArray *reports = [self.service listReportsForSubject:@"did:web:localhost:~bob"
                                               subjectURI:@"at://did:web:localhost:~bob/app.bsky.feed.post/abc"
                                                    error:&error];
    XCTAssertNotNil(reports);
    XCTAssertEqual(reports.count, 2, @"Should have 2 reports for subject");
}

@end
