let schema = await Deno.readTextFile("packages/atproto-topology/topology_schema.ts");

// Import ZodTypeAny if not present
if (!schema.includes("ZodTypeAny")) {
  schema = schema.replace('import { z } from "zod";', 'import { z, type ZodTypeAny } from "zod";');
}

// Add : ZodTypeAny to schemas
const schemaRegex = /(const\s+[a-zA-Z0-9_]+Schema)\s*=\s*(z\.)/g;
schema = schema.replace(schemaRegex, "$1: ZodTypeAny = $2");

// Also replace exported schemas
const exportSchemaRegex = /(export\s+const\s+[a-zA-Z0-9_]+Schema)\s*=\s*(z\.)/g;
schema = schema.replace(exportSchemaRegex, "$1: ZodTypeAny = $2");

await Deno.writeTextFile("packages/atproto-topology/topology_schema.ts", schema);
console.log("Fixed topology_schema.ts types");
