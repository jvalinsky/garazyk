#import "AdminAuthXrpcTestBase.h"
#import "Database/ActorStore/ActorStore.h"
#import "Database/Pool/DatabasePool.h"
#import "PDSHttpTestUtilities.h"
#import "Repository/CAR.h"
#import "Repository/CBOR.h"

@interface AdminAuthSyncTests : AdminAuthXrpcTestBase
@end

@implementation AdminAuthSyncTests

- (nullable NSString *)commitRevFromCARData:(NSData *)carData {
  NSError *carError = nil;
  CARReader *reader = [CARReader readFromData:carData error:&carError];
  XCTAssertNil(carError);
  XCTAssertNotNil(reader);
  if (!reader) {
    return nil;
  }

  CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
  XCTAssertNotNil(commitBlock);
  if (!commitBlock) {
    return nil;
  }

  CBORValue *commitValue = [CBORValue decode:commitBlock.data];
  XCTAssertNotNil(commitValue);
  XCTAssertEqual(commitValue.type, CBORTypeMap);
  if (!commitValue || commitValue.type != CBORTypeMap) {
    return nil;
  }

  CBORValue *revValue = commitValue.map[[CBORValue textString:@"rev"]];
  XCTAssertNotNil(revValue);
  XCTAssertEqual(revValue.type, CBORTypeTextString);
  return revValue.textString;
}

- (nullable CID *)commitDataCIDFromCARData:(NSData *)carData {
  NSError *carError = nil;
  CARReader *reader = [CARReader readFromData:carData error:&carError];
  XCTAssertNil(carError);
  XCTAssertNotNil(reader);
  if (!reader) {
    return nil;
  }

  CARBlock *commitBlock = [reader blockWithCID:reader.rootCID];
  XCTAssertNotNil(commitBlock);
  if (!commitBlock) {
    return nil;
  }

  CBORValue *commitValue = [CBORValue decode:commitBlock.data];
  XCTAssertNotNil(commitValue);
  XCTAssertEqual(commitValue.type, CBORTypeMap);
  if (!commitValue || commitValue.type != CBORTypeMap) {
    return nil;
  }

  CBORValue *dataValue = commitValue.map[[CBORValue textString:@"data"]];
  XCTAssertNotNil(dataValue);
  XCTAssertEqual(dataValue.type, CBORTypeTag);
  if (!dataValue || dataValue.type != CBORTypeTag) {
    return nil;
  }

  CBORValue *tagged = dataValue.tagValue;
  XCTAssertEqual(tagged.type, CBORTypeByteString);
  NSData *tagBytes = tagged.byteString;
  XCTAssertTrue(tagBytes.length > 1);
  if (tagged.type != CBORTypeByteString || tagBytes.length <= 1) {
    return nil;
  }

  NSData *rawCID =
      [tagBytes subdataWithRange:NSMakeRange(1, tagBytes.length - 1)];
  return [CID cidFromBytes:rawCID];
}

- (BOOL)carData:(NSData *)carData
    containsBlockWithCIDString:(NSString *)cidString {
  NSError *parseError = nil;
  CARReader *reader = [CARReader readFromData:carData error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(reader);
  if (!reader) {
    return NO;
  }

  for (CARBlock *block in reader.blocks) {
    if ([block.cid.stringValue isEqualToString:cidString]) {
      return YES;
    }
  }
  return NO;
}

- (void)testApplicationSyncGetRepoReturnsCARWithoutAuth {
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"application sync getRepo",
    @"createdAt" : [self iso8601String]
  };
  NSDictionary *created = [self.application.legacyController
      createRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                  record:record
          validationMode:PDSValidationModeOff
                   error:nil];
  XCTAssertNotNil(created);

  NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
  HttpResponse *response =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:query
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(response.statusCode, 200);
  XCTAssertEqualObjects(response.contentType, @"application/vnd.ipld.car");
  XCTAssertEqual(response.bodyFilePath.length, 0U);
  XCTAssertNotNil(response.bodyChunkProducer);
  XCTAssertNotNil(response.body);
  XCTAssertTrue(response.body.length > 0);
  if (response.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:response.bodyFilePath
                                               error:nil];
  }
}

