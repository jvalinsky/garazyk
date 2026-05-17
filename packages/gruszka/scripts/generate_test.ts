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
