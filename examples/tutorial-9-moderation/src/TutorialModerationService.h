/*!
 @file TutorialModerationService.h

 @abstract Content moderation and labeling for tutorial examples.

 @discussion Implements moderation with:
 - Report submission and lifecycle tracking
 - Label taxonomy (atproto label values)
 - Subject review state machine
 - Moderation action tracking
 - Thread-safe via serial dispatch queue

 This is the educational version of the production moderation in
 Garazyk/Sources/Ozone/ (ModerationService, ModerationSubject).

 Key concepts:
 - Reports are submitted by users against subjects (accounts or records)
 - Labels are applied to subjects (e.g., "!warn", "!hide", "adult")
 - Review states: none, review, escalated, resolved
 - Actions: acknowledge, escalate, takedown, appeal, resolve
 - Label values prefixed with "!" are negated/removed

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class TutorialSQLiteHelper;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const TutorialModerationErrorDomain;

#pragma mark - Data Models

@interface TutorialModerationReport : NSObject
@property (nonatomic, assign) int64_t reportId;
@property (nonatomic, copy) NSString *subjectDID;
@property (nonatomic, copy, nullable) NSString *subjectURI;
@property (nonatomic, copy) NSString *reporterDID;
@property (nonatomic, copy) NSString *reasonType;
@property (nonatomic, copy, nullable) NSString *comment;
@property (nonatomic, assign) NSTimeInterval createdAt;
@end

@interface TutorialModerationLabel : NSObject
@property (nonatomic, assign) int64_t labelId;
@property (nonatomic, copy) NSString *subjectDID;
@property (nonatomic, copy, nullable) NSString *subjectURI;
@property (nonatomic, copy) NSString *labelValue;
@property (nonatomic, copy) NSString *labeledBy;
@property (nonatomic, assign) NSTimeInterval createdAt;
@end

@interface TutorialModerationSubject : NSObject
@property (nonatomic, copy) NSString *subjectDID;
@property (nonatomic, copy, nullable) NSString *subjectURI;
@property (nonatomic, copy) NSString *reviewState;  // "none", "review", "escalated", "resolved"
@property (nonatomic, strong) NSArray<TutorialModerationLabel *> *labels;
@property (nonatomic, strong) NSArray<TutorialModerationReport *> *reports;
@property (nonatomic, assign) NSTimeInterval lastReviewedAt;
@end

#pragma mark - Service

@interface TutorialModerationService : NSObject

/*!
 @method initWithDatabasePath:

 @abstract Creates a moderation service with a database.

 @param dbPath The path to the database file.
 @return A new moderation service instance.
 */
- (instancetype)initWithDatabasePath:(NSString *)dbPath;

/*!
 @method submitReport:subjectURI:reporterDID:reasonType:comment:error:

 @abstract Submits a moderation report.

 @param subjectDID The DID of the reported account.
 @param subjectURI Optional URI of the reported record.
 @param reporterDID The DID of the reporter.
 @param reasonType The reason (e.g., "com.atproto.moderation.defs#reasonSpam").
 @param comment Optional comment.
 @param error On failure, contains error details.
 @return The report ID, or 0 on failure.
 */
- (int64_t)submitReport:(NSString *)subjectDID
              subjectURI:(nullable NSString *)subjectURI
             reporterDID:(NSString *)reporterDID
              reasonType:(NSString *)reasonType
                 comment:(nullable NSString *)comment
                   error:(NSError **)error;

/*!
 @method addLabel:subjectURI:labelValue:labeledBy:error:

 @abstract Adds a label to a subject.

 @param subjectDID The DID of the subject.
 @param subjectURI Optional URI of the record.
 @param labelValue The label value (e.g., "!warn", "adult", "spam").
 @param labeledBy The DID of the labeling authority.
 @param error On failure, contains error details.
 @return YES on success.
 */
- (BOOL)addLabel:(NSString *)subjectDID
      subjectURI:(nullable NSString *)subjectURI
      labelValue:(NSString *)labelValue
       labeledBy:(NSString *)labeledBy
           error:(NSError **)error;

/*!
 @method getSubject:subjectURI:error:

 @abstract Gets a moderation subject with its labels and reports.

 @param subjectDID The DID of the subject.
 @param subjectURI Optional URI of the record.
 @param error On failure, contains error details.
 @return The moderation subject, or nil if not found.
 */
- (nullable TutorialModerationSubject *)getSubject:(NSString *)subjectDID
                                         subjectURI:(nullable NSString *)subjectURI
                                              error:(NSError **)error;

/*!
 @method updateReviewState:subjectURI:newState:error:

 @abstract Updates the review state of a subject.

 @discussion State transitions:
 - none -> review (acknowledge)
 - review -> escalated
 - review -> resolved
 - escalated -> resolved
 - resolved -> review (appeal/reopen)

 @param subjectDID The DID of the subject.
 @param subjectURI Optional URI of the record.
 @param newState The new review state.
 @param error On failure, contains error details.
 @return YES on success.
 */
- (BOOL)updateReviewState:(NSString *)subjectDID
               subjectURI:(nullable NSString *)subjectURI
                newState:(NSString *)newState
                    error:(NSError **)error;

/*!
 @method listReportsForSubject:subjectURI:error:

 @abstract Lists reports for a subject.

 @param subjectDID The DID of the subject.
 @param subjectURI Optional URI of the record.
 @param error On failure, contains error details.
 @return Array of reports.
 */
- (nullable NSArray<TutorialModerationReport *> *)listReportsForSubject:(NSString *)subjectDID
                                                             subjectURI:(nullable NSString *)subjectURI
                                                                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
