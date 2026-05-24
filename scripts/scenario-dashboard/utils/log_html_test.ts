import { assertEquals } from "@std/assert";
import { sanitizeLogHtml } from "./log_html.ts";

Deno.test("sanitizeLogHtml: removes script tags", () => {
  const input = '<span>ok</span><script>alert(1)</script>';
  assertEquals(sanitizeLogHtml(input), "<span>ok</span>");
});

Deno.test("sanitizeLogHtml: strips inline handlers", () => {
  const input = '<span onclick="alert(1)">line</span>';
  assertEquals(sanitizeLogHtml(input), '<span>line</span>');
});

Deno.test("sanitizeLogHtml: neutralizes javascript hrefs", () => {
  const input = '<a href="javascript:alert(1)">x</a>';
  assertEquals(sanitizeLogHtml(input), '<a href="#">x</a>');
});
