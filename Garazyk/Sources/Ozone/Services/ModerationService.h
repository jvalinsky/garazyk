// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

/**
 * @abstract Service layer for Ozone moderation events, subject state, team data, and settings.
 */
@interface ModerationService : NSObject

/**
 * @abstract Creates a moderation service backed by a query database.
 * @param database Database used for moderation queries and mutations.
 */
- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

#pragma mark - Core Moderation Events

/**
 * @abstract Emits a moderation event authored by an administrator.
 */
- (nullable NSDictionary *)emitModerationEvent:(NSDictionary *)event
                                     createdBy:(NSString *)adminDid
                                         error:(NSError **)error;

/**
 * @abstract Queries moderation subject statuses using filter, limit, and cursor arguments.
 */
- (nullable NSDictionary *)queryModerationStatuses:(NSDictionary *)filters
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error;

/**
 * @abstract Queries moderation events using filter, limit, and cursor arguments.
 */
- (nullable NSDictionary *)queryModerationEvents:(NSDictionary *)filters
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

/**
 * @abstract Loads one moderation event by identifier.
 */
- (nullable NSDictionary *)getModerationEvent:(NSString *)eventId
                                        error:(NSError **)error;

#pragma mark - Subject Information

/**
 * @abstract Loads moderation metadata for a record URI.
 */
- (nullable NSDictionary *)getModerationRecord:(NSString *)uri
                                         error:(NSError **)error;

/**
 * @abstract Loads moderation metadata for multiple record URIs.
 */
- (nullable NSArray<NSDictionary *> *)getModerationRecords:(NSArray<NSString *> *)uris
                                                     error:(NSError **)error;

/**
 * @abstract Loads moderation metadata for one repository DID.
 */
- (nullable NSDictionary *)getModerationRepo:(NSString *)did
                                       error:(NSError **)error;

/**
 * @abstract Loads moderation metadata for multiple repository DIDs.
 */
- (nullable NSArray<NSDictionary *> *)getModerationRepos:(NSArray<NSString *> *)dids
                                                   error:(NSError **)error;

/**
 * @abstract Searches moderated repositories with optional filters and pagination.
 */
- (nullable NSDictionary *)searchModerationRepos:(NSDictionary *)filters
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error;

#pragma mark - Subject Status

/**
 * @abstract Loads moderation status for one subject identifier.
 */
- (nullable NSDictionary *)getSubjectStatus:(NSString *)subject
                                      error:(NSError **)error;

/**
 * @abstract Loads moderation statuses for multiple subject identifiers.
 */
- (nullable NSArray<NSDictionary *> *)getSubjectStatuses:(NSArray<NSString *> *)subjects
                                                   error:(NSError **)error;

#pragma mark - Statistics & Analytics

/**
 * @abstract Returns moderation reporting statistics for a reporter DID.
 */
- (nullable NSDictionary *)getReporterStats:(NSString *)reporterDid
                                      error:(NSError **)error;

/**
 * @abstract Returns moderation timeline entries for an account.
 */
- (nullable NSDictionary *)getAccountTimeline:(NSString *)did
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                        error:(NSError **)error;

#pragma mark - Scheduled Actions

/**
 * @abstract Schedules a moderation action created by an administrator.
 */
- (nullable NSDictionary *)scheduleAction:(NSDictionary *)action
                             createdBy:(NSString *)adminDid
                                 error:(NSError **)error;

/**
 * @abstract Lists scheduled moderation actions matching the supplied filters.
 */
- (nullable NSArray<NSDictionary *> *)listScheduledActions:(NSDictionary *)filters
                                                     error:(NSError **)error;

/**
 * @abstract Cancels one scheduled moderation action.
 */
- (BOOL)cancelScheduledAction:(NSString *)actionId
                    cancelledBy:(NSString *)adminDid
                          error:(NSError **)error;

/**
 * @abstract Cancels scheduled actions for the supplied subjects.
 */
- (nullable NSDictionary *)cancelScheduledActions:(NSArray<NSString *> *)subjects
                                          comment:(nullable NSString *)comment
                                      cancelledBy:(NSString *)adminDid
                                            error:(NSError **)error;

/**
 * @abstract Loads subject records for the supplied subject identifiers.
 */
- (nullable NSArray<NSDictionary *> *)getSubjects:(NSArray<NSString *> *)subjects
                                            error:(NSError **)error;

#pragma mark - Team Management

/**
 * @abstract Adds a moderation team member.
 */
- (nullable NSString *)addTeamMember:(NSDictionary *)member
                           createdBy:(NSString *)adminDid
                               error:(NSError **)error;

/**
 * @abstract Updates a moderation team member role.
 */
- (BOOL)updateTeamMember:(NSString *)memberId
            newRole:(NSString *)role
           updatedBy:(NSString *)adminDid
               error:(NSError **)error;

/**
 * @abstract Removes a moderation team member.
 */
- (BOOL)removeTeamMember:(NSString *)memberId
               removedBy:(NSString *)adminDid
                  error:(NSError **)error;

/**
 * @abstract Lists moderation team members.
 */
- (nullable NSArray<NSDictionary *> *)listTeamMembers:(NSError **)error;

#pragma mark - Set Management

/**
 * @abstract Creates a named moderation set.
 */
- (nullable NSString *)createSet:(NSDictionary *)set
                       createdBy:(NSString *)adminDid
                           error:(NSError **)error;

/**
 * @abstract Updates a moderation set's name or values.
 */
