#import "Network/XrpcMethodRegistry.h"
#import "Blob/BlobStorage.h"
#import "Core/DID.h"
#import "Identity/HandleResolver.h"
#import "AppView/ActorService.h"
#import "AppView/FeedService.h"
#import "AppView/NotificationService.h"

@implementation XrpcMethodRegistry

+ (void)registerMethodsWithDispatcher:(XrpcDispatcher *)dispatcher
                           controller:(PDSController *)controller {
    [dispatcher registerComAtprotoServerCreateAccount:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *email = body[@"email"];
        NSString *handle = body[@"handle"];
        NSString *password = body[@"password"];
        NSString *did = body[@"did"];

        if (!email || !password || !handle) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing email, handle, or password"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller createAccountForEmail:email
                                                         password:password
                                                          handle:handle
                                                             did:did
                                                            error:&error];

        if (error) {
            response.statusCode = 400;
            [response setJsonBody:@{@"error": @"AccountCreationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoServerCreateSession:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *identifier = body[@"identifier"];
        NSString *password = body[@"password"];

        if (!identifier || !password) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier or password"}];
            return;
        }

        NSString *handle = body[@"handle"];
        NSString *did = body[@"did"];

        NSError *error = nil;
        NSDictionary *session = [controller createSessionForIdentifier:identifier
                                                              password:password
                                                               handle:handle ?: identifier
                                                                 did:did ?: [NSString stringWithFormat:@"did:web:%@", identifier]
                                                                error:&error];

        if (error) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerComAtprotoServerRefreshSession:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *refreshToken = body[@"refreshToken"];

        if (!refreshToken) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing refreshToken"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *session = [controller refreshSessionWithRefreshToken:refreshToken error:&error];

        if (error) {
            response.statusCode = 401;
            [response setJsonBody:@{@"error": @"AuthenticationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:session];
    }];

    [dispatcher registerComAtprotoRepoCreateRecord:^(HttpRequest *request, HttpResponse *response) {
        NSLog(@"createRecord XRPC handler called");
        NSDictionary *body = request.jsonBody;
        NSString *repo = body[@"repo"];
        NSString *collection = body[@"collection"];
        NSDictionary *record = body[@"record"];

        NSLog(@"createRecord params: repo=%@, collection=%@, record=%@", repo, collection, record);

        if (!repo || !collection || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, or record"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller createRecordForDid:repo
                                                     collection:collection
                                                        record:record
                                                         error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoGetRecord:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSString *rkey = [request queryParamForKey:@"rkey"];

        if (!repo || !collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, or rkey"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller getRecordForDid:repo
                                                 collection:collection
                                                      rkey:rkey
                                                     error:&error];

        if (error) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoListRecords:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];
        NSString *collection = [request queryParamForKey:@"collection"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 50;
        NSString *cursor = [request queryParamForKey:@"cursor"];

        if (!repo || !collection) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo or collection"}];
            return;
        }

        NSError *error = nil;
        NSArray *records = [controller listRecordsForDid:repo
                                               collection:collection
                                                   limit:limit
                                                  cursor:cursor
                                                   error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"records": records}];
    }];

    [dispatcher registerComAtprotoRepoDeleteRecord:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *repo = body[@"repo"];
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];

        if (!repo || !collection || !rkey) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, or rkey"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [controller deleteRecordForDid:repo
                                            collection:collection
                                                 rkey:rkey
                                                error:&error];

        if (!success) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];

    [dispatcher registerComAtprotoRepoApplyWrites:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        if (!body) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing request body"}];
            return;
        }



        NSString *repo = body[@"repo"];
        NSArray *writes = body[@"writes"];
        NSNumber *validate = body[@"validate"];
        NSString *swapCommit = body[@"swapCommit"];

        if (!repo || !writes || writes.count == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing required fields: repo and writes"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller applyWrites:writes
                                                 repo:repo
                                             validate:validate.boolValue
                                           swapCommit:swapCommit
                                                error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ApplyWritesFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoDescribeRepo:^(HttpRequest *request, HttpResponse *response) {
        NSString *repo = [request queryParamForKey:@"repo"];

        if (!repo) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo parameter"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller describeRepo:repo error:&error];

        if (error) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoRepoPutRecord:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;
        NSString *repo = body[@"repo"];
        NSString *collection = body[@"collection"];
        NSString *rkey = body[@"rkey"];
        NSDictionary *record = body[@"record"];

        if (!repo || !collection || !rkey || !record) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing repo, collection, rkey, or record"}];
            return;
        }

        NSError *error = nil;
        BOOL success = [controller putRecordForDid:repo
                                                 collection:collection
                                                      rkey:rkey
                                                     record:record
                                                      error:&error];

        if (!success) {
            response.statusCode = error.code == 404 ? HttpStatusNotFound : HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"uri": [NSString stringWithFormat:@"at://%@/%@/%@", repo, collection, rkey]}];
    }];

    [dispatcher registerComAtprotoSyncGetRepo:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSData *repoData = [controller getRepoDataForDid:did error:&error];

        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/car";
        [response setBodyData:repoData];
    }];

    [dispatcher registerComAtprotoSyncGetHead:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSString *head = [controller getRepoHeadForDid:did error:&error];

        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"OperationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"root": head ?: [NSNull null]}];
    }];

    [dispatcher registerComAtprotoRepoUploadBlob:^(HttpRequest *request, HttpResponse *response) {
        // Extract DID from Authorization header (this would need proper auth implementation)
        // For now, we'll use a query parameter for testing
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        // Get the multipart form data
        NSDictionary *multipartData = request.multipartFormData;
        if (!multipartData || !multipartData[@"blob"]) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing blob data"}];
            return;
        }

        NSData *blobData = multipartData[@"blob"];

        // Extract MIME type from form data or use default
        NSString *mimeType = multipartData[@"mimeType"] ?: @"application/octet-stream";

        NSError *error = nil;
        NSDictionary *result = [controller uploadBlob:blobData mimeType:mimeType did:did error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobUploadFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoSyncGetBlob:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cid = [request queryParamForKey:@"cid"];

        if (!did || !cid) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did or cid"}];
            return;
        }

        NSError *error = nil;
        NSDictionary *result = [controller getBlobWithCID:cid did:did error:&error];

        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"BlobRetrievalFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        response.contentType = @"application/octet-stream"; // Should be the actual MIME type
        response.body = result[@"blob"];
    }];

    [dispatcher registerComAtprotoSyncListBlobs:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 100;
        limit = MIN(limit, 1000); // Cap at 1000

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did"}];
            return;
        }

        NSError *error = nil;
        NSArray *blobs = [controller listBlobsForDID:did limit:limit cursor:cursor error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"BlobListFailed", @"message": error.localizedDescription}];
            return;
        }

        NSDictionary *result = @{
            @"blobs": blobs,
            @"cursor": cursor ?: [NSNull null] // Would need proper cursor implementation
        };

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoIdentityResolveDid:^(HttpRequest *request, HttpResponse *response) {
        NSString *did = [request queryParamForKey:@"did"];

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing did parameter"}];
            return;
        }

        DIDResolver *resolver = [[DIDResolver alloc] init];
        NSError *error = nil;
        DIDDocument *doc = [resolver resolveDIDSync:did error:&error];

        // TODO: Support forceRefresh query parameter

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:doc.jsonDictionary];
    }];

    [dispatcher registerComAtprotoIdentityResolveIdentity:^(HttpRequest *request, HttpResponse *response) {
        NSString *identifier = [request queryParamForKey:@"identifier"];

        if (!identifier) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing identifier parameter"}];
            return;
        }

        DIDResolver *didResolver = [[DIDResolver alloc] init];
        HandleResolver *handleResolver = [[HandleResolver alloc] init];

        if ([identifier hasPrefix:@"did:"]) {
            // It's a DID, resolve directly
            NSError *error = nil;
            DIDDocument *doc = [didResolver resolveDIDSync:identifier error:&error];

            if (error) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": error.localizedDescription}];
                return;
            }

            NSDictionary *result = @{
                @"did": identifier,
                @"didDoc": doc.jsonDictionary
            };
            response.statusCode = HttpStatusOK;
            [response setJsonBody:result];
        } else {
            // It's a handle, resolve to DID then to document
            // For simplicity, resolve handle to DID, then DID to doc
            // TODO: Verify handle matches document's alsoKnownAs
            NSError *handleError = nil;
            __block NSString *did = nil;
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

            [handleResolver resolveHandle:identifier completion:^(NSString * _Nullable resolvedDid, NSError * _Nullable error) {
                did = resolvedDid;
                dispatch_semaphore_signal(semaphore);
            }];

            dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

            if (!did) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Handle resolution failed"}];
                return;
            }

            NSError *docError = nil;
            DIDDocument *doc = [didResolver resolveDIDSync:did error:&docError];

            if (docError) {
                response.statusCode = HttpStatusBadRequest;
                [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": docError.localizedDescription}];
                return;
            }

            NSDictionary *result = @{
                @"did": did,
                @"handle": identifier,
                @"didDoc": doc.jsonDictionary
            };
            response.statusCode = HttpStatusOK;
            [response setJsonBody:result];
        }
    }];

    [dispatcher registerComAtprotoIdentityResolveHandle:^(HttpRequest *request, HttpResponse *response) {
        NSString *handle = [request queryParamForKey:@"handle"];

        if (!handle) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing handle parameter"}];
            return;
        }

        HandleResolver *handleResolver = [[HandleResolver alloc] init];
        NSError *error = nil;
        __block NSString *did = nil;
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

        [handleResolver resolveHandle:handle completion:^(NSString * _Nullable resolvedDid, NSError * _Nullable resolveError) {
            did = resolvedDid;
            dispatch_semaphore_signal(semaphore);
        }];

        dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

        if (!did) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ResolutionFailed", @"message": @"Handle resolution failed"}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"did": did}];
    }];

    // Moderation endpoints
    [dispatcher registerComAtprotoAdminModerateAccount:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller moderateAccount:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoAdminModerateRecord:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller moderateRecord:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ModerationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    // Labeling endpoints
    [dispatcher registerComAtprotoLabelCreateLabel:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller createLabel:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LabelCreationFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];

    [dispatcher registerComAtprotoLabelGetLabels:^(HttpRequest *request, HttpResponse *response) {
        NSDictionary *body = request.jsonBody;

        NSError *error = nil;
        NSDictionary *result = [controller getLabels:body error:&error];

        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LabelRetrievalFailed", @"message": error.localizedDescription}];
            return;
        }

        response.statusCode = HttpStatusOK;
        [response setJsonBody:result];
    }];
    
    ActorService *actorService = [[ActorService alloc] initWithDatabase:controller.database];
    FeedService *feedService = [[FeedService alloc] initWithDatabase:controller.database];
    NotificationService *notificationService = [[NotificationService alloc] initWithDatabase:controller.database];
    
    [dispatcher registerAppBskyActorGetProfile:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *profile = [actorService getProfileForActor:actor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"ProfileNotFound", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:profile];
    }];
    
    [dispatcher registerAppBskyActorGetProfiles:^(HttpRequest *request, HttpResponse *response) {
        NSString *actorsParam = [request queryParamForKey:@"actors"];
        
        if (!actorsParam || actorsParam.length == 0) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actors parameter"}];
            return;
        }
        
        NSArray *actors = [actorsParam componentsSeparatedByString:@","];
        NSError *error = nil;
        NSArray *profiles = [actorService getProfilesForActors:actors error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"ProfilesQueryFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{@"profiles": profiles}];
    }];
    
    [dispatcher registerAppBskyActorGetPreferences:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *preferences = [actorService getPreferencesForActor:actor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"PreferencesNotFound", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:preferences];
    }];
    
    [dispatcher registerAppBskyActorPutPreferences:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSDictionary *body = request.jsonBody;
        NSDictionary *preferences = body[@"preferences"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        if (!preferences) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing preferences in body"}];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [actorService putPreferencesForActor:actor preferences:preferences error:&error];
        
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"PreferencesUpdateFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
    
    [dispatcher registerAppBskyFeedGetTimeline:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *timeline = [feedService getTimelineForActor:actor limit:limit cursor:cursor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"TimelineFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:timeline];
    }];
    
    [dispatcher registerAppBskyFeedGetAuthorFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        NSString *filter = [request queryParamForKey:@"filter"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *feed = [feedService getAuthorFeedForActor:actor limit:limit cursor:cursor filter:filter error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"FeedFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:feed];
    }];
    
    [dispatcher registerAppBskyFeedGetPostThread:^(HttpRequest *request, HttpResponse *response) {
        NSString *uri = [request queryParamForKey:@"uri"];
        NSInteger depth = [[request queryParamForKey:@"depth"] integerValue] ?: 6;
        
        if (!uri) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing uri parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *thread = [feedService getPostThread:uri depth:depth error:&error];
        
        if (error) {
            response.statusCode = HttpStatusNotFound;
            [response setJsonBody:@{@"error": @"ThreadNotFound", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:thread];
    }];
    
    [dispatcher registerAppBskyFeedGetFeed:^(HttpRequest *request, HttpResponse *response) {
        NSString *feed = [request queryParamForKey:@"feed"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        if (!feed) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing feed parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *feedResult = [feedService getFeed:feed limit:limit cursor:cursor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"FeedFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:feedResult];
    }];
    
    [dispatcher registerAppBskyFeedGetActorLikes:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSInteger limit = [[request queryParamForKey:@"limit"] integerValue] ?: 30;
        NSString *cursor = [request queryParamForKey:@"cursor"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        NSError *error = nil;
        NSDictionary *likes = [feedService getActorLikes:actor limit:limit cursor:cursor error:&error];
        
        if (error) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"LikesFetchFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:likes];
    }];
    
    [dispatcher registerAppBskyNotificationRegisterPush:^(HttpRequest *request, HttpResponse *response) {
        NSString *actor = [request queryParamForKey:@"actor"];
        NSDictionary *body = request.jsonBody;
        NSString *token = body[@"token"];
        NSString *platformToken = body[@"platformToken"];
        NSString *serviceEndpoint = body[@"serviceEndpoint"];
        
        if (!actor) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing actor parameter"}];
            return;
        }
        
        if (!token) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"InvalidRequest", @"message": @"Missing token in body"}];
            return;
        }
        
        NSError *error = nil;
        BOOL success = [notificationService registerPushForActor:actor
                                                      deviceToken:token
                                                    platformToken:platformToken
                                                    serviceEndpoint:serviceEndpoint ?: @""
                                                            error:&error];
        
        if (!success) {
            response.statusCode = HttpStatusBadRequest;
            [response setJsonBody:@{@"error": @"PushRegistrationFailed", @"message": error.localizedDescription}];
            return;
        }
        
        response.statusCode = HttpStatusOK;
        [response setJsonBody:@{}];
    }];
}
@end
