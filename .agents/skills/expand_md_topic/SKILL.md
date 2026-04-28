---
name: Expand Topic Markdown
description: Takes a markdown file outlining a topic and expands it fully into a proper, comprehensive discussion.
---

# Expand Markdown Topic

## Purpose

Expand a brief or outlined Markdown file into a comprehensive discussion, tutorial, deep dive, or documentation page while preserving the user's requested audience, tone, and destination format.

## Workflow

1. **Read the input file**
   - Inspect the target Markdown file supplied by the user.
   - Identify the topic, existing outline, implied audience, gaps, and any constraints in the file.

2. **Gather context when needed**
   - For technical topics, prefer local repository sources, nearby docs, tests, schemas, and implementation files.
   - For external standards or fast-moving topics, consult canonical sources such as official docs, RFCs, BIPs, specifications, or primary project documentation.
   - Keep citations or source notes when the expanded document depends on external claims.

3. **Expand the content**
   - Preserve the original intent and useful structure.
   - Add a clear introduction, complete body sections, examples, and a concise ending only when they fit the document type.
   - Use code blocks, tables, diagrams, or callouts only when they make the topic easier to understand.
   - Avoid filler, generic summary paragraphs, and invented authority.

4. **Edit the Markdown file**
   - Update the original file unless the user asks for a new output path.
   - Keep GitHub Flavored Markdown valid.
   - Preserve existing frontmatter, links, anchors, and project-specific conventions unless the user asks to change them.

5. **Report completion**
   - Summarize the main expansions and any assumptions, sources, or unresolved gaps.
