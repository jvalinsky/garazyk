/** Sanitize ANSI-converted log HTML before trusted insertion. @module log_html */

const SCRIPT_RE = /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi;
const EVENT_HANDLER_RE = /\s+on\w+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)/gi;
const JS_HREF_RE = /\bhref\s*=\s*["']javascript:[^"']*["']/gi;

/** Strip script tags, inline handlers, and javascript: links from log HTML. */
export function sanitizeLogHtml(html: string): string {
  return html
    .replace(SCRIPT_RE, "")
    .replace(EVENT_HANDLER_RE, "")
    .replace(JS_HREF_RE, 'href="#"');
}
