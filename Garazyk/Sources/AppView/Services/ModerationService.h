#import <Foundation/Foundation.h>
#import "Database/PDSQueryDatabase.h"

NS_ASSUME_NONNULL_BEGIN

@class PDSDatabase;

@interface ModerationService : NSObject

- (instancetype)initWithDatabase:(id<PDSQueryDatabase>)database;

#pragma mark - Core Moderation Events

- (nullable NSDictionary *)emitModerationEvent:(NSDictionary *)event
                                     createdBy:(NSString *)adminDid
                                         error:(NSError **)error;

- (nullable NSDictionary *)queryModerationStatuses:(NSDictionary *)filters
                                           limit:(NSInteger)limit
                                          cursor:(nullable NSString *)cursor
                                           error:(NSError **)error;

- (nullable NSDictionary *)queryModerationEvents:(NSDictionary *)filters
                                         limit:(NSInteger)limit
                                        cursor:(nullable NSString *)cursor
                                         error:(NSError **)error;

- (nullable NSDictionary *)getModerationEvent:(NSString *)eventId
                                        error:(NSError **)error;

#pragma mark - Subject Information

- (nullable NSDictionary *)getModerationRecord:(NSString *)uri
                                         error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getModerationRecords:(NSArray<NSString *> *)uris
                                                     error:(NSError **)error;

- (nullable NSDictionary *)getModerationRepo:(NSString *)did
                                       error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getModerationRepos:(NSArray<NSString *> *)dids
                                                   error:(NSError **)error;

- (nullable NSDictionary *)searchModerationRepos:(NSDictionary *)filters
                                          limit:(NSInteger)limit
                                         cursor:(nullable NSString *)cursor
                                          error:(NSError **)error;

#pragma mark - Subject Status

- (nullable NSDictionary *)getSubjectStatus:(NSString *)subject
                                      error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)getSubjectStatuses:(NSArray<NSString *> *)subjects
                                                   error:(NSError **)error;

#pragma mark - Statistics & Analytics

- (nullable NSDictionary *)getReporterStats:(NSString *)reporterDid
                                      error:(NSError **)error;

- (nullable NSDictionary *)getAccountTimeline:(NSString *)did
                                        limit:(NSInteger)limit
                                       cursor:(nullable NSString *)cursor
                                        error:(NSError **)error;

#pragma mark - Scheduled Actions

- (nullable NSString *)scheduleAction:(NSDictionary *)action
                            createdBy:(NSString *)adminDid
                                error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listScheduledActions:(NSDictionary *)filters
                                                     error:(NSError **)error;

- (BOOL)cancelScheduledAction:(NSString *)actionId
                    cancelledBy:(NSString *)adminDid
                          error:(NSError **)error;

#pragma mark - Team Management

- (nullable NSString *)addTeamMember:(NSDictionary *)member
                           createdBy:(NSString *)adminDid
                               error:(NSError **)error;

- (BOOL)updateTeamMember:(NSString *)memberId
            newRole:(NSString *)role
           updatedBy:(NSString *)adminDid
               error:(NSError **)error;

- (BOOL)removeTeamMember:(NSString *)memberId
               removedBy:(NSString *)adminDid
                  error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listTeamMembers:(NSError **)error;

#pragma mark - Set Management

- (nullable NSString *)createSet:(NSDictionary *)set
                       createdBy:(NSString *)adminDid
                           error:(NSError **)error;

- (BOOL)updateSet:(NSString *)setId
          newName:(nullable NSString *)name
        newValues:(nullable NSArray *)values
        updatedBy:(NSString *)adminDid
            error:(NSError **)error;

- (BOOL)deleteSet:(NSString *)setId
        deletedBy:(NSString *)adminDid
            error:(NSError **)error;

- (nullable NSDictionary *)getSet:(NSString *)setId
                             error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listSets:(NSError **)error;

- (BOOL)addSetValues:(NSString *)setId
              values:(NSArray *)values
           addedBy:(NSString *)adminDid
               error:(NSError **)error;

#pragma mark - Communication Templates

- (nullable NSString *)createCommunicationTemplate:(NSDictionary *)template
                                         createdBy:(NSString *)adminDid
                                             error:(NSError **)error;

- (BOOL)updateCommunicationTemplate:(NSString *)templateId
                            newName:(nullable NSString *)name
                           newText:(nullable NSString *)text
                        updatedBy:(NSString *)adminDid
                              error:(NSError **)error;

- (BOOL)deleteCommunicationTemplate:(NSString *)templateId
                          deletedBy:(NSString *)adminDid
                               error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listCommunicationTemplates:(NSError **)error;

#pragma mark - Verification

- (nullable NSString *)grantVerification:(NSString *)did
                               grantedBy:(NSString *)adminDid
                                   error:(NSError **)error;

- (BOOL)revokeVerification:(NSString *)did
                revokedBy:(NSString *)adminDid
                    error:(NSError **)error;

- (nullable NSArray<NSString *> *)listVerifications:(NSError **)error;

#pragma mark - Safelinks

- (nullable NSString *)createSafelink:(NSDictionary *)safelink
                            createdBy:(NSString *)adminDid
                                error:(NSError **)error;

- (BOOL)updateSafelink:(NSString *)safelinkId
               newUrl:(nullable NSString *)url
            newAction:(nullable NSString *)action
          updatedBy:(NSString *)adminDid
               error:(NSError **)error;

- (BOOL)deleteSafelink:(NSString *)safelinkId
            deletedBy:(NSString *)adminDid
                error:(NSError **)error;

- (nullable NSDictionary *)getSafelink:(NSString *)safelinkId
                                  error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listSafelinks:(NSError **)error;

#pragma mark - Signatures

- (nullable NSDictionary *)getSignature:(NSString *)signatureId
                                  error:(NSError **)error;

- (nullable NSArray<NSDictionary *> *)listSignatures:(NSError **)error;

- (BOOL)reportSignatureMatch:(NSString *)signatureId
                    matchDid:(NSString *)did
                 reportedBy:(NSString *)adminDid
                       error:(NSError **)error;

#pragma mark - Settings

- (nullable NSDictionary *)getServerConfig:(NSError **)error;

- (BOOL)updateServerSettings:(NSDictionary *)settings
                   updatedBy:(NSString *)adminDid
                       error:(NSError **)error;

#pragma mark - Hosting History

- (nullable NSArray<NSDictionary *> *)getAccountHostingHistory:(NSString *)did
                                                         limit:(NSInteger)limit
                                                        cursor:(nullable NSString *)cursor
                                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