- (void)testApplicationSyncGetRepoSinceCurrentRevReturnsEmptyDelta {
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"application sync since",
    @"createdAt" : [self iso8601String]
  };
  NSDictionary *created = [self.application.legacyController
      createRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                  record:record
          validationMode:PDSValidationModeOff
                   error:nil];
  XCTAssertNotNil(created);

  NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
  HttpResponse *fullResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:query
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(fullResponse.statusCode, 200);
  NSString *rev = [self commitRevFromCARData:fullResponse.body];
  XCTAssertNotNil(rev);
  if (fullResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:fullResponse.bodyFilePath
                                               error:nil];
  }

  NSString *deltaQuery =
      [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, rev];
  HttpResponse *deltaResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:deltaQuery
                       queryParams:@{@"did" : self.userDid, @"since" : rev}
                           headers:@{}];
  XCTAssertEqual(deltaResponse.statusCode, 200);
  XCTAssertEqualObjects(deltaResponse.contentType, @"application/vnd.ipld.car");

  NSError *parseError = nil;
  CARReader *reader =
      [CARReader readFromData:deltaResponse.body error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.blocks.count, 0U);
  if (deltaResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath
                                               error:nil];
  }
}

- (void)testApplicationSyncGetRepoUnknownSinceFallsBackToFull {
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"application unknown since",
    @"createdAt" : [self iso8601String]
  };
  NSDictionary *created = [self.application.legacyController
      createRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                  record:record
          validationMode:PDSValidationModeOff
                   error:nil];
  XCTAssertNotNil(created);

  NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
  HttpResponse *fullResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:query
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(fullResponse.statusCode, 200);

  NSError *fullParseError = nil;
  CARReader *fullReader =
      [CARReader readFromData:fullResponse.body error:&fullParseError];
  XCTAssertNil(fullParseError);
  XCTAssertNotNil(fullReader);
  if (fullResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:fullResponse.bodyFilePath
                                               error:nil];
  }

  NSString *unknownSinceQuery = [NSString
      stringWithFormat:@"did=%@&since=%@", self.userDid, @"3jzfcijpj2z2a"];
  HttpResponse *unknownResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:unknownSinceQuery
                       queryParams:@{
                         @"did" : self.userDid,
                         @"since" : @"3jzfcijpj2z2a"
                       }
                           headers:@{}];
  XCTAssertEqual(unknownResponse.statusCode, 200);
  XCTAssertEqualObjects(unknownResponse.contentType,
                        @"application/vnd.ipld.car");

  NSError *unknownParseError = nil;
  CARReader *unknownReader =
      [CARReader readFromData:unknownResponse.body error:&unknownParseError];
  XCTAssertNil(unknownParseError);
  XCTAssertNotNil(unknownReader);
  XCTAssertEqual(unknownReader.blocks.count, fullReader.blocks.count);
  if (unknownResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager]
        removeItemAtPath:unknownResponse.bodyFilePath
                   error:nil];
  }
}

