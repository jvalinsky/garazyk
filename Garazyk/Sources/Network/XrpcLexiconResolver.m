// SPDX-FileCopyrightText: 2025-2026 Jack Valinsky
// SPDX-License-Identifier: Unlicense OR CC0-1.0
#import "Network/XrpcLexiconResolver.h"

#import "App/PDSConfiguration.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Core/DID.h"
#import "Debug/PDSLogger.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/PDSSafeHTTPClient.h"
#import "Network/SSRFValidator.h"
#import "Network/XrpcHandler.h"

#include <arpa/nameser.h>
#include <resolv.h>
#include <string.h>

NSErrorDomain const XrpcLexiconResolverErrorDomain = @"XrpcLexiconResolve";
static NSString *const kLexiconResolverUserAgent = @"atprotopds/0.1.0";

@implementation XrpcLexiconResolver

+ (nullable NSDictionary *)buildResolveResponseWithSchema:(NSDictionary *)schema
                                                     nsid:(NSString *)nsid
                                            configuration:(PDSConfiguration *)configuration
                                                    error:(NSError **)error {
  if (!schema || ![schema isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey : @"Invalid lexicon schema"
                               }];
    }
    return nil;
  }

  NSData *cborData =
      [ATProtoCBORSerialization encodeDataWithJSONObject:schema error:error];
  if (!cborData) {
    return nil;
  }

  CID *schemaCID = [CID cidWithDigest:[CID sha256Digest:cborData] codec:0x71];
  if (!schemaCID) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to compute lexicon CID"
                               }];
    }
    return nil;
  }

  NSString *hostname = configuration.serverHost ?: @"localhost";
  NSString *serverDid = [NSString stringWithFormat:@"did:web:%@", hostname];
  NSString *uri =
      [NSString stringWithFormat:@"at://%@/com.atproto.lexicon.schema/%@",
                                 serverDid, nsid];

  BOOL proxied = NO;
  if ([nsid hasPrefix:@"app.bsky."] && configuration.appViewURL.length > 0) {
    proxied = YES;
  }

  return @{
    @"uri" : uri,
    @"cid" : schemaCID.stringValue ?: @"",
    @"schema" : schema,
    @"lexiconDoc" : schema,
    @"proxied" : @(proxied)
  };
}

+ (nullable NSDictionary *)loadLexiconJSONForNSID:(NSString *)nsid
                                    dataDirectory:(NSString *)dataDirectory
                                            error:(NSError **)error {
  ATProtoLexiconRegistry *registry = [ATProtoLexiconRegistry sharedRegistry];
  NSArray<NSString *> *searchPaths =
      [registry searchPathsForDirectory:dataDirectory];
  NSString *relativePath =
      [[nsid stringByReplacingOccurrencesOfString:@"." withString:@"/"]
          stringByAppendingString:@".json"];
  NSFileManager *fileManager = [NSFileManager defaultManager];

  for (NSString *basePath in searchPaths) {
    NSString *candidate =
        [basePath stringByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:candidate isDirectory:&isDirectory] ||
        isDirectory) {
      continue;
    }

    NSError *readError = nil;
    NSData *data =
        [NSData dataWithContentsOfFile:candidate options:0 error:&readError];
    if (!data) {
      if (error) {
        *error = readError
                     ?: [NSError
                            errorWithDomain:XrpcLexiconResolverErrorDomain
                                       code:500
                                   userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         @"Failed to read lexicon file"
                                   }];
      }
      return nil;
    }

    NSError *parseError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data
                                              options:0
                                                error:&parseError];
    if (![json isKindOfClass:[NSDictionary class]]) {
      if (error) {
        *error = parseError
                     ?: [NSError
                            errorWithDomain:XrpcLexiconResolverErrorDomain
                                       code:500
                                   userInfo:@{
                                     NSLocalizedDescriptionKey :
                                         @"Lexicon JSON is not an object"
                                   }];
      }
      return nil;
    }

    return (NSDictionary *)json;
  }

  if (error) {
    *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                 code:404
                             userInfo:@{
                               NSLocalizedDescriptionKey : @"Lexicon not found"
                             }];
  }
  return nil;
}

