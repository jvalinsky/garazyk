/**
 * Tests for Markdown link parser
 */

import { test } from 'node:test';
import assert from 'node:assert';
import {
  parseMarkdownLinks,
  classifyLink,
  isInternalLink,
  filterInternalLinks,
  filterExternalLinks,
  groupLinksByType,
  LinkType
} from './link-parser.js';

// ============================================================================
// classifyLink tests
// ============================================================================

test('classifyLink identifies external HTTP links', () => {
  assert.strictEqual(classifyLink('http://example.com'), LinkType.EXTERNAL);
  assert.strictEqual(classifyLink('https://example.com'), LinkType.EXTERNAL);
});

test('classifyLink identifies external protocol links', () => {
  assert.strictEqual(classifyLink('ftp://example.com'), LinkType.EXTERNAL);
  assert.strictEqual(classifyLink('mailto:test@example.com'), LinkType.EXTERNAL);
  assert.strictEqual(classifyLink('ssh://git@github.com'), LinkType.EXTERNAL);
});

test('classifyLink identifies anchor links', () => {
  assert.strictEqual(classifyLink('#section'), LinkType.ANCHOR);
  assert.strictEqual(classifyLink('#heading-with-dashes'), LinkType.ANCHOR);
});

test('classifyLink identifies absolute paths', () => {
  assert.strictEqual(classifyLink('/docs/file.md'), LinkType.ABSOLUTE);
  assert.strictEqual(classifyLink('/path/to/file'), LinkType.ABSOLUTE);
});

test('classifyLink identifies relative paths', () => {
  assert.strictEqual(classifyLink('./file.md'), LinkType.RELATIVE);
  assert.strictEqual(classifyLink('../other.md'), LinkType.RELATIVE);
  assert.strictEqual(classifyLink('file.md'), LinkType.RELATIVE);
  assert.strictEqual(classifyLink('dir/file.md'), LinkType.RELATIVE);
});

test('classifyLink handles edge cases', () => {
  assert.strictEqual(classifyLink(''), LinkType.EXTERNAL);
  assert.strictEqual(classifyLink(null), LinkType.EXTERNAL);
  assert.strictEqual(classifyLink(undefined), LinkType.EXTERNAL);
});

// ============================================================================
// isInternalLink tests
// ============================================================================

test('isInternalLink returns true for internal link types', () => {
  assert.strictEqual(isInternalLink(LinkType.RELATIVE), true);
  assert.strictEqual(isInternalLink(LinkType.ABSOLUTE), true);
  assert.strictEqual(isInternalLink(LinkType.ANCHOR), true);
});

test('isInternalLink returns false for external link types', () => {
  assert.strictEqual(isInternalLink(LinkType.EXTERNAL), false);
});

// ============================================================================
// parseMarkdownLinks - inline links tests
// ============================================================================

test('parseMarkdownLinks extracts simple inline link', () => {
  const content = 'Check out [this link](./file.md) for more info.';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].type, LinkType.RELATIVE);
  assert.strictEqual(links[0].text, 'this link');
  assert.strictEqual(links[0].href, './file.md');
  assert.strictEqual(links[0].line, 1);
  assert.ok(links[0].column > 0);
});

test('parseMarkdownLinks extracts multiple inline links', () => {
  const content = `
First [link](./file1.md) here.
Second [link](../file2.md) there.
Third [link](/absolute/path.md) everywhere.
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 3);
  assert.strictEqual(links[0].href, './file1.md');
  assert.strictEqual(links[1].href, '../file2.md');
  assert.strictEqual(links[2].href, '/absolute/path.md');
  
  // Check line numbers
  assert.strictEqual(links[0].line, 2);
  assert.strictEqual(links[1].line, 3);
  assert.strictEqual(links[2].line, 4);
});

test('parseMarkdownLinks handles inline links with titles', () => {
  const content = '[link](./file.md "Title text")';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].href, './file.md');
  assert.strictEqual(links[0].text, 'link');
});

test('parseMarkdownLinks handles links with anchors', () => {
  const content = '[section](#heading) and [file](./doc.md#section)';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 2);
  assert.strictEqual(links[0].type, LinkType.ANCHOR);
  assert.strictEqual(links[0].href, '#heading');
  assert.strictEqual(links[1].type, LinkType.RELATIVE);
  assert.strictEqual(links[1].href, './doc.md#section');
});

// ============================================================================
// parseMarkdownLinks - autolinks tests
// ============================================================================

test('parseMarkdownLinks extracts autolinks', () => {
  const content = 'Visit <https://example.com> for more.';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].type, LinkType.EXTERNAL);
  assert.strictEqual(links[0].href, 'https://example.com');
  assert.strictEqual(links[0].text, 'https://example.com');
});

test('parseMarkdownLinks extracts mailto autolinks', () => {
  const content = 'Email me at <mailto:test@example.com>';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].type, LinkType.EXTERNAL);
  assert.strictEqual(links[0].href, 'mailto:test@example.com');
});

// ============================================================================
// parseMarkdownLinks - bare URLs tests
// ============================================================================

test('parseMarkdownLinks extracts bare URLs', () => {
  const content = 'Visit https://example.com for more info.';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].type, LinkType.EXTERNAL);
  assert.strictEqual(links[0].href, 'https://example.com');
});

test('parseMarkdownLinks handles multiple bare URLs', () => {
  const content = 'See http://example.com and https://other.com';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 2);
  assert.strictEqual(links[0].href, 'http://example.com');
  assert.strictEqual(links[1].href, 'https://other.com');
});

// ============================================================================
// parseMarkdownLinks - reference-style links tests
// ============================================================================

test('parseMarkdownLinks extracts reference-style links', () => {
  const content = `
Check [this link][ref1] for info.

[ref1]: ./file.md
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].type, LinkType.RELATIVE);
  assert.strictEqual(links[0].text, 'this link');
  assert.strictEqual(links[0].href, './file.md');
  assert.strictEqual(links[0].refId, 'ref1');
});

