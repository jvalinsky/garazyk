#!/usr/bin/env python3
import os
import re

renames = {
    "AppViewActorIndexer": "GZAppViewActorIndexer",
    "AppViewAdminRoutePack": "GZAppViewAdminRoutePack",
    "AppViewBackfillOrchestrator": "GZAppViewBackfillOrchestrator",
    "AppViewBackfillWorker": "GZAppViewBackfillWorker",
    "AppViewBookmarkIndexer": "GZAppViewBookmarkIndexer",
    "AppViewCheckpoint": "GZAppViewCheckpoint",
    "AppViewCollectionFilter": "GZAppViewCollectionFilter",
    "AppViewConfiguration": "GZAppViewConfiguration",
    "AppViewCustomQueryRegistry": "GZAppViewCustomQueryRegistry",
    "AppViewDatabase": "GZAppViewDatabase",
    "AppViewFeedIndexer": "GZAppViewFeedIndexer",
    "AppViewGenericIndexer": "GZAppViewGenericIndexer",
    "AppViewGenericQueryHandler": "GZAppViewGenericQueryHandler",
    "AppViewGraphIndexer": "GZAppViewGraphIndexer",
    "AppViewGraphQueryHandler": "GZAppViewGraphQueryHandler",
    "AppViewGroupIndexer": "GZAppViewGroupIndexer",
    "AppViewIndexHookRegistry": "GZAppViewIndexHookRegistry",
    "AppViewIngestEngine": "GZAppViewIngestEngine",
    "AppViewIngestEvent": "GZAppViewIngestEvent",
    "AppViewLexiconEndpointGenerator": "GZAppViewLexiconEndpointGenerator",
    "AppViewNotificationIndexer": "GZAppViewNotificationIndexer",
    "AppViewOAuth2Middleware": "GZAppViewOAuth2Middleware",
    "AppViewPendingDelta": "GZAppViewPendingDelta",
    "AppViewRelayConnection": "GZAppViewRelayConnection",
    "AppViewRelevanceMembership": "GZAppViewRelevanceMembership",
    "AppViewRelevanceSet": "GZAppViewRelevanceSet",
    "AppViewRepoSyncState": "GZAppViewRepoSyncState",
    "AppViewRuntime": "GZAppViewRuntime",
    "AppViewSearchIndexHook": "GZAppViewSearchIndexHook",
    "AppViewWebhookHook": "GZAppViewWebhookHook",
    "AppViewWriteProxy": "GZAppViewWriteProxy",
    "BeskidConfiguration": "GZBeskidConfiguration",
    "BeskidDatabase": "GZBeskidDatabase",
    "BeskidMetrics": "GZBeskidMetrics",
    "BeskidRuntime": "GZBeskidRuntime",
    "BeskidXrpcRoutePack": "GZBeskidXrpcRoutePack",
    "MikrusConfiguration": "GZMikrusConfiguration",
    "MikrusDatabase": "GZMikrusDatabase",
    "MikrusLinkExtractor": "GZMikrusLinkExtractor",
    "MikrusMetrics": "GZMikrusMetrics",
    "MikrusRuntime": "GZMikrusRuntime",
    "MikrusSourceSpec": "GZMikrusSourceSpec",
    "MikrusXrpcRoutePack": "GZMikrusXrpcRoutePack",
    "SyrenaMetrics": "GZSyrenaMetrics",
}

# Sort by descending length to avoid partial matches
sorted_renames = sorted(renames.items(), key=lambda x: -len(x[0]))

def process_line(line):
    if line.lstrip().startswith('#import') or line.lstrip().startswith('#include'):
        return line
    # Split line into segments: inside @"..." strings vs outside
    # We preserve content inside @"..." strings
    parts = re.split(r'(@"(?:[^"\\]|\\.)*")', line)
    for i, part in enumerate(parts):
        if part.startswith('@"'):
            continue
        for old, new in sorted_renames:
            part = re.sub(r'\b' + old + r'\b', new, part)
        parts[i] = part
    return ''.join(parts)

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Garazyk')
root = os.path.normpath(root)
changed_files = 0

for dirpath, dirnames, filenames in os.walk(root):
    # Skip Tests/fixtures/
    rel = os.path.relpath(dirpath, root)
    if rel.startswith('Tests/fixtures') or '/Tests/fixtures' in rel:
        continue
    for fname in filenames:
        if not (fname.endswith('.m') or fname.endswith('.h')):
            continue
        fpath = os.path.join(dirpath, fname)
        with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
            original = f.read()
        lines = original.split('\n')
        new_lines = [process_line(l) for l in lines]
        new_content = '\n'.join(new_lines)
        if new_content != original:
            with open(fpath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            changed_files += 1

print(f"Modified {changed_files} files.")
