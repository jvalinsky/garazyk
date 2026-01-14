/*!
 @file ExploreHandler.h

 @abstract Explore API web interface with OpenAPI documentation.

 @discussion Provides a web-based exploration interface for the PDS, including
 OpenAPI/Swagger documentation, interactive endpoint testing, and rich blob
 rendering (images, videos, audio, profile cards).

 @copyright Copyright (c) 2025-2026 Jack Valinsky
 */

#import <Foundation/Foundation.h>

@class HttpRequest;
@class HttpResponse;
@class PDSController;

NS_ASSUME_NONNULL_BEGIN

/*!
 @class APIParameterDescriptor

 @abstract Describes an OpenAPI parameter.

 @discussion Models API parameter metadata for OpenAPI documentation generation.
 Supports query, path, and header parameters with type validation.
 */
@interface APIParameterDescriptor : NSObject

/*! Parameter name (e.g., "did", "limit"). */
@property (nonatomic, copy) NSString *name;

/*! Parameter location: "query", "path", or "header". */
@property (nonatomic, copy) NSString *in;

/*! Parameter type: "string", "integer", "boolean". */
@property (nonatomic, copy) NSString *type;

/*! Human-readable parameter description. */
@property (nonatomic, copy, nullable) NSString *paramDescription;

/*! Whether parameter is required. */
@property (nonatomic, assign) BOOL required;

/*! Whether parameter is deprecated. */
@property (nonatomic, assign) BOOL deprecated;

/*!
 @method openAPIDict

 @abstract Export parameter as OpenAPI dictionary.

 @return Dictionary conforming to OpenAPI 3.0 parameter schema.
 */
- (NSDictionary *)openAPIDict;

/*!
 @method initWithName:in:type:description:required:

 @abstract Create parameter descriptor.

 @param name Parameter name.
 @param inLocation Parameter location (query/path/header).
 @param type Parameter type (string/integer/boolean).
 @param description Human-readable description.
 @param required Whether parameter is required.
 @return Initialized parameter descriptor.
 */
+ (instancetype)initWithName:(NSString *)name in:(NSString *)inLocation type:(NSString *)type description:(NSString *)description required:(BOOL)required;

@end

/*!
 @class APIResponseDescriptor

 @abstract Describes an OpenAPI response.

 @discussion Models API response metadata for OpenAPI documentation,
 including status codes, descriptions, and schema references.
 */
@interface APIResponseDescriptor : NSObject

/*! HTTP status code ("200", "400", "404"). */
@property (nonatomic, copy) NSString *statusCode;

/*! Human-readable response description. */
@property (nonatomic, copy) NSString *responseDescription;

/*! Schema reference (e.g., "#/components/schemas/Account"). */
@property (nonatomic, copy, nullable) NSString *schemaRef;

/*! Array item schema reference for array responses. */
@property (nonatomic, copy, nullable) NSString *arrayItemRef;

/*!
 @method openAPIDict

 @abstract Export response as OpenAPI dictionary.

 @return Dictionary conforming to OpenAPI 3.0 response schema.
 */
- (NSDictionary *)openAPIDict;

/*!
 @method initWithStatusCode:description:

 @abstract Create response descriptor.

 @param statusCode HTTP status code.
 @param description Human-readable description.
 @return Initialized response descriptor.
 */
+ (instancetype)initWithStatusCode:(NSString *)statusCode description:(NSString *)description;

@end

/*!
 @class APIEndpointDescriptor

 @abstract Describes a complete API endpoint.

 @discussion Models full endpoint metadata for OpenAPI documentation,
 including path, method, parameters, and responses.
 */
@interface APIEndpointDescriptor : NSObject

/*! Endpoint path (e.g., "/accounts"). */
@property (nonatomic, copy) NSString *path;

/*! HTTP method ("get", "post"). */
@property (nonatomic, copy) NSString *method;

/*! Brief endpoint summary. */
@property (nonatomic, copy) NSString *summary;

/*! Internal endpoint name. */
@property (nonatomic, copy, nullable) NSString *endpointName;

/*! Detailed endpoint description. */
@property (nonatomic, copy, nullable) NSString *endpointDescription;

/*! OpenAPI operation ID. */
@property (nonatomic, copy, nullable) NSString *operationId;

/*! OpenAPI tags for grouping. */
@property (nonatomic, copy, nullable) NSArray<NSString *> *tags;

/*! Endpoint parameters. */
@property (nonatomic, strong) NSArray<APIParameterDescriptor *> *parameters;

/*! Endpoint responses. */
@property (nonatomic, strong) NSArray<APIResponseDescriptor *> *responses;

/*! Whether endpoint is deprecated. */
@property (nonatomic, assign) BOOL deprecated;

/*!
 @method openAPIDict

 @abstract Export endpoint as OpenAPI dictionary.

 @return Dictionary conforming to OpenAPI 3.0 path item schema.
 */
- (NSDictionary *)openAPIDict;

/*!
 @method descriptorWithPath:method:summary:endpointName:operationId:tags:parameters:responses:

 @abstract Create complete endpoint descriptor.

 @param path Endpoint path.
 @param method HTTP method.
 @param summary Brief summary.
 @param endpointName Internal name.
 @param operationId OpenAPI operation ID.
 @param tags Grouping tags.
 @param parameters Parameter descriptors.
 @param responses Response descriptors.
 @return Initialized endpoint descriptor.
 */
+ (instancetype)descriptorWithPath:(NSString *)path
                            method:(NSString *)method
                           summary:(NSString *)summary
                      endpointName:(nullable NSString *)endpointName
                      operationId:(nullable NSString *)operationId
                             tags:(nullable NSArray<NSString *> *)tags
                        parameters:(NSArray<APIParameterDescriptor *> *)parameters
                        responses:(NSArray<APIResponseDescriptor *> *)responses;

@end

/*!
 @class ExploreHandler

 @abstract Web-based PDS exploration interface.

 @discussion Handles requests to /explore paths, serving:
 - OpenAPI/Swagger documentation
 - Interactive endpoint testing
 - Account browsing with profile cards
 - Rich blob rendering (images, videos, audio)
 - DID document and PLC log inspection

 Responses are cached for 5-10 minutes to reduce database load.
 */
@interface ExploreHandler : NSObject

/*!
 @method sharedHandler

 @abstract Get singleton handler instance.

 @return Shared ExploreHandler instance.
 */
+ (instancetype)sharedHandler;

/*!
 @method setController:

 @abstract Set PDS controller for data access.

 @param controller PDS controller providing database access.
 */
- (void)setController:(PDSController *)controller;

/*!
 @method canHandleRequest:

 @abstract Check if handler can process request.

 @param request HTTP request to check.
 @return YES if path starts with "/explore", NO otherwise.
 */
- (BOOL)canHandleRequest:(HttpRequest *)request;

/*!
 @method handleRequest:response:

 @abstract Handle Explore API request.

 @discussion Routes to appropriate handler based on path:
 - /explore - Main interface
 - /explore/openapi.json - OpenAPI spec
 - /explore/accounts - Account list
 - /explore/did/{did} - DID document
 - /explore/blob/{cid} - Blob content with rich rendering

 @param request HTTP request.
 @param response HTTP response to populate.
 */
- (void)handleRequest:(HttpRequest *)request response:(HttpResponse *)response;

@end

NS_ASSUME_NONNULL_END
