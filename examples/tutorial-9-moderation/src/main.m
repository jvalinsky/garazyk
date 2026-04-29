#import <Foundation/Foundation.h>
#import "TutorialModerationService.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLog(@"Tutorial 9: Moderation & Ozone");
        NSLog(@"==============================\n");

        NSError *error = nil;

        // Setup database
        NSString *dbPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tutorial-9-moderation.db"];
        [[NSFileManager defaultManager] removeItemAtPath:dbPath error:nil];

        TutorialModerationService *mod = [[TutorialModerationService alloc] initWithDatabasePath:dbPath];

        NSString *subjectDID = @"did:web:localhost:~bob";
        NSString *subjectURI = @"at://did:web:localhost:~bob/app.bsky.feed.post/abc123";
        NSString *reporterDID = @"did:web:localhost:~alice";
        NSString *moderatorDID = @"did:web:localhost:2583";

        // ============================================================
        // 1. Submit a report
        // ============================================================
        NSLog(@"1. Submit a report");
        NSLog(@"-------------------");

        int64_t reportId = [mod submitReport:subjectDID
                                   subjectURI:subjectURI
                                  reporterDID:reporterDID
                                   reasonType:@"com.atproto.moderation.defs#reasonSpam"
                                      comment:@"This post is spam"
                                        error:&error];
        if (reportId > 0) {
            NSLog(@"Report submitted: ID=%lld", reportId);
        } else {
            NSLog(@"Report failed: %@", error.localizedDescription);
            return 1;
        }

        // Submit another report for the same subject
        int64_t reportId2 = [mod submitReport:subjectDID
                                   subjectURI:subjectURI
                                  reporterDID:@"did:web:localhost:~carol"
                                   reasonType:@"com.atproto.moderation.defs#reasonViolation"
                                      comment:@"Violates community guidelines"
                                        error:&error];
        NSLog(@"Second report submitted: ID=%lld\n", reportId2);

        // ============================================================
        // 2. View subject status
        // ============================================================
        NSLog(@"2. View subject status");
        NSLog(@"----------------------");

        TutorialModerationSubject *subject = [mod getSubject:subjectDID subjectURI:subjectURI error:&error];
        if (subject) {
            NSLog(@"Subject: %@ %@", subject.subjectDID, subject.subjectURI ?: @"");
            NSLog(@"  Review state: %@", subject.reviewState);
            NSLog(@"  Reports: %lu", (unsigned long)subject.reports.count);
            NSLog(@"  Labels: %lu\n", (unsigned long)subject.labels.count);
        }

        // ============================================================
        // 3. Apply labels
        // ============================================================
        NSLog(@"3. Apply labels");
        NSLog(@"---------------");

        [mod addLabel:subjectDID
            subjectURI:subjectURI
            labelValue:@"spam"
             labeledBy:moderatorDID
                 error:&error];
        NSLog(@"Applied 'spam' label");

        [mod addLabel:subjectDID
            subjectURI:subjectURI
            labelValue:@"!warn"
             labeledBy:moderatorDID
                 error:&error];
        NSLog(@"Applied '!warn' label (negation prefix)\n");

        // ============================================================
        // 4. Review state machine
        // ============================================================
        NSLog(@"4. Review state machine");
        NSLog(@"-----------------------");

        // Current state: review (auto-transitioned on report)
        subject = [mod getSubject:subjectDID subjectURI:subjectURI error:nil];
        NSLog(@"Current state: %@", subject.reviewState);

        // Escalate
        BOOL escalated = [mod updateReviewState:subjectDID subjectURI:subjectURI newState:@"escalated" error:&error];
        if (escalated) {
            NSLog(@"Escalated -> 'escalated'");
        }

        // Resolve
        BOOL resolved = [mod updateReviewState:subjectDID subjectURI:subjectURI newState:@"resolved" error:&error];
        if (resolved) {
            NSLog(@"Resolved -> 'resolved'");
        }

        // Try invalid transition (resolved -> escalated)
        BOOL invalid = [mod updateReviewState:subjectDID subjectURI:subjectURI newState:@"escalated" error:&error];
        if (!invalid) {
            NSLog(@"Invalid transition correctly rejected: %@\n", error.localizedDescription);
        }

        // Reopen (appeal)
        BOOL reopened = [mod updateReviewState:subjectDID subjectURI:subjectURI newState:@"review" error:&error];
        if (reopened) {
            NSLog(@"Appeal -> 'review' (reopened)\n");
        }

        // ============================================================
        // 5. Label taxonomy
        // ============================================================
        NSLog(@"5. Label taxonomy");
        NSLog(@"-----------------");

        NSLog(@"ATProto label values:");
        NSLog(@"  Positive labels (applied):");
        NSLog(@"    spam     — Spam content");
        NSLog(@"    adult    — Adult content");
        NSLog(@"    nsfw     — Not safe for work");
        NSLog(@"    !warn    — Warning/negation");
        NSLog(@"    !hide    — Content hidden");
        NSLog(@"    !takedown — Content taken down");
        NSLog(@"");
        NSLog(@"  Negation labels (prefixed with '!') remove the label:");
        NSLog(@"    !spam    — Remove spam label");
        NSLog(@"    !adult   — Remove adult label");
        NSLog(@"");
        NSLog(@"  Custom labels can be defined by labelers:");
        NSLog(@"    my-labeler.custom — Custom label namespace\n");

        // ============================================================
        // 6. Final subject view
        // ============================================================
        NSLog(@"6. Final subject view");
        NSLog(@"---------------------");

        subject = [mod getSubject:subjectDID subjectURI:subjectURI error:&error];
        if (subject) {
            NSLog(@"Subject: %@ %@", subject.subjectDID, subject.subjectURI ?: @"");
            NSLog(@"  Review state: %@", subject.reviewState);
            NSLog(@"  Reports: %lu", (unsigned long)subject.reports.count);
            for (TutorialModerationReport *report in subject.reports) {
                NSLog(@"    #%lld: %@ by %@ — \"%@\"",
                      report.reportId, report.reasonType, report.reporterDID, report.comment ?: @"");
            }
            NSLog(@"  Labels: %lu", (unsigned long)subject.labels.count);
            for (TutorialModerationLabel *label in subject.labels) {
                NSLog(@"    %lld: '%@' by %@", label.labelId, label.labelValue, label.labeledBy);
            }
        }

        NSLog(@"\n==============================");
        NSLog(@"Tutorial completed!");
        NSLog(@"Key concepts:");
        NSLog(@"  - Report submission with reason types");
        NSLog(@"  - Label taxonomy (positive and negation labels)");
        NSLog(@"  - Review state machine (none -> review -> escalated -> resolved)");
        NSLog(@"  - Appeal/reopen path (resolved -> review)");
        NSLog(@"  - Subject aggregation (reports + labels in one view)");
    }

    return 0;
}