- (void)testApplicationSyncGetRepoOlderSinceReturnsSmallerDeltaThanFull {
  for (NSUInteger i = 0; i < 30; i++) {
    NSDictionary *record = @{
      @"$type" : @"app.bsky.feed.post",
      @"text" : [NSString stringWithFormat:@"bulk-%lu", (unsigned long)i],
      @"createdAt" : [self iso8601String]
    };
    NSDictionary *created = [self.application.legacyController
        createRecordForDid:self.userDid
                collection:@"app.bsky.feed.post"
                    record:record
            validationMode:PDSValidationModeOff
                     error:nil];
    XCTAssertNotNil(created);
  }

  NSString *baselineQuery = [NSString stringWithFormat:@"did=%@", self.userDid];
  HttpResponse *baselineResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:baselineQuery
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(baselineResponse.statusCode, 200);
  NSString *baselineRev = [self commitRevFromCARData:baselineResponse.body];
  XCTAssertNotNil(baselineRev);
  if (baselineResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager]
        removeItemAtPath:baselineResponse.bodyFilePath
                   error:nil];
  }

  NSDictionary *deltaRecord = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"single-delta-change",
    @"createdAt" : [self iso8601String]
  };
  NSDictionary *createdDelta = [self.application.legacyController
      createRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                  record:deltaRecord
          validationMode:PDSValidationModeOff
                   error:nil];
  XCTAssertNotNil(createdDelta);

  NSString *deltaQuery =
      [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, baselineRev];
  HttpResponse *deltaResponse = [self
      sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                 queryString:deltaQuery
                 queryParams:@{@"did" : self.userDid, @"since" : baselineRev}
                     headers:@{}];
  XCTAssertEqual(deltaResponse.statusCode, 200);

  HttpResponse *fullAfterResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:baselineQuery
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(fullAfterResponse.statusCode, 200);

  NSError *deltaParseError = nil;
  CARReader *deltaReader =
      [CARReader readFromData:deltaResponse.body error:&deltaParseError];
  XCTAssertNil(deltaParseError);
  XCTAssertNotNil(deltaReader);

  NSError *fullParseError = nil;
  CARReader *fullReader =
      [CARReader readFromData:fullAfterResponse.body error:&fullParseError];
  XCTAssertNil(fullParseError);
  XCTAssertNotNil(fullReader);
  XCTAssertLessThan(deltaReader.blocks.count, fullReader.blocks.count);

  if (deltaResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath
                                               error:nil];
  }
  if (fullAfterResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager]
        removeItemAtPath:fullAfterResponse.bodyFilePath
                   error:nil];
  }
}

- (void)testApplicationSyncGetRepoSincePreDeleteRevOmitsDeletedRecordBlock {
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"delete-delta-target",
    @"createdAt" : [self iso8601String]
  };
  NSDictionary *created = [self.application.legacyController
      createRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                  record:record
          validationMode:PDSValidationModeOff
                   error:nil];
  XCTAssertNotNil(created);
  NSString *deletedCID = created[@"cid"];
  XCTAssertTrue(deletedCID.length > 0);

  NSString *fullQuery = [NSString stringWithFormat:@"did=%@", self.userDid];
  HttpResponse *beforeDeleteResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:fullQuery
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(beforeDeleteResponse.statusCode, 200);
  NSString *beforeDeleteRev =
      [self commitRevFromCARData:beforeDeleteResponse.body];
  XCTAssertNotNil(beforeDeleteRev);
  if (beforeDeleteResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager]
        removeItemAtPath:beforeDeleteResponse.bodyFilePath
                   error:nil];
  }

  NSString *uri = created[@"uri"];
  NSString *rkey = uri.pathComponents.lastObject;
  XCTAssertTrue(rkey.length > 0);
  BOOL deleted = [self.application.legacyController
      deleteRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                    rkey:rkey
                   error:nil];
  XCTAssertTrue(deleted);

  NSString *deltaQuery = [NSString
      stringWithFormat:@"did=%@&since=%@", self.userDid, beforeDeleteRev];
  HttpResponse *deltaResponse =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                       queryString:deltaQuery
                       queryParams:@{
                         @"did" : self.userDid,
                         @"since" : beforeDeleteRev
                       }
                           headers:@{}];
  XCTAssertEqual(deltaResponse.statusCode, 200);
  XCTAssertFalse(
      [self carData:deltaResponse.body containsBlockWithCIDString:deletedCID]);

  NSError *parseError = nil;
  CARReader *reader =
      [CARReader readFromData:deltaResponse.body error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(reader);
  XCTAssertGreaterThan(reader.blocks.count, 0U);

  CID *dataCID = [self commitDataCIDFromCARData:deltaResponse.body];
  XCTAssertNotNil(dataCID);
  XCTAssertNotNil([reader blockWithCID:dataCID]);

  if (deltaResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath
                                               error:nil];
  }
}

