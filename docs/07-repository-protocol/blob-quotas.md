---
title: Blob Quotas
---



## Overview

Blob quotas are essential for managing storage resources in a PDS deployment. They prevent individual users from consuming excessive storage and ensure fair resource allocation across all users.

## Quota Enforcement

The PDS enforces blob quotas at multiple levels:

1. **Per-blob size limits** - Individual blobs cannot exceed the maximum size
2. **Per-user total storage** - Each user has a total storage quota
3. **Rate limiting** - Upload frequency is controlled to prevent abuse

## Configuration

Blob quotas are configured in the PDS configuration file:

```json
{
  "blob": {
    "max_size": 5242880,
    "user_quota": 52428800
  }
}
```

## Monitoring

Administrators can monitor blob usage through the admin API endpoints to track storage consumption and identify users approaching their quotas.
