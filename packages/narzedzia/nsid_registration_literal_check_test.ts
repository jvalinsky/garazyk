import { assertEquals } from "@std/assert";
import {
  findRawNsidRegistrationLiterals,
} from "./nsid_registration_literal_check.ts";

Deno.test("findRawNsidRegistrationLiterals accepts generated constants", () => {
  const source =
    "[dispatcher registerMethod:kGZXrpcNSID_com_atproto_server_getSession handler:nil];";

  assertEquals(findRawNsidRegistrationLiterals(source, "Example.m"), []);
});

Deno.test("findRawNsidRegistrationLiterals rejects a direct NSID literal", () => {
  const source =
    '[dispatcher registerMethod:@"com.atproto.server.getSession" handler:nil];';

  assertEquals(findRawNsidRegistrationLiterals(source, "Example.m"), [
    {
      file: "Example.m",
      line: 1,
      literal: "com.atproto.server.getSession",
    },
  ]);
});

Deno.test("findRawNsidRegistrationLiterals permits internal handlers", () => {
  const source = '[dispatcher registerMethod:@"_health" handler:nil];';

  assertEquals(findRawNsidRegistrationLiterals(source, "Example.m"), []);
});

Deno.test("findRawNsidRegistrationLiterals handles multiline registrations", () => {
  const source = [
    "[dispatcher registerMethod:",
    '    @"com.atproto.server.getSession"',
    "                 handler:nil];",
  ].join("\n");

  assertEquals(findRawNsidRegistrationLiterals(source, "Example.m"), [
    {
      file: "Example.m",
      line: 2,
      literal: "com.atproto.server.getSession",
    },
  ]);
});

Deno.test("findRawNsidRegistrationLiterals ignores line and block comments", () => {
  const source = [
    '// [dispatcher registerMethod:@"com.atproto.server.getSession" handler:nil];',
    '/* [dispatcher registerMethod:@"com.atproto.server.createSession" handler:nil]; */',
  ].join("\n");

  assertEquals(findRawNsidRegistrationLiterals(source, "Example.m"), []);
});

Deno.test("findRawNsidRegistrationLiterals preserves comment markers in strings", () => {
  const source =
    'NSString *url = @"https://example.test//not-a-comment/*also-not*/"; [dispatcher registerMethod:@"com.atproto.server.getSession" handler:nil];';

  assertEquals(findRawNsidRegistrationLiterals(source, "Example.m"), [
    {
      file: "Example.m",
      line: 1,
      literal: "com.atproto.server.getSession",
    },
  ]);
});
