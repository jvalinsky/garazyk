#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HttpRequest;
@class HttpResponse;

/*!
 @class HttpBufferPool

 @abstract Slab allocator for HTTP request/response objects and buffers.

 @discussion HttpBufferPool reduces allocation overhead by reusing HttpRequest,
 HttpResponse, and data buffers. Uses size classes (256, 1024, 4096, 16384 bytes)
 with separate pools for each size to minimize internal fragmentation.

 Thread Safety: All methods are thread-safe using serial dispatch queues.
 */
@interface HttpBufferPool : NSObject

/*!
 @method sharedPool

 @abstract Returns the shared buffer pool instance.

 @return The singleton pool.
 */
+ (instancetype)sharedPool;

/*!
 @method initWithSizeClasses:

 @abstract Initialize a pool with specific size classes.

 @param sizeClasses Array of buffer sizes in bytes.

 @return An initialized pool.
 */
- (instancetype)initWithSizeClasses:(NSArray<NSNumber *> *)sizeClasses;

/*!
 @method acquireBufferOfSize:

 @abstract Returns a buffer of at least the requested size.

 @param size The minimum buffer size in bytes.

 @return A mutable data buffer, or nil if size exceeds max.
 */
- (NSMutableData *)acquireBufferOfSize:(NSUInteger)size;

/*!
 @method releaseBuffer:

 @abstract Returns a buffer to the pool for reuse.

 @param buffer The buffer to release.
 */
- (void)releaseBuffer:(NSMutableData *)buffer;

/*!
 @method acquireRequest

 @abstract Returns a recycled HttpRequest object.

 @return An HttpRequest instance, or nil if pool is exhausted.
 */
- (nullable HttpRequest *)acquireRequest;

/*!
 @method releaseRequest:

 @abstract Returns an HttpRequest to the pool for reuse.

 @param request The request to recycle.
 */
- (void)releaseRequest:(HttpRequest *)request;

/*!
 @method acquireResponse

 @abstract Returns a recycled HttpResponse object.

 @return An HttpResponse instance, or nil if pool is exhausted.
 */
- (nullable HttpResponse *)acquireResponse;

/*!
 @method releaseResponse:

 @abstract Returns an HttpResponse to the pool for reuse.

 @param response The response to recycle.
 */
- (void)releaseResponse:(HttpResponse *)response;

/*!
 @property maxPoolSize

 @abstract Maximum number of objects to keep in each pool (default: 64).

 @discussion When exceeded, objects are deallocated instead of recycled.
 */
@property (nonatomic, assign) NSUInteger maxPoolSize;

/*!
 @property bufferCount

 @abstract Current total count of buffered objects (for monitoring).
 */
@property (nonatomic, readonly) NSUInteger bufferCount;

/*!
 @property requestCount

 @abstract Current count of pooled request objects.
 */
@property (nonatomic, readonly) NSUInteger requestCount;

/*!
 @property responseCount

 @abstract Current count of pooled response objects.
 */
@property (nonatomic, readonly) NSUInteger responseCount;

/*!
 @method drainPools

 @abstract Releases all pooled objects to free memory.

 @discussion Call this during low-traffic periods or when scaling down.
 */
- (void)drainPools;

@end

NS_ASSUME_NONNULL_END
