# Explicit source manifest for ATProtoMediaCore.
# Entries are repository-relative; CMake validates existence, ownership, and
# build-host independence before resolving them into target source lists.
set(ATPROTO_MEDIA_CORE_MANIFEST
  "Garazyk/Sources/MediaCore/ATProtoMUXLBox.m"
  "Garazyk/Sources/MediaCore/ATProtoMUXLFragment.m"
  "Garazyk/Sources/MediaCore/ATProtoCAObjectStore.m"
  "Garazyk/Sources/MediaCore/ATProtoVODManifestBuilder.m"
  "Garazyk/Sources/MediaCore/ATProtoCAMediaDenylist.m"
  "Garazyk/Sources/MediaCore/ATProtoCAWatchService.m"
  "Garazyk/Sources/MediaCore/ATProtoCAObjectLifecycle.m"
  "Garazyk/Sources/MediaCore/ATProtoVideoPrefetchBootstrap.m"
  "Garazyk/Sources/MediaCore/ATProtoCAMirrorResolver.m"
  "Garazyk/Sources/MediaCore/ATProtoCAMirrorHTTPSFetcher.m"
  "Garazyk/Sources/MediaCore/ATProtoCARASLWellKnown.m"
  "Garazyk/Sources/MediaCore/ATProtoMediaSQLiteStore.m"
  "Garazyk/Sources/MediaCore/ATProtoMediaServiceConfiguration.m"
  "Garazyk/Sources/MediaCore/ATProtoMediaWorker.m"
  "Garazyk/Sources/MediaCore/JelczCLI.m"
)
