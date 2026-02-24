/**
 * Markdown Link Parser
 * 
 * Parses Markdown files to extract all links including:
 * - Inline links: [text](url)
 * - Autolinks: <url>
 * - Bare URLs: http://example.com
 * - Anchor links: #section
 * - Reference-style links: [text][ref]
 * 
 * Distinguishes between internal (relative) and external (absolute) links.
 * Provides line and column information for each link.
 */

/**
 * Link type enumeration
 */
export const LinkType = {
  RELATIVE: 'relative',      // ./file.md, ../other.md, file.md
  ABSOLUTE: 'absolute',      // /docs/file.md
  ANCHOR: 'anchor',          // #section
  EXTERNAL: 'external',      // http://example.com, https://example.com
  REFERENCE: 'reference'     // [text][ref] style links
};

/**
 * Link object structure
 * @typedef {Object} Link
 * @property {string} type - Link type (relative/absolute/anchor/external/reference)
 * @property {string} text - Link text or label
 * @property {string} href - Link target URL or path
 * @property {number} line - Line number (1-indexed)
 * @property {number} column - Column number (1-indexed)
 * @property {string} [refId] - Reference ID for reference-style links
 */

/**
 * Determines the type of a link based on its href
 * @param {string} href - The link href
 * @returns {string} Link type from LinkType enum
 */
export function classifyLink(href) {
  if (!href || typeof href !== 'string') {
    return LinkType.EXTERNAL;
  }

  // External links (http://, https://, ftp://, mailto:, etc.)
  if (/^[a-z][a-z0-9+.-]*:/i.test(href)) {
    return LinkType.EXTERNAL;
  }

  // Anchor links (#section)
  if (href.startsWith('#')) {
    return LinkType.ANCHOR;
  }

  // Absolute paths (/docs/file.md)
  if (href.startsWith('/')) {
    return LinkType.ABSOLUTE;
  }

  // Relative paths (./file.md, ../file.md, file.md)
  return LinkType.RELATIVE;
}

/**
 * Checks if a link is internal (relative or absolute path to local file)
 * @param {string} type - Link type from LinkType enum
 * @returns {boolean} True if link is internal
 */
export function isInternalLink(type) {
  return type === LinkType.RELATIVE || 
         type === LinkType.ABSOLUTE || 
         type === LinkType.ANCHOR;
}

/**
 * Parses inline links: [text](url)
 * @param {string} content - Markdown content
 * @param {Array<{start: number, end: number}>} codeRanges - Code block ranges
 * @returns {Link[]} Array of link objects
 */
function parseInlineLinks(content, codeRanges) {
  const links = [];
  // Match [text](url) or [text](url "title")
  // Handles escaped brackets and parentheses
  const inlineLinkRegex = /\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g;
  
  let match;
  while ((match = inlineLinkRegex.exec(content)) !== null) {
    const position = match.index;
    
    // Skip if in code block
    if (isInCodeBlock(position, codeRanges)) {
      continue;
    }
    
    const text = match[1];
    const href = match[2];
    
    // Calculate line and column
    const beforeMatch = content.substring(0, position);
    const line = (beforeMatch.match(/\n/g) || []).length + 1;
    const lastNewline = beforeMatch.lastIndexOf('\n');
    const column = position - lastNewline;
    
    const type = classifyLink(href);
    
    links.push({
      type,
      text,
      href,
      line,
      column
    });
  }
  
  return links;
}

/**
 * Parses autolinks: <url>
 * @param {string} content - Markdown content
 * @param {Array<{start: number, end: number}>} codeRanges - Code block ranges
 * @returns {Link[]} Array of link objects
 */
function parseAutolinks(content, codeRanges) {
  const links = [];
  // Match <url> but not HTML tags
  const autolinkRegex = /<((?:https?|ftp|mailto):[^>\s]+)>/g;
  
  let match;
  while ((match = autolinkRegex.exec(content)) !== null) {
    const position = match.index;
    
    // Skip if in code block
    if (isInCodeBlock(position, codeRanges)) {
      continue;
    }
    
    const href = match[1];
    
    // Calculate line and column
    const beforeMatch = content.substring(0, position);
    const line = (beforeMatch.match(/\n/g) || []).length + 1;
    const lastNewline = beforeMatch.lastIndexOf('\n');
    const column = position - lastNewline;
    
    const type = classifyLink(href);
    
    links.push({
      type,
      text: href,
      href,
      line,
      column
    });
  }
  
  return links;
}

