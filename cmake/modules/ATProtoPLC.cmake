# Explicit source manifest for ATProtoPLC.
# Entries are repository-relative; CMake validates existence, ownership, and
# build-host independence before resolving them into target source lists.
set(ATPROTO_PLC_MANIFEST
  "Garazyk/Sources/PLC/DIDPLCResolver.m"
  "Garazyk/Sources/PLC/PDSPLCAccountOperationProvider.m"
  "Garazyk/Sources/PLC/PLCAuditor.m"
  "Garazyk/Sources/PLC/PLCCacheDirectory.m"
  "Garazyk/Sources/PLC/PLCConstants.m"
  "Garazyk/Sources/PLC/PLCDIDKey.m"
  "Garazyk/Sources/PLC/PLCMetrics.m"
  "Garazyk/Sources/PLC/PLCMockStore.m"
  "Garazyk/Sources/PLC/PLCOperation.m"
  "Garazyk/Sources/PLC/PLCPersistentStore.m"
  "Garazyk/Sources/PLC/PLCReplicaServer.m"
  "Garazyk/Sources/PLC/PLCReplicaStore.m"
  "Garazyk/Sources/PLC/PLCRotationKeyManager.m"
  "Garazyk/Sources/PLC/PLCServer.m"
  "Garazyk/Sources/PLC/PLCSyncClient.m"
  "Garazyk/Sources/PLC/PLCSyncEngine.m"
)
