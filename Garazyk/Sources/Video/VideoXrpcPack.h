#import <Foundation/Foundation.h>

@class XrpcDispatcher;
@class PDSDatabase;
@protocol VideoJobStore;
@protocol VideoAuthProvider;
@protocol PDSBlobProvider;

NS_ASSUME_NONNULL_BEGIN

@interface ATProtoVideoXrpcPack : NSObject

+ (void)registerWithDispatcher:(XrpcDispatcher *)dispatcher
                       jobStore:(id<VideoJobStore>)jobStore
                   authProvider:(id<VideoAuthProvider>)authProvider
                  blobProvider:(id<PDSBlobProvider>)blobProvider;

/// Validates that the data appears to be a valid video container (MP4 ftyp or Matroska header).
+ (BOOL)validateVideoContentType:(NSData *)data declaredMimeType:(NSString *)mimeType;

@end

NS_ASSUME_NONNULL_END
