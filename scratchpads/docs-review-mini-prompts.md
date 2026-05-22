# Documentation Review Mini-Prompts

Use these as focused prompts for scratchpad-based review passes. Save outputs as `scratchpads/docs-review-<pass>.md` and attach them to the relevant deciduous node.

## Staleness pass

Review the selected docs for stale commands, paths, service names, environment variables, URLs, generated-file warnings, or workflow steps. For each issue, cite the doc path, the stale text, the current source of truth, and the recommended fix.

## Delete/keep pass

Identify docs that should be deleted, archived, merged, or kept. Require evidence: orphaned references, superseded content, duplicated content, current usage, or operational risk if removed.

## Duplicate/overlap pass

Find overlapping documentation across README files, `docs/`, `.agents/`, `.opencode/workflows/`, scripts, and ops notes. Recommend a canonical location and list unique content that must be preserved before merging.

## Dangerous instruction pass

Look for docs that could cause unsafe or incorrect actions: production deployment mistakes, destructive commands, credential exposure, wrong ports, wrong hostnames, outdated auth flows, or misleading test commands. Rank findings by severity.

## Missing documentation pass

Compare current source areas and scripts against existing docs. Identify undocumented public commands, workflows, services, config files, environment variables, and operational procedures.

## User journey pass

Read docs from the perspective of a new contributor trying to build, test, run local services, deploy, and debug. Note gaps, contradictions, circular references, or missing prerequisites.

## Final backlog prompt

Convert all scratchpad findings into a concise backlog table with columns: path, status, evidence, proposed change, risk, and deciduous node. Separate quick wins from changes that need owner review.