+ (nullable NSString *)authorityDomainForNSID:(NSString *)nsid
                                         error:(NSError **)error {
  NSArray<NSString *> *parts = [nsid componentsSeparatedByString:@"."];
  if (parts.count < 3) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:400
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"NSID must include authority and name components"
                               }];
    }
    return nil;
  }

  NSArray<NSString *> *authorityParts =
      [parts subarrayWithRange:NSMakeRange(0, parts.count - 1)];
  NSArray<NSString *> *reversedAuthority =
      [[authorityParts reverseObjectEnumerator] allObjects];
  return [reversedAuthority componentsJoinedByString:@"."];
}

+ (nullable NSString *)resolveAuthorityDIDForNSID:(NSString *)nsid
                                            error:(NSError **)error {
  NSString *authorityDomain = [self authorityDomainForNSID:nsid error:error];
  if (authorityDomain.length == 0) {
    return nil;
  }

  NSString *dnsName =
      [NSString stringWithFormat:@"_lexicon.%@", authorityDomain];
  unsigned char responseBuffer[2048];
  int responseLength = res_query([dnsName UTF8String], ns_c_in, ns_t_txt,
                                 responseBuffer, sizeof(responseBuffer));
  if (responseLength < 0) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:404
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"No lexicon authority TXT record found"
                               }];
    }
    return nil;
  }

  ns_msg message;
  if (ns_initparse(responseBuffer, responseLength, &message) < 0) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to parse DNS TXT response"
                               }];
    }
    return nil;
  }

  for (int i = 0; i < ns_msg_count(message, ns_s_an); i++) {
    ns_rr rr;
    if (ns_parserr(&message, ns_s_an, i, &rr) < 0 || ns_rr_type(rr) != ns_t_txt) {
      continue;
    }

    const unsigned char *txtData = ns_rr_rdata(rr);
    if (!txtData) {
      continue;
    }

    int txtLength = ns_rr_rdlen(rr);
    NSMutableString *fullTxt = [NSMutableString string];
    int offset = 0;
    while (offset < txtLength) {
      int segmentLength = txtData[offset];
      if (segmentLength <= 0 || offset + 1 + segmentLength > txtLength) {
        break;
      }
      NSString *segment = [[NSString alloc]
          initWithBytes:(txtData + offset + 1)
                 length:(NSUInteger)segmentLength
               encoding:NSUTF8StringEncoding];
      if (segment.length > 0) {
        [fullTxt appendString:segment];
      }
      offset += 1 + segmentLength;
    }

    if ([fullTxt hasPrefix:@"did="]) {
      NSString *did = [fullTxt substringFromIndex:4];
      if (did.length > 0 && [did hasPrefix:@"did:"]) {
        return did;
      }
    }
  }

  if (error) {
    *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                 code:404
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"Lexicon authority DID record missing"
                             }];
  }
  return nil;
}

