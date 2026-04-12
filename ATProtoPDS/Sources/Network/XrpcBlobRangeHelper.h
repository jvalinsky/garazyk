#import <Foundation/Foundation.h>
#import "Network/HttpResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface XrpcBlobRangeHelper : NSObject

+ (BOOL)parseByteRangeHeader:(nullable NSString *)rangeHeader
                 totalLength:(unsigned long long)totalLength
                    hasRange:(nullable BOOL *)hasRange
                 satisfiable:(nullable BOOL *)satisfiable
                       start:(nullable unsigned long long *)start
                         end:(nullable unsigned long long *)end
               failureReason:(NSString *_Nullable *_Nullable)failureReason;

+ (nullable HttpResponseBodyChunkProducer)
    blobFileChunkProducerForPath:(NSString *)path
                     startOffset:(unsigned long long)startOffset
                       endOffset:(unsigned long long)endOffset
                           error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

