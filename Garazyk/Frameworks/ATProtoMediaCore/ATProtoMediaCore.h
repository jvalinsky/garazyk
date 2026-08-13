/*!
 @header ATProtoMediaCore.h

 @abstract Experimental v0 umbrella for media processing and MUXL primitives.
 */

#import <Foundation/Foundation.h>

#import "MediaCore/ATProtoMediaProcessor.h"
#import "MediaCore/ATProtoMediaServiceConfiguration.h"
#import "MediaCore/ATProtoMediaServiceRuntime.h"
#import "MediaCore/ATProtoMUXLBox.h"
#import "MediaCore/ATProtoMUXLFragment.h"
#import "MediaCore/ATProtoCAObjectStore.h"
#import "MediaCore/ATProtoVODManifestBuilder.h"
#import "MediaCore/ATProtoCAMediaDenylist.h"
#import "MediaCore/ATProtoCAWatchService.h"
#import "MediaCore/ATProtoCAObjectLifecycle.h"
#import "MediaCore/ATProtoCAMirrorResolver.h"
#import "MediaCore/ATProtoCAMirrorHTTPSFetcher.h"
#import "MediaCore/ATProtoCARASLWellKnown.h"
#import "MediaCore/ATProtoVideoPrefetchBootstrap.h"

FOUNDATION_EXPORT double ATProtoMediaCoreVersionNumber;
FOUNDATION_EXPORT const unsigned char ATProtoMediaCoreVersionString[];
