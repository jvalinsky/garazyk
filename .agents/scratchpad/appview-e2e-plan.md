# AppView E2E Scenario Coverage Plan

## Goal
Write 7 new e2e scenario scripts covering untested AppView features.

## Implementation Order
1. Client.py infrastructure (~25 new methods)
2. Scenario 14: Drafts & Bookmarks Workflow
3. Scenario 15: Mutes, Relationships & Starter Packs
4. Scenario 16: Notification Management & Preferences
5. Scenario 17: Actor Preferences & Discovery
6. Scenario 18: AppView Admin Operations
7. Scenario 19: Contact Management & Age Assurance
8. Scenario 20: Unspecced Search & Discovery
9. Register all in run_scenario.py
10. Update README.md endpoint coverage matrix

## Client Methods Needed
See detailed spec - admin_get/post, drafts CRUD, preferences, typeahead, mutes,
relationships, starter packs, feed discovery, notification management, contact
service, age assurance, unspecced search.

## Files Changed
- scripts/lib/atproto/client.py (+~250 lines)
- scripts/scenarios/scenarios/14_drafts_bookmarks.py (new)
- scripts/scenarios/scenarios/15_mutes_relationships_starterpacks.py (new)
- scripts/scenarios/scenarios/16_notification_management.py (new)
- scripts/scenarios/scenarios/17_actor_preferences_discovery.py (new)
- scripts/scenarios/scenarios/18_admin_operations.py (new)
- scripts/scenarios/scenarios/19_contact_age_assurance.py (new)
- scripts/scenarios/scenarios/20_unspecced_search.py (new)
- scripts/scenarios/run_scenario.py (register 7 entries)
- scripts/scenarios/README.md (update tables)

## Key Decisions
- Admin ops uses raw HTTP (not XRPC) on AppView port 3200
- Unspecced/contact/age-assurance guarded with step_skipped for stubs
- All scenarios standalone (create own accounts)
- Follow existing pattern from scenarios 01-13
