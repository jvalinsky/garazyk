import { XrpcClient } from "@garazyk/gruszka";
import { createCharacterRegistry, ScenarioResult, timedCall } from "@garazyk/hamownia";

export async function runSmoke(pdsUrl: string): Promise<ScenarioResult> {
  const result = new ScenarioResult("Account + Post Creation");
  result.start();

  const client = new XrpcClient(pdsUrl);
  const chars = createCharacterRegistry(pdsUrl);
  const luna = chars.getCharacter("luna");

  await timedCall(result, "Server health check", async () => {
    const res = await fetch(`${pdsUrl}/xrpc/com.atproto.server.describeServer`);
    if (!res.ok) throw new Error(`Server not healthy: ${res.status}`);
  });

  if (result.failed > 0) { result.finish(); return result; }

  const session = await timedCall(
    result, `Create account: ${luna.name}`,
    async () => {
      try {
        const res = await client.agent.createAccount({
          handle: luna.handle,
          email: luna.email,
          password: luna.password,
        });
        return res.data;
      } catch (e: any) {
        if (e?.status === 400 && String(e.body?.error ?? "").includes("already exists")) {
          const res = await client.agent.login({
            identifier: luna.handle,
            password: luna.password,
          });
          return res.data;
        }
        throw e;
      }
    },
    (s) => `did=${s.did}`,
  );

  if (!session) { result.finish(); return result; }
  luna.did = session.did;
  luna.accessJwt = session.accessJwt;

  let postUri = "";
  await timedCall(
    result, "Create a post",
    async () => {
      const res = await client.agent.com.atproto.repo.createRecord({
        repo: luna.did,
        collection: "app.bsky.feed.post",
        record: {
          $type: "app.bsky.feed.post",
          text: "Hello from Garazyk scenario!",
          createdAt: new Date().toISOString(),
        },
      });
      postUri = res.data.uri;
      return res.data;
    },
    (r) => `uri=${r.uri}`,
  );

  if (postUri) {
    await timedCall(
      result, "Read post back",
      async () => {
        const rkey = postUri.split("/").pop()!;
        const res = await client.agent.com.atproto.repo.getRecord({
          repo: luna.did,
          collection: "app.bsky.feed.post",
          rkey,
        });
        if (!res.data) throw new Error("Post not found");
        return res.data;
      },
      (r) => `cid=${r.cid}`,
    );
  }

  result.finish();
  return result;
}


