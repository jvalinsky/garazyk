import { XrpcClient } from "./scripts/lib/deno/client.ts";

const PDS_URL = "http://localhost:2583";
const client = new XrpcClient(PDS_URL);

console.log("Testing deleteSession with Refresh JWT...");

try {
  // 1. Login
  const session = await client.raw.post("com.atproto.server.createSession", {
    identifier: "luna.test",
    password: "password"
  });
  console.log("Logged in.");

  const refreshJwt = session.refreshJwt;
  const accessJwt = session.accessJwt;

  // 2. Try deleteSession with Refresh JWT
  console.log("Attempting deleteSession with Refresh JWT...");
  try {
    await client.raw.post("com.atproto.server.deleteSession", {}, refreshJwt);
    console.log("SUCCESS: deleteSession accepted Refresh JWT.");
  } catch (e) {
    console.error("FAILURE: deleteSession rejected Refresh JWT:", e.message);
  }

  // 3. Login again
  const session2 = await client.raw.post("com.atproto.server.createSession", {
    identifier: "luna.test",
    password: "password"
  });
  console.log("Logged in again.");

  // 4. Try deleteSession with Access JWT
  console.log("Attempting deleteSession with Access JWT...");
  try {
    await client.raw.post("com.atproto.server.deleteSession", {}, session2.accessJwt);
    console.log("SUCCESS: deleteSession accepted Access JWT.");
  } catch (e) {
    console.error("FAILURE: deleteSession rejected Access JWT:", e.message);
  }

} catch (e) {
  console.error("Unexpected error:", e);
}