- (void)testApplicationSyncGetRepoSinceApplyWritesCreateRevReturnsEmptyDelta {
  NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
  NSDictionary *createWrite = @{
    @"action" : @"create",
    @"collection" : @"app.bsky.feed.post",
    @"rkey" : @"applywrites-since-create",
    @"value" : @{
      @"$type" : @"app.bsky.feed.post",
      @"text" : @"applyWrites create rev baseline",
      @"createdAt" : [self iso8601String]
    }
  };

  HttpResponse *applyResponse = [self
      sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                         body:@{@"writes" : @[ createWrite ], @"validate" : @NO}
                      headers:@{@"authorization" : authHeader}];
  XCTAssertEqual(applyResponse.statusCode, 200);
  NSDictionary *applyCommit = applyResponse.jsonBody[@"commit"];
  XCTAssertNotNil(applyCommit);
  XCTAssertTrue([applyCommit[@"cid"] length] > 0);
  XCTAssertTrue([applyCommit[@"rev"] length] > 0);

  PDSActorStore *store =
      [self.application.userDatabasePool storeForDid:self.userDid error:nil];
  XCTAssertNotNil(store);
  NSString *commitRev = [store latestMutationRevisionWithError:nil];
  XCTAssertNotNil(commitRev);
  XCTAssertTrue(commitRev.length > 0);
  XCTAssertEqualObjects(applyCommit[@"rev"], commitRev);

  NSString *query =
      [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, commitRev];
  HttpResponse *deltaResponse = [self
      sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                 queryString:query
                 queryParams:@{@"did" : self.userDid, @"since" : commitRev}
                     headers:@{}];
  XCTAssertEqual(deltaResponse.statusCode, 200);

  NSError *parseError = nil;
  CARReader *reader =
      [CARReader readFromData:deltaResponse.body error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.blocks.count, 0U);
  if (deltaResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath
                                               error:nil];
  }
}

- (void)testApplicationSyncGetRepoSinceApplyWritesDeleteRevReturnsEmptyDelta {
  NSString *authHeader = [NSString stringWithFormat:@"Bearer %@", self.userJwt];
  NSDictionary *createWrite = @{
    @"action" : @"create",
    @"collection" : @"app.bsky.feed.post",
    @"rkey" : @"applywrites-since-delete",
    @"value" : @{
      @"$type" : @"app.bsky.feed.post",
      @"text" : @"applyWrites delete rev baseline",
      @"createdAt" : [self iso8601String]
    }
  };
  HttpResponse *createResponse = [self
      sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                         body:@{@"writes" : @[ createWrite ], @"validate" : @NO}
                      headers:@{@"authorization" : authHeader}];
  XCTAssertEqual(createResponse.statusCode, 200);
  NSDictionary *createCommit = createResponse.jsonBody[@"commit"];
  XCTAssertNotNil(createCommit);
  XCTAssertTrue([createCommit[@"cid"] length] > 0);
  XCTAssertTrue([createCommit[@"rev"] length] > 0);

  NSDictionary *deleteWrite = @{
    @"action" : @"delete",
    @"collection" : @"app.bsky.feed.post",
    @"rkey" : @"applywrites-since-delete"
  };
  HttpResponse *deleteResponse = [self
      sendJsonRequestWithPath:@"/xrpc/com.atproto.repo.applyWrites"
                         body:@{@"writes" : @[ deleteWrite ], @"validate" : @NO}
                      headers:@{@"authorization" : authHeader}];
  XCTAssertEqual(deleteResponse.statusCode, 200);
  NSDictionary *deleteCommit = deleteResponse.jsonBody[@"commit"];
  XCTAssertNotNil(deleteCommit);
  XCTAssertTrue([deleteCommit[@"cid"] length] > 0);
  XCTAssertTrue([deleteCommit[@"rev"] length] > 0);

  PDSActorStore *store =
      [self.application.userDatabasePool storeForDid:self.userDid error:nil];
  XCTAssertNotNil(store);
  NSString *deleteRev = [store latestMutationRevisionWithError:nil];
  XCTAssertNotNil(deleteRev);
  XCTAssertTrue(deleteRev.length > 0);
  XCTAssertEqualObjects(deleteCommit[@"rev"], deleteRev);

  NSString *query =
      [NSString stringWithFormat:@"did=%@&since=%@", self.userDid, deleteRev];
  HttpResponse *deltaResponse = [self
      sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepo"
                 queryString:query
                 queryParams:@{@"did" : self.userDid, @"since" : deleteRev}
                     headers:@{}];
  XCTAssertEqual(deltaResponse.statusCode, 200);

  NSError *parseError = nil;
  CARReader *reader =
      [CARReader readFromData:deltaResponse.body error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.blocks.count, 0U);
  if (deltaResponse.bodyFilePath.length > 0) {
    [[NSFileManager defaultManager] removeItemAtPath:deltaResponse.bodyFilePath
                                               error:nil];
  }
}

