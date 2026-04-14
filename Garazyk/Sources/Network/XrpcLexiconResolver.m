#import "Network/XrpcLexiconResolver.h"

#import "App/PDSConfiguration.h"
#import "Core/ATProtoCBORSerialization.h"
#import "Core/ATProtoValidator.h"
#import "Core/CID.h"
#import "Lexicon/ATProtoLexiconRegistry.h"
#import "Network/HttpRequest.h"
#import "Network/HttpResponse.h"
#import "Network/XrpcHandler.h"

NSErrorDomain const XrpcLexiconResolverErrorDomain = @"XrpcLexiconResolve";

@implementation XrpcLexiconResolver

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

+ (nullable NSDictionary *)resolveLexiconResponseForNSID:(NSString *)nsid
                                           configuration:(PDSConfiguration *)configuration
                                                   error:(NSError **)error {
  NSDictionary *schema = [self loadLexiconJSONForNSID:nsid
                                         dataDirectory:configuration.dataDirectory
                                                 error:error];
  if (!schema) {
    return nil;
  }

  NSError *cborError = nil;
  NSData *cborData =
      [ATProtoCBORSerialization encodeDataWithJSONObject:schema
                                                   error:&cborError];
  if (!cborData) {
    if (error) {
      *error = cborError
                   ?: [NSError
                          errorWithDomain:XrpcLexiconResolverErrorDomain
                                     code:500
                                 userInfo:@{
                                   NSLocalizedDescriptionKey :
                                       @"Failed to encode lexicon schema"
                                 }];
    }
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

  return @{
    @"uri" : uri,
    @"cid" : schemaCID.stringValue ?: @"",
    @"schema" : schema
  };
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

    NSString *nsid = [request queryParamForKey:@"nsid"];
    if (nsid.length == 0) {
      response.statusCode = HttpStatusBadRequest;
      [response setJsonBody:@{
        @"error" : @"InvalidRequest",
        @"message" : @"Missing nsid parameter"
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

