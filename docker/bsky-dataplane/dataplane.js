// Standalone dataplane entry point for schema initialization.
// Runs Kysely migrations against the bsky schema, then starts the gRPC DataPlane server.
// This is the same pattern used by Blacksky (outof-coffee/atproto) for running
// rsky-wintermute alongside the reference dataplane.

const { Database } = require("@atproto/bsky/dist/data-plane/server/db");
const { DataPlaneServer } = require("@atproto/bsky/dist/data-plane/server");

const main = async () => {
  const dbUrl = process.env.BSKY_DB_POSTGRES_URL;
  const dbSchema = process.env.BSKY_DB_POSTGRES_SCHEMA || "bsky";
  const port = parseInt(process.env.BSKY_DATAPLANE_PORT || "2585", 10);
  const plcUrl = process.env.BSKY_DID_PLC_URL || "https://plc.directory";

  if (!dbUrl) {
    console.error("BSKY_DB_POSTGRES_URL is required");
    process.exit(1);
  }

  console.log("Starting DataPlane server...");
  console.log("Database URL:", dbUrl.replace(/:[^:@]+@/, ":****@"));
  console.log("Schema:", dbSchema);
  console.log("Port:", port);

  const db = new Database({
    url: dbUrl,
    schema: dbSchema,
    poolSize: 10,
  });

  // Run migrations — creates the bsky schema and all tables
  console.log("Running database migrations...");
  await db.migrateToLatestOrThrow();
  console.log("Migrations complete");

  const server = await DataPlaneServer.create({
    db,
    port,
    plcUrl,
  });
  console.log("DataPlane server listening on port", port);

  const shutdown = async () => {
    console.log("Shutting down DataPlane server...");
    await server.destroy();
    await db.close();
    process.exit(0);
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
};

main().catch((err) => {
  console.error("DataPlane server failed to start:", err);
  process.exit(1);
});
