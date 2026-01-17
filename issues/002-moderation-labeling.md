# Issue: Admin/moderation/labeling endpoints return not implemented

## Summary
`ATProtoPDS/Sources/App/PDSController.m` exposes `takeDownAccount`, `reinstateAccount`, `moderateAccount`, `moderateRecord`, `createLabel`, and `getLabels` but each implementation immediately returns `ATProtoErrorCodeNotImplemented` and `{@"status": @"not_implemented"}` without doing any work.

## Impact
- Clients cannot actually invoke these moderation workflows despite the endpoints existing in the schema.
- Test coverage will continue to be limited to the error responses, masking real moderation scenarios.

## Proposed fix
- Implement the real admin/moderation/labeling logic or delegate to existing services that can handle account state changes, moderation decisions, and label management.
- If work isn’t ready, gate the endpoints or remove them until implementation is available to avoid false promises.