- (void)testApplicationSyncGetRepoSocketStreamingUsesChunkedTransferEncoding {
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"socket streaming getRepo",
    @"createdAt" : [self iso8601String]
  };
  NSDictionary *created = [self.application.legacyController
      createRecordForDid:self.userDid
              collection:@"app.bsky.feed.post"
                  record:record
          validationMode:PDSValidationModeOff
                   error:nil];
  XCTAssertNotNil(created);

  NSError *startError = nil;
  HttpServer *server =
      [PDSHttpTestUtilities startSocketServerWithDispatcher:self.dispatcher
                                                      error:&startError];
  if (!server) {
    XCTSkip(@"Socket listener unavailable in this environment: %@",
            startError.localizedDescription ?: @"unknown error");
    return;
  }

  NSString *encodedDid =
      [self.userDid stringByAddingPercentEncodingWithAllowedCharacters:
                        [NSCharacterSet URLQueryAllowedCharacterSet]];
  NSString *path =
      [NSString stringWithFormat:@"/xrpc/com.atproto.sync.getRepo?did=%@",
                                 encodedDid ?: self.userDid];

  NSError *requestError = nil;
  NSData *rawResponse =
      [PDSHttpTestUtilities rawHTTPResponseForPath:path
                                              port:(uint16_t)server.port
                                             error:&requestError];
  [server stop];
  XCTAssertNil(requestError);
  XCTAssertNotNil(rawResponse);
  if (!rawResponse) {
    return;
  }

  NSError *parseError = nil;
  NSDictionary *parsed =
      [PDSHttpTestUtilities parseRawHTTPResponse:rawResponse error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(parsed);
  if (!parsed) {
    return;
  }

  XCTAssertEqual([parsed[@"statusCode"] integerValue], (NSInteger)200);
  NSDictionary<NSString *, NSString *> *headers = parsed[@"headers"];
  XCTAssertEqualObjects([headers[@"content-type"] lowercaseString],
                        @"application/vnd.ipld.car");
  XCTAssertEqualObjects([headers[@"transfer-encoding"] lowercaseString],
                        @"chunked");
  XCTAssertNil(headers[@"content-length"]);

  NSDictionary *chunked =
      [PDSHttpTestUtilities decodeChunkedBody:parsed[@"body"]
                                        error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(chunked);
  if (!chunked) {
    return;
  }

  NSArray<NSNumber *> *chunkSizes = chunked[@"chunkSizes"];
  XCTAssertTrue(chunkSizes.count > 1, @"Expected multiple streamed chunks");
  NSData *carData = chunked[@"payload"];
  XCTAssertTrue(carData.length > 0);

  NSError *carError = nil;
  CARReader *reader = [CARReader readFromData:carData error:&carError];
  XCTAssertNil(carError);
  XCTAssertNotNil(reader);
  XCTAssertNotNil(reader.rootCID);
  XCTAssertTrue(reader.blocks.count > 0);
}

- (void)testApplicationSyncGetBlobSocketRangeUsesChunkedPartialContent {
  NSData *blobData =
      [@"socket-range-blob" dataUsingEncoding:NSUTF8StringEncoding];
  NSError *uploadError = nil;
  NSDictionary *uploadResult =
      [self.application.legacyController uploadBlob:blobData
                                             forDid:self.userDid
                                           mimeType:@"text/plain"
                                              error:&uploadError];
  XCTAssertNil(uploadError);
  XCTAssertNotNil(uploadResult);
  NSString *cid = uploadResult[@"blob"][@"ref"][@"$link"];
  XCTAssertTrue(cid.length > 0);
  if (cid.length == 0) {
    return;
  }

  NSError *startError = nil;
  HttpServer *server =
      [PDSHttpTestUtilities startSocketServerWithDispatcher:self.dispatcher
                                                      error:&startError];
  if (!server) {
    XCTSkip(@"Socket listener unavailable in this environment: %@",
            startError.localizedDescription ?: @"unknown error");
    return;
  }

  NSString *encodedDid =
      [self.userDid stringByAddingPercentEncodingWithAllowedCharacters:
                        [NSCharacterSet URLQueryAllowedCharacterSet]];
  NSString *encodedCID =
      [cid stringByAddingPercentEncodingWithAllowedCharacters:
               [NSCharacterSet URLQueryAllowedCharacterSet]];
  NSString *path = [NSString
      stringWithFormat:@"/xrpc/com.atproto.sync.getBlob?did=%@&cid=%@",
                       encodedDid ?: self.userDid, encodedCID ?: cid];

  NSError *requestError = nil;
  NSData *rawResponse =
      [PDSHttpTestUtilities rawHTTPResponseForPath:path
                                              port:(uint16_t)server.port
                                 additionalHeaders:@{@"Range" : @"bytes=1-5"}
                                             error:&requestError];
  [server stop];
  XCTAssertNil(requestError);
  XCTAssertNotNil(rawResponse);
  if (!rawResponse) {
    return;
  }

  NSError *parseError = nil;
  NSDictionary *parsed =
      [PDSHttpTestUtilities parseRawHTTPResponse:rawResponse error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(parsed);
  if (!parsed) {
    return;
  }

  XCTAssertEqual([parsed[@"statusCode"] integerValue], (NSInteger)206);
  NSDictionary<NSString *, NSString *> *headers = parsed[@"headers"];
  XCTAssertEqualObjects([headers[@"accept-ranges"] lowercaseString], @"bytes");
  XCTAssertEqualObjects([headers[@"transfer-encoding"] lowercaseString],
                        @"chunked");
  NSString *expectedContentRange = [NSString
      stringWithFormat:@"bytes 1-5/%lu", (unsigned long)blobData.length];
  XCTAssertEqualObjects([headers[@"content-range"] lowercaseString],
                        [expectedContentRange lowercaseString]);

  NSDictionary *chunked =
      [PDSHttpTestUtilities decodeChunkedBody:parsed[@"body"]
                                        error:&parseError];
  XCTAssertNil(parseError);
  XCTAssertNotNil(chunked);
  if (!chunked) {
    return;
  }

  NSData *payload = chunked[@"payload"];
  NSData *expected = [blobData subdataWithRange:NSMakeRange(1, 5)];
  XCTAssertEqualObjects(payload, expected);
}

- (void)testApplicationSyncGetRepoStatusReturnsActiveAndRev {
  NSString *query = [NSString stringWithFormat:@"did=%@", self.userDid];
  HttpResponse *response =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepoStatus"
                       queryString:query
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(response.statusCode, 200);
  NSDictionary *body = response.jsonBody;
  XCTAssertNotNil(body);
  XCTAssertEqualObjects(body[@"did"], self.userDid);
  XCTAssertEqualObjects(body[@"active"], @YES);
  // Since 'userDid' implies an active account in the test setup, we might or
  // might not have a rev depending if records were created. Let's just create
  // one to be sure.
  NSDictionary *record = @{
    @"$type" : @"app.bsky.feed.post",
    @"text" : @"post for rev",
    @"createdAt" : [self iso8601String]
  };
  [self.application.legacyController createRecordForDid:self.userDid
                                             collection:@"app.bsky.feed.post"
                                                 record:record
                                         validationMode:PDSValidationModeOff
                                                  error:nil];

  HttpResponse *responseWithRev =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepoStatus"
                       queryString:query
                       queryParams:@{@"did" : self.userDid}
                           headers:@{}];
  XCTAssertEqual(responseWithRev.statusCode, 200);
  XCTAssertNotNil(responseWithRev.jsonBody[@"rev"]);
  XCTAssertTrue(
      [responseWithRev.jsonBody[@"rev"] isKindOfClass:[NSString class]]);
}

- (void)testApplicationSyncGetRepoStatusReturnsNotFoundForInvalidDid {
  NSString *query = @"did=did:plc:invalid";
  HttpResponse *response =
      [self sendGetRequestWithPath:@"/xrpc/com.atproto.sync.getRepoStatus"
                       queryString:query
                       queryParams:@{@"did" : @"did:plc:invalid"}
                           headers:@{}];
  XCTAssertEqual(response.statusCode, 404);
  XCTAssertEqualObjects(response.jsonBody[@"error"], @"RepoNotFound");
}

@end