test('parseMarkdownLinks handles implicit reference links', () => {
  const content = `
Check [this link][] for info.

[this link]: https://example.com
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].text, 'this link');
  assert.strictEqual(links[0].href, 'https://example.com');
});

test('parseMarkdownLinks handles shortcut reference links', () => {
  const content = `
Check [example] for info.

[example]: https://example.com
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].text, 'example');
  assert.strictEqual(links[0].href, 'https://example.com');
});

test('parseMarkdownLinks ignores undefined references', () => {
  const content = 'Check [this link][undefined] for info.';
  const links = parseMarkdownLinks(content);
  
  // Should not include the link since reference is undefined
  assert.strictEqual(links.length, 0);
});

test('parseMarkdownLinks handles case-insensitive references', () => {
  const content = `
Check [this link][REF1] for info.

[ref1]: ./file.md
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].href, './file.md');
});

// ============================================================================
// parseMarkdownLinks - code block handling tests
// ============================================================================

test('parseMarkdownLinks ignores links in fenced code blocks', () => {
  const content = `
Normal [link](./file.md) here.

\`\`\`
[code link](./code.md)
\`\`\`

Another [link](./file2.md) here.
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 2);
  assert.strictEqual(links[0].href, './file.md');
  assert.strictEqual(links[1].href, './file2.md');
});

test('parseMarkdownLinks ignores links in inline code', () => {
  const content = 'Normal [link](./file.md) and `[code](./code.md)` inline.';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].href, './file.md');
});

test('parseMarkdownLinks ignores links in indented code blocks', () => {
  const content = `
Normal [link](./file.md) here.

    [code link](./code.md)

Another [link](./file2.md) here.
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 2);
  assert.strictEqual(links[0].href, './file.md');
  assert.strictEqual(links[1].href, './file2.md');
});

// ============================================================================
// parseMarkdownLinks - edge cases tests
// ============================================================================

test('parseMarkdownLinks handles empty content', () => {
  assert.deepStrictEqual(parseMarkdownLinks(''), []);
  assert.deepStrictEqual(parseMarkdownLinks(null), []);
  assert.deepStrictEqual(parseMarkdownLinks(undefined), []);
});

test('parseMarkdownLinks handles content with no links', () => {
  const content = 'This is just plain text with no links.';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 0);
});

test('parseMarkdownLinks sorts links by line and column', () => {
  const content = `
Line 1 [second](./b.md) and [first](./a.md)
Line 2 [third](./c.md)
`;
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 3);
  // Should be sorted by position in file
  assert.strictEqual(links[0].href, './b.md');
  assert.strictEqual(links[1].href, './a.md');
  assert.strictEqual(links[2].href, './c.md');
});

test('parseMarkdownLinks handles special characters in link text', () => {
  const content = '[Link with **bold** and `code`](./file.md)';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].text, 'Link with **bold** and `code`');
});

test('parseMarkdownLinks handles URLs with query parameters', () => {
  const content = '[link](./file.md?param=value&other=123)';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].href, './file.md?param=value&other=123');
});

test('parseMarkdownLinks handles URLs with fragments', () => {
  const content = '[link](./file.md#section-name)';
  const links = parseMarkdownLinks(content);
  
  assert.strictEqual(links.length, 1);
  assert.strictEqual(links[0].href, './file.md#section-name');
});

