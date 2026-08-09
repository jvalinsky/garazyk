# Explicit source manifest for ATProtoVideoService.
# Entries are repository-relative; CMake validates existence, ownership, and
# build-host independence before resolving them into target source lists.
set(ATPROTO_VIDEO_MANIFEST
  "Garazyk/Sources/Video/ATProtoVideoProcessor.m"
  "Garazyk/Sources/Video/AVFoundationTranscoder.m"
  "Garazyk/Sources/Video/FFmpegTranscoder.m"
  "Garazyk/Sources/Video/JelczConfiguration.m"
  "Garazyk/Sources/Video/JelczDatabase.m"
  "Garazyk/Sources/Video/PDSLocalVideoJobStore.m"
  "Garazyk/Sources/Video/VideoHLSGenerator.m"
  "Garazyk/Sources/Video/VideoJWTAuthProvider.m"
  "Garazyk/Sources/Video/VideoLocalBlobUploader.m"
  "Garazyk/Sources/Video/VideoRemoteBlobUploader.m"
  "Garazyk/Sources/Video/VideoThumbnailGenerator.m"
  "Garazyk/Sources/Video/VideoTranscoder.m"
  "Garazyk/Sources/Video/VideoWorker.m"
)
