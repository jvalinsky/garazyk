# Bugfix Requirements Document

## Introduction

The CAR (Content Addressable aRchive) export functionality in PDSRepositoryService is failing because blocks stored successfully in the actor store cannot be retrieved during export operations. This causes 97 test failures in PDSRepositoryServiceTests, with errors like "Data too short for CAR header" and "Signing key not found". The root issue is that `putBlock` operations succeed but subsequent `getBlockForCID` calls fail to find the same blocks, indicating a storage/retrieval mismatch.

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN blocks are stored via `putBlock` and then retrieved via `getBlockForCID` within the same export operation THEN the system fails to find the blocks despite successful storage

1.2 WHEN CAR export attempts to retrieve blocks for records THEN the system returns "not found" errors even though logs show successful `putBlock` operations

1.3 WHEN CAR export materializes blocks from records and stores them THEN subsequent retrieval during the same export fails with "Data too short for CAR header"

1.4 WHEN multiple blocks are stored in a transaction during export preparation THEN the blocks are not visible to subsequent read operations in the export flow

### Expected Behavior (Correct)

2.1 WHEN blocks are stored via `putBlock` THEN subsequent `getBlockForCID` calls SHALL successfully retrieve those blocks within the same operation

2.2 WHEN CAR export attempts to retrieve blocks for records THEN the system SHALL return the block data that was previously stored

2.3 WHEN CAR export materializes blocks from records and stores them THEN subsequent retrieval SHALL succeed and return valid block data

2.4 WHEN multiple blocks are stored in a transaction during export preparation THEN the blocks SHALL be immediately visible to subsequent read operations within the same export flow

### Unchanged Behavior (Regression Prevention)

3.1 WHEN blocks are stored and retrieved in separate, independent operations THEN the system SHALL CONTINUE TO function correctly

3.2 WHEN CAR export is performed for repositories with pre-existing blocks THEN the system SHALL CONTINUE TO export those blocks successfully

3.3 WHEN block storage operations complete successfully THEN the system SHALL CONTINUE TO persist blocks to the database

3.4 WHEN CID encoding and serialization is performed THEN the system SHALL CONTINUE TO use consistent binary representation for storage and retrieval