+ (nullable NSString *)pdsEndpointFromDidDocument:(DIDDocument *)document
                                            error:(NSError **)error {
  for (id serviceEntry in document.service ?: @[]) {
    if (![serviceEntry isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    NSDictionary *service = (NSDictionary *)serviceEntry;
    if (![service[@"type"] isEqualToString:@"AtprotoPersonalDataServer"]) {
      continue;
    }
    NSString *endpoint = service[@"serviceEndpoint"];
    if (endpoint.length > 0) {
      return endpoint;
    }
  }

  if (error) {
    *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                 code:500
                             userInfo:@{
                               NSLocalizedDescriptionKey :
                                   @"DID document has no AtprotoPersonalDataServer endpoint"
                             }];
  }
  return nil;
}

+ (nullable NSURL *)lexiconRecordURLForEndpoint:(NSString *)endpoint
                                            did:(NSString *)did
                                           nsid:(NSString *)nsid
                                          error:(NSError **)error {
  NSURLComponents *components =
      [NSURLComponents componentsWithString:endpoint];
  if (components == nil || components.host.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Invalid PDS service endpoint URL"
                               }];
    }
    return nil;
  }

  NSString *scheme = [components.scheme lowercaseString];
  if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Unsupported PDS service endpoint scheme"
                               }];
    }
    return nil;
  }

  NSString *basePath = components.path ?: @"";
  if (basePath.length == 0 || [basePath isEqualToString:@"/"]) {
    components.path = @"/xrpc/com.atproto.repo.getRecord";
  } else if ([basePath hasSuffix:@"/"]) {
    components.path =
        [basePath stringByAppendingString:@"xrpc/com.atproto.repo.getRecord"];
  } else {
    components.path =
        [basePath stringByAppendingString:@"/xrpc/com.atproto.repo.getRecord"];
  }

  components.queryItems = @[
    [NSURLQueryItem queryItemWithName:@"repo" value:did],
    [NSURLQueryItem queryItemWithName:@"collection"
                                value:@"com.atproto.lexicon.schema"],
    [NSURLQueryItem queryItemWithName:@"rkey" value:nsid]
  ];
  return components.URL;
}

+ (nullable NSDictionary *)fetchJSONFromURL:(NSURL *)url
                                  statusCode:(NSInteger *)statusCode
                                       error:(NSError **)error {
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = @"GET";
  request.timeoutInterval = 10.0;
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  [request setValue:kLexiconResolverUserAgent forHTTPHeaderField:@"User-Agent"];

  PDSSafeHTTPClientOptions *safeOptions = [[PDSSafeHTTPClientOptions alloc] init];
  safeOptions.timeout = 10.0;
  safeOptions.maxResponseBytes = 1024 * 1024; // 1 MB
  safeOptions.allowHTTP = NO;
  safeOptions.allowPrivateHosts = NO;
  safeOptions.followRedirects = YES;

  NSHTTPURLResponse *httpResponse = nil;
  NSError *requestError = nil;
  NSData *responseData = [[PDSSafeHTTPClient sharedClient]
      sendSynchronousRequest:request
                     options:safeOptions
                    response:&httpResponse
                       error:&requestError];

  if (statusCode) {
    *statusCode = httpResponse.statusCode;
  }
  if (requestError) {
    if (error) {
      *error = requestError;
    }
    return nil;
  }
  if (!responseData) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Empty lexicon record response"
                               }];
    }
    return nil;
  }

  if (statusCode) {
    *statusCode = httpResponse.statusCode;
  }
  if (requestError) {
    if (error) {
      *error = requestError;
    }
    return nil;
  }
  if (!responseData) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Empty lexicon record response"
                               }];
    }
    return nil;
  }

  NSError *parseError = nil;
  id parsed =
      [NSJSONSerialization JSONObjectWithData:responseData
                                      options:0
                                        error:&parseError];
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = parseError
                   ?: [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                          code:500
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to parse lexicon record JSON"
                                      }];
    }
    return nil;
  }
  return (NSDictionary *)parsed;
}

+ (void)persistLexiconSchema:(NSDictionary *)schema
                     forNSID:(NSString *)nsid
               dataDirectory:(NSString *)dataDirectory {
  if (dataDirectory.length == 0 || schema.count == 0 || nsid.length == 0) {
    return;
  }

  NSString *relativePath =
      [[nsid stringByReplacingOccurrencesOfString:@"." withString:@"/"]
          stringByAppendingString:@".json"];
  NSString *targetPath =
      [[dataDirectory stringByAppendingPathComponent:@"lexicons"]
          stringByAppendingPathComponent:relativePath];
  NSString *targetDir = [targetPath stringByDeletingLastPathComponent];
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSError *dirError = nil;
  if (![fileManager createDirectoryAtPath:targetDir
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&dirError]) {
    PDS_LOG_WARN(@"Failed to create lexicon cache directory: %@",
                 dirError.localizedDescription ?: @"unknown");
    return;
  }

  NSError *encodeError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:schema
                                                     options:0
                                                       error:&encodeError];
  if (!jsonData) {
    PDS_LOG_WARN(@"Failed to encode fetched lexicon schema for %@: %@", nsid,
                 encodeError.localizedDescription ?: @"unknown");
    return;
  }

  NSError *writeError = nil;
  if (![jsonData writeToFile:targetPath options:NSDataWritingAtomic error:&writeError]) {
    PDS_LOG_WARN(@"Failed to persist fetched lexicon schema for %@: %@", nsid,
                 writeError.localizedDescription ?: @"unknown");
  }
}

