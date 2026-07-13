import { assert, assertEquals, assertRejects } from "@std/assert";
import { dirname, fromFileUrl, join } from "@std/path";
import { generateLexicons } from "./generate.ts";

const SCRIPT_DIR = dirname(fromFileUrl(import.meta.url));
const REPO_ROOT = dirname(dirname(dirname(SCRIPT_DIR)));

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

  assertEquals(result, { lexiconCount: 1, endpointCount: 1, outFile });
  assert(source.includes('"app.bsky.actor.getProfile"'));
  assert(
    source.includes(
      '"getProfile"(params?: QueryParams<"app.bsky.actor.getProfile">',
    ),
  );
  assert(source.includes('outputEncoding: "application/json";'));
  assert(source.includes("export const LEXICON_METHOD_OUTPUT_ENCODINGS"));
});

Deno.test("generateLexicons preserves binary input and output encodings", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "com", "example", "getBlob.json"),
    defsDoc("com.example.getBlob", {
      main: {
        type: "query",
        output: {
          encoding: "application/vnd.ipld.car",
        },
      },
    }),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "uploadBlob.json"),
    defsDoc("com.example.uploadBlob", {
      main: {
        type: "procedure",
        input: {
          encoding: "*/*",
        },
        output: {
          encoding: "application/json",
          schema: {
            type: "object",
            required: ["ok"],
            properties: {
              ok: { type: "boolean" },
            },
          },
        },
      },
    }),
  );

  await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assert(source.includes('outputEncoding: "application/vnd.ipld.car";'));
  assert(source.includes("output: BinaryXrpcResponse;"));
  assert(source.includes('inputEncoding: "*/*";'));
  assert(source.includes("input: Uint8Array;"));
  assert(source.includes('"com.example.getBlob": "application/vnd.ipld.car"'));
  assert(source.includes('"com.example.uploadBlob": "*/*"'));
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
  await writeJson(
    join(lexiconsDir, "app", "bsky", "actor", "getProfile.json"),
    lexiconDoc("app.bsky.actor.getProfile"),
  );

  await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assert(source.includes('type: "record";'));
  assert(
    !source.includes(
      '"app.bsky.actor.profile": {\n    type: "query";',
    ),
  );
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

Deno.test("generateLexicons refuses to overwrite output when no lexicons exist", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");
  await Deno.mkdir(lexiconsDir);
  await Deno.writeTextFile(outFile, "preserve existing output\n");

  await assertRejects(
    () => generateLexicons({ lexiconsDir, outFile }),
    Error,
    "No lexicon documents found",
  );

  assertEquals(
    await Deno.readTextFile(outFile),
    "preserve existing output\n",
  );
});

Deno.test("generateLexicons refuses to overwrite output when no endpoints exist", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");
  await Deno.writeTextFile(outFile, "preserve existing output\n");
  await writeJson(
    join(lexiconsDir, "com", "example", "record.json"),
    lexiconDoc("com.example.record", "record"),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "defs.json"),
    defsDoc("com.example.defs", {
      main: { type: "object", properties: {} },
    }),
  );

  await assertRejects(
    () => generateLexicons({ lexiconsDir, outFile }),
    Error,
    "No endpoint definitions found",
  );

  assertEquals(
    await Deno.readTextFile(outFile),
    "preserve existing output\n",
  );
});

Deno.test("generateLexicons classifies every supported main definition kind", async () => {
  const tempDir = await Deno.makeTempDir();
  const lexiconsDir = join(tempDir, "lexicons");
  const outFile = join(tempDir, "lexicons.ts");

  await writeJson(
    join(lexiconsDir, "com", "example", "record.json"),
    lexiconDoc("com.example.record", "record"),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "query.json"),
    lexiconDoc("com.example.query"),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "procedure.json"),
    defsDoc("com.example.procedure", {
      main: { type: "procedure" },
    }),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "subscription.json"),
    defsDoc("com.example.subscription", {
      main: { type: "subscription" },
    }),
  );
  await writeJson(
    join(lexiconsDir, "com", "example", "object.json"),
    defsDoc("com.example.object", {
      main: { type: "object", properties: {} },
    }),
  );

  const result = await generateLexicons({ lexiconsDir, outFile });
  const source = await Deno.readTextFile(outFile);

  assertEquals(result, { lexiconCount: 5, endpointCount: 3, outFile });
  assert(source.includes("export const LEXICON_DEFINITION_KINDS"));
  assert(source.includes('"com.example.record": "record",'));
  assert(source.includes('"com.example.query": "query",'));
  assert(source.includes('"com.example.procedure": "procedure",'));
  assert(source.includes('"com.example.subscription": "subscription",'));
  assert(source.includes('"com.example.object": "other",'));
  assert(
    !source.includes('"com.example.subscription": {\n    type: "procedure";'),
  );
});

Deno.test("generateLexicons has deterministic output independent of discovery order", async () => {
  const tempDir = await Deno.makeTempDir();
  const firstRoot = join(tempDir, "first");
  const secondRoot = join(tempDir, "second");
  const firstOutFile = join(tempDir, "first.ts");
  const secondOutFile = join(tempDir, "second.ts");
  const query = lexiconDoc("com.example.query");
  const procedure = defsDoc("com.example.procedure", {
    main: { type: "procedure" },
  });

  await writeJson(
    join(firstRoot, "com", "example", "procedure.json"),
    procedure,
  );
  await writeJson(join(firstRoot, "com", "example", "query.json"), query);
  await writeJson(join(secondRoot, "com", "example", "query.json"), query);
  await writeJson(
    join(secondRoot, "com", "example", "procedure.json"),
    procedure,
  );

  await generateLexicons({ lexiconsDir: firstRoot, outFile: firstOutFile });
  await generateLexicons({ lexiconsDir: secondRoot, outFile: secondOutFile });

  assertEquals(
    await Deno.readTextFile(firstOutFile),
    await Deno.readTextFile(secondOutFile),
  );
});

Deno.test("generateLexicons default output matches the checked-in artifact", async () => {
  const tempDir = await Deno.makeTempDir();
  const outFile = join(tempDir, "lexicons.ts");

  const result = await generateLexicons({ outFile });

  assert(result.lexiconCount > 0);
  assert(result.endpointCount > 0);
  assertEquals(
    await Deno.readTextFile(outFile),
    await Deno.readTextFile(
      join(REPO_ROOT, "packages", "gruszka", "lexicons.ts"),
    ),
  );
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
