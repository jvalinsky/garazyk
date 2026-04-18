# Plan: Chat Group Administration

## Objective
Expose full administrative control over group chats on the PDS, allowing moderators to monitor group activity, manage membership, and control invitation links.

## Backend Enhancements
### GroupService.m
- Implement `- (nullable NSArray<NSDictionary *> *)listAllGroupsWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;`
- Implement `- (nullable NSArray<NSDictionary *> *)listAllInviteLinksWithLimit:(NSInteger)limit cursor:(nullable NSString *)cursor error:(NSError **)error;`

### XrpcChatBskyGroupPack.m
- Register `chat.bsky.group.listGroups` (Admin-only variant if needed, or upgrade existing if appropriate).

## Frontend Implementation
### Sidebar & Navigation
- Add "Groups" and "Invite Links" items under the "Chat" sidebar section in `index.html`.

### Partial Templates
- `chat_groups.html`: Table listing Group URI, Name, Creator, Member Count, and Status.
- `chat_group_detail.html`: Detailed view of a group showing all members, pending requests, and message audit.
- `chat_invite_links.html`: List of all active group invite links, their usage counts, and expiry.

### UI Controls
- **Lock/Unlock Group**: Global freeze on group activity.
- **Force Remove Member**: Remove any user from any group.
- **Revoke Invite Link**: Disable a group invite link immediately.

## Implementation Steps
1. Implement `listAllGroups` and `listAllInviteLinks` in `GroupService.m`.
2. Add routes to `PDSHttpAdminRoutePack.m`.
3. Add partial handlers to `AdminUIHandler.m`.
4. Create templates in `Garazyk/Sources/Admin/AdminUI/Templates/`.
5. Implement event delegation for actions in `admin-chat.js`.
