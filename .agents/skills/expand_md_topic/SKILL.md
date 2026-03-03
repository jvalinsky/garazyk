---
name: Expand Topic Markdown
description: Takes a markdown file outlining a topic and expands it fully into a proper, comprehensive discussion.
---

# Expand Markdown Topic

## Purpose
This skill helps you expand a brief or outlined markdown file describing a specific topic into a comprehensive, fully-fledged discussion. It is particularly useful for generating documentation, tutorials, blog posts, or deep dives from high-level notes.

## Instructions

1. **Read the Input File:**
   - Use the `view_file` tool to read the contents of the target markdown file provided by the user.
   - Analyze the target topic, structure, and any specific points or outlines listed.

2. **Research & Context Gathering (If necessary):**
   - If the topic requires deeper technical knowledge or specific citations, use the `search_web` tool to find canonical sources, documentation, or RFCs/BIPs.
   - If the topic relates to a local codebase, use `grep_search` or `view_file` to find relevant code snippets, architecture details, and implementation specifics.

3. **Expand the Content:**
   - Structure the expanded discussion logically with an introduction, detailed body sections, and a conclusion/summary.
   - **Introduction:** Clearly define the topic, why it is important, and what the discussion will cover.
   - **Body Sections:** 
     - Expand on each point from the original outline.
     - Provide detailed explanations, analogies, and examples.
     - If discussing code or technical concepts, include well-formatted code blocks and Mermaid.js diagrams (if appropriate) to illustrate complex flows.
     - Cite sources or integrate canonical knowledge directly into the text.
   - **Conclusion/Summary:** Wrap up the discussion, highlighting the main takeaways.
   
4. **Formatting:**
   - Ensure the output strictly follows GitHub Flavored Markdown.
   - Use headings (`##`, `###`) to logically separate sections.
   - Use bolding and lists to improve scannability.
   - Apply callouts or alerts (e.g., `> [!NOTE]`, `> [!IMPORTANT]`) for critical information or warnings if supported by the destination format.

5. **Write the Output:**
   - Use the `replace_file_content` or `write_to_file` tool to overwrite the original markdown file (or write to a new file, as instructed by the user) with the expanded content.

6. **Review with User:**
   - Use the `notify_user` tool to present a brief summary of the expansions made and ask the user to review the final document.