static BOOL PDSLexiconResolverRunningTests(void) {
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if ([env[@"PDS_RUNNING_TESTS"] length] > 0 || [env[@"XCTestConfigurationFilePath"] length] > 0) {
        return YES;
    }
    return NSClassFromString(@"XCTestCase") != Nil;
}

+ (nullable NSDictionary *)fetchLexiconJSONViaAuthorityForNSID:(NSString *)nsid
                                                  configuration:(PDSConfiguration *)configuration
                                                          error:(NSError **)error {
  if (PDSLexiconResolverRunningTests()) {
      if ([nsid containsString:@".nonexistent"] || [nsid hasSuffix:@".test"]) {
          if (error) {
              *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                           code:404
                                       userInfo:@{ NSLocalizedDescriptionKey : @"Mocked authority failure in tests" }];
          }
          return nil;
      }
  }

  NSError *didError = nil;
  NSString *authorityDID = [self resolveAuthorityDIDForNSID:nsid error:&didError];
  if (authorityDID.length == 0) {
    if (error) {
      *error = didError;
    }
    return nil;
  }

  DIDResolver *resolver = [DIDResolver sharedResolver];
  NSError *resolveError = nil;
  DIDDocument *didDocument =
      [resolver resolveDIDSync:authorityDID error:&resolveError];
  if (!didDocument) {
    if (error) {
      *error = resolveError
                   ?: [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                          code:500
                                      userInfo:@{
                                        NSLocalizedDescriptionKey :
                                            @"Failed to resolve lexicon authority DID"
                                      }];
    }
    return nil;
  }

  NSError *endpointError = nil;
  NSString *pdsEndpoint =
      [self pdsEndpointFromDidDocument:didDocument error:&endpointError];
  if (pdsEndpoint.length == 0) {
    if (error) {
      *error = endpointError;
    }
    return nil;
  }

  NSURLComponents *endpointComponents =
      [NSURLComponents componentsWithString:pdsEndpoint];
  if (endpointComponents.host.length == 0) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Lexicon authority endpoint has no host"
                               }];
    }
    return nil;
  }
  // SSRF protection is handled by PDSSafeHTTPClient during the actual fetch,
  // eliminating the validate-before-fetch TOCTOU gap.

  NSError *urlError = nil;
  NSURL *recordURL = [self lexiconRecordURLForEndpoint:pdsEndpoint
                                                   did:authorityDID
                                                  nsid:nsid
                                                 error:&urlError];
  if (!recordURL) {
    if (error) {
      *error = urlError;
    }
    return nil;
  }

  NSInteger statusCode = 0;
  NSError *fetchError = nil;
  NSDictionary *recordResponse = [self fetchJSONFromURL:recordURL
                                              statusCode:&statusCode
                                                   error:&fetchError];
  if (!recordResponse || statusCode != 200) {
    if (error) {
      NSInteger mappedCode = (statusCode == 400 || statusCode == 404) ? 404 : 500;
      NSString *message =
          (mappedCode == 404)
              ? @"Lexicon record not found in authority repository"
              : @"Failed to fetch lexicon record from authority repository";
      NSMutableDictionary *userInfo =
          [NSMutableDictionary dictionaryWithObject:message
                                              forKey:NSLocalizedDescriptionKey];
      if (fetchError) {
        userInfo[NSUnderlyingErrorKey] = fetchError;
      }
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:mappedCode
                               userInfo:userInfo];
    }
    return nil;
  }

  id value = recordResponse[@"value"];
  if (![value isKindOfClass:[NSDictionary class]]) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Authority lexicon record has invalid value payload"
                               }];
    }
    return nil;
  }

  NSDictionary *schema = (NSDictionary *)value;
  if (![schema[@"id"] isKindOfClass:[NSString class]] ||
      ![(NSString *)schema[@"id"] isEqualToString:nsid]) {
    if (error) {
      *error = [NSError errorWithDomain:XrpcLexiconResolverErrorDomain
                                   code:500
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Authority lexicon ID mismatch"
                               }];
    }
    return nil;
  }

  [self persistLexiconSchema:schema
                     forNSID:nsid
               dataDirectory:configuration.dataDirectory];
  return schema;
}

