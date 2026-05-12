#import "TutorialModerationService.h"
#import "TutorialSQLiteHelper.h"

NSString * const TutorialModerationErrorDomain = @"com.atproto.tutorial.moderation";

@implementation TutorialModerationReport
@end

@implementation TutorialModerationLabel
@end

@implementation TutorialModerationSubject
@end

@interface TutorialModerationService ()
@property (nonatomic, strong) TutorialSQLiteHelper *db;
@end

@implementation TutorialModerationService

- (instancetype)initWithDatabasePath:(NSString *)dbPath {
    self = [super init];
    if (!self) return nil;

    _db = [[TutorialSQLiteHelper alloc] initWithPath:dbPath];
    if (!_db) return nil;

    [self createTablesIfNeeded];
    return self;
}

- (void)createTablesIfNeeded {
    NSError *error = nil;
    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS moderation_reports ("
        @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
        @"subject_did TEXT NOT NULL, "
        @"subject_uri TEXT, "
        @"reporter_did TEXT NOT NULL, "
        @"reason_type TEXT NOT NULL, "
        @"comment TEXT, "
        @"created_at REAL NOT NULL"
        @")"];
    [self.db executeUpdate:&error sql:@"CREATE INDEX IF NOT EXISTS idx_reports_subject ON moderation_reports(subject_did, subject_uri)"];

    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS moderation_labels ("
        @"id INTEGER PRIMARY KEY AUTOINCREMENT, "
        @"subject_did TEXT NOT NULL, "
        @"subject_uri TEXT, "
        @"label_value TEXT NOT NULL, "
        @"labeled_by TEXT NOT NULL, "
        @"created_at REAL NOT NULL"
        @")"];
    [self.db executeUpdate:&error sql:@"CREATE INDEX IF NOT EXISTS idx_labels_subject ON moderation_labels(subject_did, subject_uri)"];

    [self.db executeUpdate:&error sql:@"CREATE TABLE IF NOT EXISTS moderation_subjects ("
        @"subject_did TEXT NOT NULL, "
        @"subject_uri TEXT, "
        @"review_state TEXT NOT NULL DEFAULT 'none', "
        @"last_reviewed_at REAL, "
        @"PRIMARY KEY(subject_did, subject_uri)"
        @")"];
}

- (int64_t)submitReport:(NSString *)subjectDID
              subjectURI:(nullable NSString *)subjectURI
             reporterDID:(NSString *)reporterDID
              reasonType:(NSString *)reasonType
                 comment:(nullable NSString *)comment
                   error:(NSError **)error {
    __block int64_t reportId = 0;

    [self.db executeSync:error block:^(sqlite3 *db) {
        const char *sql = "INSERT INTO moderation_reports (subject_did, subject_uri, reporter_did, reason_type, comment, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [NSError errorWithDomain:TutorialModerationErrorDomain code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [reporterDID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, [reasonType UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 5, [comment UTF8String] ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 6, [[NSDate date] timeIntervalSince1970]);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc == SQLITE_DONE) {
            reportId = sqlite3_last_insert_rowid(db);
            // Auto-transition subject to "review" state
            [self ensureSubject:subjectDID subjectURI:subjectURI db:db];
        } else if (error) {
            *error = [NSError errorWithDomain:TutorialModerationErrorDomain code:rc userInfo:nil];
        }
    }];

    return reportId;
}

- (BOOL)addLabel:(NSString *)subjectDID
      subjectURI:(nullable NSString *)subjectURI
      labelValue:(NSString *)labelValue
       labeledBy:(NSString *)labeledBy
           error:(NSError **)error {
    __block BOOL success = NO;

    [self.db executeSync:error block:^(sqlite3 *db) {
        const char *sql = "INSERT INTO moderation_labels (subject_did, subject_uri, label_value, labeled_by, created_at) "
            "VALUES (?, ?, ?, ?, ?)";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) return;

        sqlite3_bind_text(stmt, 1, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 3, [labelValue UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, [labeledBy UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 5, [[NSDate date] timeIntervalSince1970]);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);
        success = (rc == SQLITE_DONE);

        // Ensure subject exists
        if (success) {
            [self ensureSubject:subjectDID subjectURI:subjectURI db:db];
        }
    }];

    return success;
}

- (nullable TutorialModerationSubject *)getSubject:(NSString *)subjectDID
                                         subjectURI:(nullable NSString *)subjectURI
                                              error:(NSError **)error {
    return [self.db executeUnsafeRawQuery:error block:^id(sqlite3 *db) {
        // Get subject state
        const char *sql = "SELECT review_state, last_reviewed_at FROM moderation_subjects "
            "WHERE subject_did = ? AND COALESCE(subject_uri, '') = ?";
        sqlite3_stmt *stmt;
        if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return nil;

        sqlite3_bind_text(stmt, 1, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);

        TutorialModerationSubject *subject = nil;
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            subject = [[TutorialModerationSubject alloc] init];
            subject.subjectDID = subjectDID;
            subject.subjectURI = subjectURI;
            subject.reviewState = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 0)];
            subject.lastReviewedAt = sqlite3_column_double(stmt, 1);
        }
        sqlite3_finalize(stmt);

        if (!subject) return nil;

        // Get labels
        subject.labels = [self queryLabelsForSubject:subjectDID subjectURI:subjectURI db:db];

        // Get reports
        subject.reports = [self queryReportsForSubject:subjectDID subjectURI:subjectURI db:db];

        return subject;
    }];
}

