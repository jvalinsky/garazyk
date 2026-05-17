import { assert, assertEquals, assertRejects } from "@std/assert";
import { dirname, join } from "@std/path";
import { generateLexicons } from "./generate.ts";

function lexiconDoc(id: string, type: "query" | "record" = "query") {
  return {
    lexicon: 1,
    id,
    defs: {
      main: type === "query"
        ? {
          type: "query",
          parameters: {
            type: "params",
            properties: {
              actor: { type: "string" },
            },
            required: ["actor"],
          },
          output: {
            encoding: "application/json",
            schema: {
              type: "object",
              properties: {
                did: { type: "string" },
              },
              required: ["did"],
            },
          },
        }
        : {
          type: "record",
          record: {
            type: "object",
            properties: {
              text: { type: "string" },
            },
            required: ["text"],
          },
        },
    },
  };
}

function defsDoc(id: string, defs: Record<string, unknown>) {
  return { lexicon: 1, id, defs };
}

async function writeJson(path: string, value: unknown): Promise<void> {
  await Deno.mkdir(dirname(path), { recursive: true });
  await Deno.writeTextFile(path, JSON.stringify(value, null, 2));
}

Deno.test("generateLexicons writes to the requested package output path", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "packages", "gruszka", "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "app", "bsky", "actor", "getProfile.json"),
    lexiconDoc("app.bsky.actor.getProfile"),
  );

  const result = await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assertEquals(result, { lexiconCount: 1, outFile });
  assert(source.includes('"app.bsky.actor.getProfile"'));
  assert(
    source.includes(
      '"getProfile"(params?: QueryParams<"app.bsky.actor.getProfile">',
    ),
  );
});

Deno.test("generateLexicons selects the canonical path when duplicate ids exist", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "app", "bsky", "actor", "profile.json"),
    lexiconDoc("app.bsky.actor.profile", "record"),
  );
  await writeJson(
    join(lexiconsDir, "examples", "statusphere", "profile.json"),
    lexiconDoc("app.bsky.actor.profile", "query"),
  );

  await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assert(source.includes('type: "record";'));
  assert(!source.includes('type: "query";'));
});

Deno.test("generateLexicons rejects ambiguous duplicate ids", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "one", "profile.json"),
    lexiconDoc("app.bsky.actor.profile", "record"),
  );
  await writeJson(
    join(lexiconsDir, "two", "profile.json"),
    lexiconDoc("app.bsky.actor.profile", "query"),
  );

  const error = await assertRejects(
    () => generateLexicons({ lexiconsDir, outFile }),
    Error,
    "Duplicate lexicon ids without a unique canonical path",
  );

  assert(error.message.includes("app.bsky.actor.profile"));
  assert(error.message.includes("app/bsky/actor/profile.json"));
});

Deno.test("generateLexicons resolves local and external refs", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "com", "example", "defs.json"),
    defsDoc("com.example.defs", {
      main: {
        type: "object",
        required: ["id"],
        properties: {
          id: { type: "string" },
        },
      },
      local: {
        type: "object",
        required: ["name"],
        properties: {
          name: { type: "string" },
        },
      },
    }),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "getThing.json"),
    defsDoc("com.example.getThing", {
      main: {
        type: "query",
        output: {
          encoding: "application/json",
          schema: {
            type: "object",
            required: ["thing", "local"],
            properties: {
              thing: { type: "ref", ref: "com.example.defs" },
              local: { type: "ref", ref: "#local" },
            },
          },
        },
      },
      local: {
        type: "object",
        required: ["ok"],
        properties: {
          ok: { type: "boolean" },
        },
      },
    }),
  );

  await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assert(source.includes("export interface LexiconDefs"));
  assert(source.includes('"thing": LexiconDefs["com.example.defs"]["main"];'));
  assert(
    source.includes('"local": LexiconDefs["com.example.getThing"]["local"];'),
  );
});

Deno.test("generateLexicons resolves unions and reports unresolved refs explicitly", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "com", "example", "union.json"),
    defsDoc("com.example.union", {
      main: {
        type: "query",
        output: {
          encoding: "application/json",
          schema: {
            type: "object",
            properties: {
              open: {
                type: "union",
                refs: ["#known", "com.example.missing#main"],
              },
              closed: {
                type: "union",
                refs: ["#known"],
                closed: true,
              },
            },
          },
        },
      },
      known: {
        type: "object",
        properties: {
          value: { type: "string" },
        },
      },
    }),
  );

  await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assert(
    source.includes(
      '"open"?: LexiconDefs["com.example.union"]["known"] | any /* unresolved ref: com.example.missing#main */ | Record<string, any>;',
    ),
  );
  assert(
    source.includes(
      '"closed"?: LexiconDefs["com.example.union"]["known"];',
    ),
  );
});