/**
 * Parses bare URLs in text
 * @param {string} content - Markdown content
 * @param {Array<{start: number, end: number}>} codeRanges - Code block ranges
 * @returns {Link[]} Array of link objects
 */
function parseBareUrls(content, codeRanges) {
  const links = [];
  // Match URLs not already in markdown link syntax
  // This is a simplified pattern - bare URLs in markdown are tricky
  // Negative lookbehind to avoid matching URLs in links, autolinks, or reference definitions
  const bareUrlRegex = /(?<![(\[<:])https?:\/\/[^\s<>)\]]+/g;
  
  let match;
  while ((match = bareUrlRegex.exec(content)) !== null) {
    const position = match.index;
    
    // Skip if in code block
    if (isInCodeBlock(position, codeRanges)) {
      continue;
    }
    
    // Skip if this is part of a reference definition
    // Check if the line starts with [ref]: before this URL
    const beforeMatch = content.substring(0, position);
    const lastNewline = beforeMatch.lastIndexOf('\n');
    const lineStart = lastNewline === -1 ? 0 : lastNewline + 1;
    const linePrefix = content.substring(lineStart, position);
    if (/^\[[^\]]+\]:\s*$/.test(linePrefix)) {
      continue;
    }
    
    const href = match[0];
    
    // Calculate line and column
    const line = (beforeMatch.match(/\n/g) || []).length + 1;
    const column = position - lastNewline;
    
    links.push({
      type: LinkType.EXTERNAL,
      text: href,
      href,
      line,
      column
    });
  }
  
  return links;
}

/**
 * Parses reference-style link definitions: [id]: url
 * @param {string} content - Markdown content
 * @returns {Map<string, string>} Map of reference IDs to URLs
 */
function parseReferenceDefs(content) {
  const refs = new Map();
  // Match [id]: url or [id]: url "title"
  const refDefRegex = /^\[([^\]]+)\]:\s*(\S+)(?:\s+"[^"]*")?$/gm;
  
  let match;
  while ((match = refDefRegex.exec(content)) !== null) {
    const refId = match[1].toLowerCase();
    const href = match[2];
    refs.set(refId, href);
  }
  
  return refs;
}

/**
 * Parses reference-style links: [text][ref] or [text][]
 * @param {string} content - Markdown content
 * @param {Map<string, string>} refs - Reference definitions
 * @param {Array<{start: number, end: number}>} codeRanges - Code block ranges
 * @returns {Link[]} Array of link objects
 */
function parseReferenceLinks(content, refs, codeRanges) {
  const links = [];
  // Match [text][ref] or [text][] or [text]
  const refLinkRegex = /\[([^\]]+)\](?:\[([^\]]*)\])?(?!\()/g;
  
  let match;
  while ((match = refLinkRegex.exec(content)) !== null) {
    const position = match.index;
    
    // Skip if in code block
    if (isInCodeBlock(position, codeRanges)) {
      continue;
    }
    
    const text = match[1];
    // For [text][], match[2] is empty string; for [text], match[2] is undefined
    // In both cases, use text as the refId
    const refId = (match[2] !== undefined && match[2] !== '' ? match[2] : text).toLowerCase();
    
    // Skip if this is a reference definition (starts at beginning of line)
    const beforeMatch = content.substring(0, position);
    const lastNewline = beforeMatch.lastIndexOf('\n');
    const lineStart = lastNewline === -1 ? 0 : lastNewline + 1;
    const linePrefix = content.substring(lineStart, position).trim();
    if (linePrefix === '' && content[position + match[0].length] === ':') {
      continue;
    }
    
    // Look up the reference
    const href = refs.get(refId);
    if (!href) {
      // Reference not found - skip
      continue;
    }
    
    // Calculate line and column
    const line = (beforeMatch.match(/\n/g) || []).length + 1;
    const column = position - lastNewline;
    
    const type = classifyLink(href);
    
    links.push({
      type,
      text,
      href,
      line,
      column,
      refId
    });
  }
  
  return links;
}