- (BOOL)updateSet:(NSString *)setId
          newName:(nullable NSString *)name
        newValues:(nullable NSArray *)values
        updatedBy:(NSString *)adminDid
            error:(NSError **)error;

/**
 * @abstract Deletes a moderation set.
 */
- (BOOL)deleteSet:(NSString *)setId
        deletedBy:(NSString *)adminDid
            error:(NSError **)error;

/**
 * @abstract Loads one moderation set.
 */
- (nullable NSDictionary *)getSet:(NSString *)setId
                             error:(NSError **)error;

/**
 * @abstract Lists moderation sets.
 */
- (nullable NSArray<NSDictionary *> *)listSets:(NSError **)error;

/**
 * @abstract Adds values to a moderation set.
 */
- (BOOL)addSetValues:(NSString *)setId
              values:(NSArray *)values
           addedBy:(NSString *)adminDid
               error:(NSError **)error;

/**
 * @abstract Removes values from a moderation set.
 */
- (BOOL)deleteSetValues:(NSString *)setId
                values:(NSArray *)values
             deletedBy:(NSString *)adminDid
                 error:(NSError **)error;

/**
 * @abstract Lists values in a moderation set.
 */
- (nullable NSDictionary *)getSetValues:(NSString *)setId
                                  limit:(NSInteger)limit
                                 cursor:(nullable NSString *)cursor
                                  error:(NSError **)error;

/**
 * @abstract Queries moderation sets by optional name prefix.
 */
- (nullable NSDictionary *)querySets:(NSInteger)limit
                              cursor:(nullable NSString *)cursor
                          namePrefix:(nullable NSString *)namePrefix
                              error:(NSError **)error;

#pragma mark - Communication Templates

/**
 * @abstract Creates a moderator communication template.
 */
- (nullable NSString *)createCommunicationTemplate:(NSDictionary *)templateDict
                                         createdBy:(NSString *)adminDid
                                             error:(NSError **)error;

/**
 * @abstract Updates a moderator communication template.
 */
- (BOOL)updateCommunicationTemplate:(NSString *)templateId
                            newName:(nullable NSString *)name
                           newText:(nullable NSString *)text
                        updatedBy:(NSString *)adminDid
                              error:(NSError **)error;

/**
 * @abstract Deletes a moderator communication template.
 */
- (BOOL)deleteCommunicationTemplate:(NSString *)templateId
                          deletedBy:(NSString *)adminDid
                               error:(NSError **)error;

/**
 * @abstract Lists moderator communication templates.
 */
- (nullable NSArray<NSDictionary *> *)listCommunicationTemplates:(NSError **)error;

#pragma mark - Verification

/**
 * @abstract Grants verification to an account DID.
 */
- (nullable NSString *)grantVerification:(NSString *)did
                               grantedBy:(NSString *)adminDid
                                   error:(NSError **)error;

/**
 * @abstract Revokes verification from an account DID.
 */
- (BOOL)revokeVerification:(NSString *)did
                revokedBy:(NSString *)adminDid
                    error:(NSError **)error;

/**
 * @abstract Lists verified account DIDs.
 */
- (nullable NSArray<NSString *> *)listVerifications:(NSError **)error;

#pragma mark - Safelinks

/**
 * @abstract Creates a safelink moderation rule.
 */
- (nullable NSString *)createSafelink:(NSDictionary *)safelink
                            createdBy:(NSString *)adminDid
                                error:(NSError **)error;

/**
 * @abstract Updates a safelink URL or action.
 */
- (BOOL)updateSafelink:(NSString *)safelinkId
               newUrl:(nullable NSString *)url
            newAction:(nullable NSString *)action
          updatedBy:(NSString *)adminDid
               error:(NSError **)error;

/**
 * @abstract Deletes a safelink rule.
 */
- (BOOL)deleteSafelink:(NSString *)safelinkId
            deletedBy:(NSString *)adminDid
                error:(NSError **)error;

/**
 * @abstract Loads one safelink rule.
 */
- (nullable NSDictionary *)getSafelink:(NSString *)safelinkId
                                  error:(NSError **)error;

/**
 * @abstract Lists safelink rules.
 */
- (nullable NSArray<NSDictionary *> *)listSafelinks:(NSError **)error;

#pragma mark - Signatures

/**
 * @abstract Loads one content signature record.
 */
- (nullable NSDictionary *)getSignature:(NSString *)signatureId
                                  error:(NSError **)error;

/**
 * @abstract Lists content signature records.
 */
- (nullable NSArray<NSDictionary *> *)listSignatures:(NSError **)error;

/**
 * @abstract Records that a signature matched an account DID.
 */
- (BOOL)reportSignatureMatch:(NSString *)signatureId
                    matchDid:(NSString *)did
                 reportedBy:(NSString *)adminDid
                       error:(NSError **)error;

#pragma mark - Settings

/**
 * @abstract Loads moderation server configuration.
 */
- (nullable NSDictionary *)getServerConfig:(NSError **)error;

/**
 * @abstract Updates moderation server settings.
 */
- (BOOL)updateServerSettings:(NSDictionary *)settings
                   updatedBy:(NSString *)adminDid
                       error:(NSError **)error;

#pragma mark - Hosting History

/**
 * @abstract Returns hosting history entries for an account DID.
 */
- (nullable NSArray<NSDictionary *> *)getAccountHostingHistory:(NSString *)did
                                                         limit:(NSInteger)limit
                                                        cursor:(nullable NSString *)cursor
                                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