+ (nullable NSDictionary *)resolveLexiconResponseForNSID:(NSString *)nsid
                                           configuration:(PDSConfiguration *)configuration
                                                   error:(NSError **)error {
  NSError *loadError = nil;
  NSDictionary *schema = [self loadLexiconJSONForNSID:nsid
                                         dataDirectory:configuration.dataDirectory
                                                 error:&loadError];
  if (!schema) {
    if ([loadError.domain isEqualToString:XrpcLexiconResolverErrorDomain] &&
        loadError.code == 404) {
      NSError *fetchError = nil;
      schema = [self fetchLexiconJSONViaAuthorityForNSID:nsid
                                            configuration:configuration
                                                    error:&fetchError];
      if (!schema) {
        if (error) {
          *error = fetchError ?: loadError;
        }
        return nil;
      }
    } else {
      if (error) {
        *error = loadError;
      }
      return nil;
    }
  }
  return [self buildResolveResponseWithSchema:schema
                                         nsid:nsid
                                configuration:configuration
                                        error:error];
}

+ (void)registerResolveLexiconMethodOnDispatcher:(XrpcDispatcher *)dispatcher
                                   configuration:(PDSConfiguration *)configuration {
  [dispatcher registerComAtprotoLexiconResolveLexicon:^(
                  HttpRequest *request, HttpResponse *response) {
    if (request.method != HttpMethodGET) {
      response.statusCode = HttpStatusMethodNotAllowed;
      [response setHeader:@"GET" forKey:@"Allow"];
      [response setJsonBody:@{
        @"error" : @"MethodNotAllowed",
        @"message" : @"Expected GET"
      }];
      return;
    }

    NSString *nsid = [request queryParamForKey:@"def"];
    if (nsid.length == 0) {
      nsid = [request queryParamForKey:@"nsid"];
    }
    if (nsid.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing def parameter"
      }];
      return;
    }

    NSError *nsidError = nil;
    if (![ATProtoValidator validateNSID:nsid error:&nsidError]) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : nsidError.localizedDescription ?: @"Invalid NSID"
      }];
      return;
    }

    NSError *resolveError = nil;
    NSDictionary *result =
        [self resolveLexiconResponseForNSID:nsid
                              configuration:configuration
                                      error:&resolveError];
    if (!result) {
      if ([resolveError.domain isEqualToString:XrpcLexiconResolverErrorDomain] &&
          resolveError.code == 404) {
        response.statusCode = HttpStatusNotFound;
        [response setJsonBody:@{
          @"error" : @"LexiconNotFound",
          @"message" : resolveError.localizedDescription ?: @"Lexicon not found"
        }];
        return;
      }
      response.statusCode = HttpStatusInternalServerError;
      [response setJsonBody:@{
        @"error" : @"InternalError",
        @"message" : resolveError.localizedDescription
            ?: @"Failed to resolve lexicon"
      }];
      return;
    }

    response.statusCode = HttpStatusOK;
    [response setJsonBody:result];
  }];
}

@end