// ============================================================================
// filterInternalLinks tests
// ============================================================================

test('filterInternalLinks returns only internal links', () => {
  const content = `
[relative](./file.md)
[absolute](/docs/file.md)
[anchor](#section)
[external](https://example.com)
`;
  const links = parseMarkdownLinks(content);
  const internal = filterInternalLinks(links);
  
  assert.strictEqual(internal.length, 3);
  assert.ok(internal.every(link => isInternalLink(link.type)));
});

// ============================================================================
// filterExternalLinks tests
// ============================================================================

test('filterExternalLinks returns only external links', () => {
  const content = `
[relative](./file.md)
[external1](https://example.com)
[external2](http://other.com)
`;
  const links = parseMarkdownLinks(content);
  const external = filterExternalLinks(links);
  
  assert.strictEqual(external.length, 2);
  assert.ok(external.every(link => link.type === LinkType.EXTERNAL));
});

// ============================================================================
// groupLinksByType tests
// ============================================================================

test('groupLinksByType groups links correctly', () => {
  const content = `
[relative](./file.md)
[absolute](/docs/file.md)
[anchor](#section)
[external](https://example.com)
`;
  const links = parseMarkdownLinks(content);
  const grouped = groupLinksByType(links);
  
  assert.strictEqual(grouped.relative.length, 1);
  assert.strictEqual(grouped.absolute.length, 1);
  assert.strictEqual(grouped.anchor.length, 1);
  assert.strictEqual(grouped.external.length, 1);
  assert.strictEqual(grouped.reference.length, 0);
});

test('groupLinksByType handles empty input', () => {
  const grouped = groupLinksByType([]);
  
  assert.strictEqual(grouped.relative.length, 0);
  assert.strictEqual(grouped.absolute.length, 0);
  assert.strictEqual(grouped.anchor.length, 0);
  assert.strictEqual(grouped.external.length, 0);
  assert.strictEqual(grouped.reference.length, 0);
});

// ============================================================================
// Real-world example tests
// ============================================================================

test('parseMarkdownLinks handles complex real-world document', () => {
  const content = `
# Documentation

See the [installation guide](./guides/install.md) for setup instructions.

## External Resources

- Official site: <https://example.com>
- GitHub: https://github.com/user/repo
- Email: <mailto:support@example.com>

## Internal Links

Jump to [configuration](#configuration) section.

For more details, see:
- [API Reference](/docs/api.md)
- [Examples](../examples/basic.md)

[guide]: ./guides/advanced.md
[api]: /docs/api.md

Check the [advanced guide][guide] and [API docs][api].

\`\`\`javascript
// This [link](./code.md) should be ignored
const url = "https://example.com/ignored";
\`\`\`

## Configuration

Configuration details here.
`;

  const links = parseMarkdownLinks(content);
  
  // Count different types
  const grouped = groupLinksByType(links);
  
  assert.ok(grouped.relative.length > 0, 'Should have relative links');
  assert.ok(grouped.absolute.length > 0, 'Should have absolute links');
  assert.ok(grouped.anchor.length > 0, 'Should have anchor links');
  assert.ok(grouped.external.length > 0, 'Should have external links');
  
  // Verify code blocks are ignored
  const codeLinks = links.filter(link => 
    link.href.includes('code.md') || link.href.includes('ignored')
  );
  assert.strictEqual(codeLinks.length, 0, 'Should ignore links in code blocks');
  
  // Verify reference links are resolved
  const guideLinks = links.filter(link => link.text === 'advanced guide');
  assert.strictEqual(guideLinks.length, 1);
  assert.strictEqual(guideLinks[0].href, './guides/advanced.md');
});

test('parseMarkdownLinks handles README-style document', () => {
  const content = `
# Project Name

[![Build Status](https://ci.example.com/badge.svg)](https://ci.example.com)

## Quick Start

1. Read the [installation guide](docs/install.md)
2. Check out [examples](./examples/)
3. See [API documentation](/docs/api/)

## Links

- [Contributing](CONTRIBUTING.md)
- [License](LICENSE)
- [Changelog](CHANGELOG.md)

Visit https://example.com for more information.
`;

  const links = parseMarkdownLinks(content);
  
  assert.ok(links.length > 0, 'Should extract links from README');
  
  const internal = filterInternalLinks(links);
  const external = filterExternalLinks(links);
  
  assert.ok(internal.length > 0, 'Should have internal links');
  assert.ok(external.length > 0, 'Should have external links');
});