/**
 * Identifies code block regions in the content
 * @param {string} content - Markdown content
 * @returns {Array<{start: number, end: number}>} Array of code block ranges
 */
function getCodeBlockRanges(content) {
  const ranges = [];
  
  // Find fenced code blocks (``` or ~~~)
  const fencedRegex = /^```[\s\S]*?^```$|^~~~[\s\S]*?^~~~$/gm;
  let match;
  while ((match = fencedRegex.exec(content)) !== null) {
    ranges.push({ start: match.index, end: match.index + match[0].length });
  }
  
  // Find indented code blocks (4 spaces or tab at start of line)
  const lines = content.split('\n');
  let inCodeBlock = false;
  let codeBlockStart = 0;
  let position = 0;
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const isCodeLine = /^(?:    |\t)/.test(line);
    
    if (isCodeLine && !inCodeBlock) {
      inCodeBlock = true;
      codeBlockStart = position;
    } else if (!isCodeLine && inCodeBlock && line.trim() !== '') {
      inCodeBlock = false;
      ranges.push({ start: codeBlockStart, end: position });
    }
    
    position += line.length + 1; // +1 for newline
  }
  
  if (inCodeBlock) {
    ranges.push({ start: codeBlockStart, end: content.length });
  }
  
  // Find inline code (`code`)
  const inlineCodeRegex = /`[^`\n]+`/g;
  while ((match = inlineCodeRegex.exec(content)) !== null) {
    ranges.push({ start: match.index, end: match.index + match[0].length });
  }
  
  // Sort and merge overlapping ranges
  ranges.sort((a, b) => a.start - b.start);
  const merged = [];
  for (const range of ranges) {
    if (merged.length === 0 || merged[merged.length - 1].end < range.start) {
      merged.push(range);
    } else {
      merged[merged.length - 1].end = Math.max(merged[merged.length - 1].end, range.end);
    }
  }
  
  return merged;
}

/**
 * Checks if a position is inside a code block
 * @param {number} position - Position in content
 * @param {Array<{start: number, end: number}>} codeRanges - Code block ranges
 * @returns {boolean} True if position is in code
 */
function isInCodeBlock(position, codeRanges) {
  return codeRanges.some(range => position >= range.start && position < range.end);
}

/**
 * Parses all links from Markdown content
 * @param {string} content - Markdown file content
 * @returns {Link[]} Array of link objects with type, text, href, line, column
 */
export function parseMarkdownLinks(content) {
  if (!content || typeof content !== 'string') {
    return [];
  }
  
  // Identify code block regions
  const codeRanges = getCodeBlockRanges(content);
  
  // Parse reference definitions first
  const refs = parseReferenceDefs(content);
  
  // Parse all link types
  const inlineLinks = parseInlineLinks(content, codeRanges);
  const autolinks = parseAutolinks(content, codeRanges);
  const bareUrls = parseBareUrls(content, codeRanges);
  const referenceLinks = parseReferenceLinks(content, refs, codeRanges);
  
  // Combine all links
  const allLinks = [
    ...inlineLinks,
    ...autolinks,
    ...bareUrls,
    ...referenceLinks
  ];
  
  // Sort by line and column
  allLinks.sort((a, b) => {
    if (a.line !== b.line) {
      return a.line - b.line;
    }
    return a.column - b.column;
  });
  
  return allLinks;
}

/**
 * Filters links to only internal links (relative, absolute, anchor)
 * @param {Link[]} links - Array of link objects
 * @returns {Link[]} Array of internal link objects
 */
export function filterInternalLinks(links) {
  return links.filter(link => isInternalLink(link.type));
}

/**
 * Filters links to only external links
 * @param {Link[]} links - Array of link objects
 * @returns {Link[]} Array of external link objects
 */
export function filterExternalLinks(links) {
  return links.filter(link => link.type === LinkType.EXTERNAL);
}

/**
 * Groups links by type
 * @param {Link[]} links - Array of link objects
 * @returns {Object} Object with links grouped by type
 */
export function groupLinksByType(links) {
  const grouped = {
    relative: [],
    absolute: [],
    anchor: [],
    external: [],
    reference: []
  };
  
  for (const link of links) {
    grouped[link.type].push(link);
  }
  
  return grouped;
}
