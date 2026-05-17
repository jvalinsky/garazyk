import { assertEquals, assertStringIncludes } from "@std/assert";
import { redactDiagnosticText } from "./diagnostics.ts";

Deno.test("redactDiagnosticText preserves JSON strings while redacting secrets", () => {
  const input = JSON.stringify({
    accessJwt: "abc.def.ghi",
    password: "secret-password",
    nested: { token: "token-value" },
  });

  const redacted = redactDiagnosticText(input);
  const parsed = JSON.parse(redacted);
  assertEquals(parsed.accessJwt, "[REDACTED]");
  assertEquals(parsed.password, "[REDACTED]");
  assertEquals(parsed.nested.token, "[REDACTED]");
});

Deno.test("redactDiagnosticText redacts bearer tokens and env-style secrets", () => {
  const redacted = redactDiagnosticText(
    "Authorization: Bearer abc.def.ghi\nMASTER_SECRET=top-secret\n",
  );
  assertStringIncludes(redacted, "Authorization: Bearer [REDACTED]");
  assertStringIncludes(redacted, "MASTER_SECRET=[REDACTED]");
});