- (BOOL)updateReviewState:(NSString *)subjectDID
               subjectURI:(nullable NSString *)subjectURI
                newState:(NSString *)newState
                    error:(NSError **)error {
    // Validate state transition
    TutorialModerationSubject *subject = [self getSubject:subjectDID subjectURI:subjectURI error:nil];
    NSString *currentState = subject ? subject.reviewState : @"none";

    if (![self isValidTransition:currentState to:newState]) {
        if (error) {
            *error = [NSError errorWithDomain:TutorialModerationErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Invalid transition: %@ -> %@", currentState, newState]}];
        }
        return NO;
    }

    return [self.db executeSync:error block:^(sqlite3 *db) {
        const char *sql = "UPDATE moderation_subjects SET review_state = ?, last_reviewed_at = ? "
            "WHERE subject_did = ? AND COALESCE(subject_uri, '') = ?";
        sqlite3_stmt *stmt;
        int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, NULL);
        if (rc != SQLITE_OK) {
            if (error) *error = [NSError errorWithDomain:TutorialModerationErrorDomain code:rc userInfo:nil];
            return;
        }

        sqlite3_bind_text(stmt, 1, [newState UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_double(stmt, 2, [[NSDate date] timeIntervalSince1970]);
        sqlite3_bind_text(stmt, 3, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 4, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);

        rc = sqlite3_step(stmt);
        sqlite3_finalize(stmt);

        if (rc != SQLITE_DONE && error) {
            *error = [NSError errorWithDomain:TutorialModerationErrorDomain code:rc userInfo:nil];
        }
    }];
}

- (nullable NSArray<TutorialModerationReport *> *)listReportsForSubject:(NSString *)subjectDID
                                                             subjectURI:(nullable NSString *)subjectURI
                                                                  error:(NSError **)error {
    return [self.db executeUnsafeRawQuery:error block:^id(sqlite3 *db) {
        return [self queryReportsForSubject:subjectDID subjectURI:subjectURI db:db];
    }];
}

#pragma mark - Private

- (void)ensureSubject:(NSString *)subjectDID subjectURI:(nullable NSString *)subjectURI db:(sqlite3 *)db {
    const char *sql = "INSERT OR IGNORE INTO moderation_subjects (subject_did, subject_uri, review_state) VALUES (?, ?, 'none')";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
    sqlite3_bind_text(stmt, 1, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);
    sqlite3_step(stmt);
    sqlite3_finalize(stmt);
}

- (NSArray<TutorialModerationLabel *> *)queryLabelsForSubject:(NSString *)subjectDID
                                                   subjectURI:(nullable NSString *)subjectURI
                                                           db:(sqlite3 *)db {
    const char *sql = "SELECT id, label_value, labeled_by, created_at FROM moderation_labels "
        "WHERE subject_did = ? AND COALESCE(subject_uri, '') = ?";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return @[];

    sqlite3_bind_text(stmt, 1, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);

    NSMutableArray *labels = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        TutorialModerationLabel *label = [[TutorialModerationLabel alloc] init];
        label.labelId = sqlite3_column_int64(stmt, 0);
        label.subjectDID = subjectDID;
        label.subjectURI = subjectURI;
        label.labelValue = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        label.labeledBy = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        label.createdAt = sqlite3_column_double(stmt, 3);
        [labels addObject:label];
    }
    sqlite3_finalize(stmt);
    return labels;
}

- (NSArray<TutorialModerationReport *> *)queryReportsForSubject:(NSString *)subjectDID
                                                    subjectURI:(nullable NSString *)subjectURI
                                                            db:(sqlite3 *)db {
    const char *sql = "SELECT id, reporter_did, reason_type, comment, created_at FROM moderation_reports "
        "WHERE subject_did = ? AND COALESCE(subject_uri, '') = ? ORDER BY created_at DESC";
    sqlite3_stmt *stmt;
    if (sqlite3_prepare_v2(db, sql, -1, &stmt, NULL) != SQLITE_OK) return @[];

    sqlite3_bind_text(stmt, 1, [subjectDID UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [subjectURI UTF8String] ?: "", -1, SQLITE_TRANSIENT);

    NSMutableArray *reports = [NSMutableArray array];
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        TutorialModerationReport *report = [[TutorialModerationReport alloc] init];
        report.reportId = sqlite3_column_int64(stmt, 0);
        report.subjectDID = subjectDID;
        report.subjectURI = subjectURI;
        report.reporterDID = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 1)];
        report.reasonType = [NSString stringWithUTF8String:(const char *)sqlite3_column_text(stmt, 2)];
        const char *comment = (const char *)sqlite3_column_text(stmt, 3);
        report.comment = comment ? [NSString stringWithUTF8String:comment] : nil;
        report.createdAt = sqlite3_column_double(stmt, 4);
        [reports addObject:report];
    }
    sqlite3_finalize(stmt);
    return reports;
}

- (BOOL)isValidTransition:(NSString *)from to:(NSString *)to {
    // Valid state transitions
    NSDictionary *validTransitions = @{
        @"none": [NSSet setWithArray:@[@"review"]],
        @"review": [NSSet setWithArray:@[@"escalated", @"resolved"]],
        @"escalated": [NSSet setWithArray:@[@"resolved"]],
        @"resolved": [NSSet setWithArray:@[@"review"]]  // Appeal/reopen
    };
    NSSet *allowed = validTransitions[from];
    return allowed && [allowed containsObject:to];
}

@end
