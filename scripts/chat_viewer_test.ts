import { assert, assertEquals, assertMatch } from "@std/assert";
import {
  ansiColor,
  padLeft,
  padRight,
  printConversation,
  stripAnsi,
  wrapText,
} from "./chat_viewer.ts";

function withColumns<T>(columns: string, fn: () => T): T {
  const previous = Deno.env.get("COLUMNS");
  Deno.env.set("COLUMNS", columns);
  try {
    return fn();
  } finally {
    if (previous === undefined) {
      Deno.env.delete("COLUMNS");
    } else {
      Deno.env.set("COLUMNS", previous);
    }
  }
}

Deno.test("stripAnsi removes SGR escape sequences", () => {
  assertEquals(stripAnsi(`${ansiColor("Alice", 1, 92)} plain`), "Alice plain");
});

Deno.test("padding uses visible width for ANSI-colored strings", () => {
  const colored = ansiColor("A", 1, 92);

  assertEquals(stripAnsi(padRight(colored, 4)), "A   ");
  assertEquals(stripAnsi(padLeft(colored, 4)), "   A");
});

Deno.test("wrapText breaks text at word boundaries", () => {
  assertEquals(wrapText("alpha beta gamma", 10), ["alpha beta", "gamma"]);
  assertEquals(wrapText("", 10), [""]);
});

Deno.test("printConversation renders deterministic chronological output", () => {
  const lines: string[] = [];
  const originalLog = console.log;
  console.log = (...data: unknown[]): void => {
    lines.push(data.map(String).join(" "));
  };

  try {
    withColumns("48", () => {
      printConversation(
        {
          id: "convo-1",
          members: [
            { did: "did:plc:self", handle: "alice.test" },
            { did: "did:plc:bob", handle: "bob.test" },
          ],
          unreadCount: 2,
        },
        0,
        1,
        "did:plc:self",
        [
          {
            id: "new",
            sender: { did: "did:plc:self", handle: "alice.test" },
            sentAt: "not-a-date-new",
            text: "newer reply",
          },
          {
            id: "old",
            sender: { did: "did:plc:bob", handle: "bob.test" },
            sentAt: "not-a-date-old",
            text: "older hello",
          },
        ],
      );
    });
  } finally {
    console.log = originalLog;
  }

  const rendered = stripAnsi(lines.join("\n"));
  assertMatch(rendered, /Convo 1\/1/);
  assertMatch(rendered, /Members: alice\.test, bob\.test\s+2 unread/);
  assertMatch(rendered, /2 messages/);
  assert(rendered.indexOf("older hello") < rendered.indexOf("newer reply"));
});
