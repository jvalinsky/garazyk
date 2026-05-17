let inst = await Deno.readTextFile("packages/scenario-runner/instrumentation.ts");
inst = inst.replace(
  /async stop\(\): Promise<void> {\n    if \(this\.intervalId\) clearInterval\(this\.intervalId\);\n    await this\.scrape\(\); \/\/ Final scrape\n    return this\.getTimeSeries\(\);\n  }/,
  "async stop(): Promise<Record<string, any>> {\n    if (this.intervalId) clearInterval(this.intervalId);\n    await this.scrape(); // Final scrape\n    return this.getTimeSeries();\n  }"
);
inst = inst.replace(
  /getTimeSeries\(\): any\[\] \{/,
  "getTimeSeries(): Record<string, any> {"
);
inst = inst.replace(
  /async stop\(\): Promise<void> {\n    if \(this\.intervalId\) clearInterval\(this\.intervalId\);\n    await this\.sample\(\);\n    return this\.stats;\n  }/,
  "async stop(): Promise<Record<string, any[]>> {\n    if (this.intervalId) clearInterval(this.intervalId);\n    await this.sample();\n    return this.stats;\n  }"
);
await Deno.writeTextFile("packages/scenario-runner/instrumentation.ts", inst);

let meta = await Deno.readTextFile("packages/scenario-runner/scenario_metadata.ts");
meta = meta.replace(
  /export function getParameters\(scenarioId: string\): Record<string, string> \{/,
  "export function getParameters(scenarioId: string): Record<string, any> {"
);
await Deno.writeTextFile("packages/scenario-runner/scenario_metadata.ts", meta);

let seed = await Deno.readTextFile("packages/atproto-client/seed.ts");
seed = seed.replace(
  /export async function createAccountOrLogin\(\n  client: XrpcClient,\n  handle: string,\n  email: string,\n  password: string,\n\) \{/,
  "export async function createAccountOrLogin(\n  client: XrpcClient,\n  handle: string,\n  email: string,\n  password: string,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function createRecordIdempotent\(\n  client: XrpcClient,\n  repo: string,\n  collection: string,\n  record: Record<string, unknown>,\n  token: string,\n\) \{/,
  "export async function createRecordIdempotent(\n  client: XrpcClient,\n  repo: string,\n  collection: string,\n  record: Record<string, unknown>,\n  token: string,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function chatXrpcGet\(\n  context: ChatServiceContext,\n  accessJwt: string,\n  method: string,\n  params\?: Record<string, unknown>,\n\) \{/,
  "export async function chatXrpcGet(\n  context: ChatServiceContext,\n  accessJwt: string,\n  method: string,\n  params?: Record<string, unknown>,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function chatXrpcPost\(\n  context: ChatServiceContext,\n  accessJwt: string,\n  method: string,\n  body\?: Record<string, unknown>,\n\) \{/,
  "export async function chatXrpcPost(\n  context: ChatServiceContext,\n  accessJwt: string,\n  method: string,\n  body?: Record<string, unknown>,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function chatGetConvoForMembers\(\n  context: ChatServiceContext,\n  accessJwt: string,\n  memberDids: string\[\],\n\) \{/,
  "export async function chatGetConvoForMembers(\n  context: ChatServiceContext,\n  accessJwt: string,\n  memberDids: string[],\n): Promise<any> {"
);
seed = seed.replace(
  /export async function chatSendMessage\(\n  context: ChatServiceContext,\n  accessJwt: string,\n  convoId: string,\n  text: string,\n\) \{/,
  "export async function chatSendMessage(\n  context: ChatServiceContext,\n  accessJwt: string,\n  convoId: string,\n  text: string,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function chatListConvos\(\n  context: ChatServiceContext,\n  accessJwt: string,\n  limit = 20,\n\) \{/,
  "export async function chatListConvos(\n  context: ChatServiceContext,\n  accessJwt: string,\n  limit = 20,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function chatGetMessages\(\n  context: ChatServiceContext,\n  accessJwt: string,\n  convoId: string,\n  limit = 50,\n\) \{/,
  "export async function chatGetMessages(\n  context: ChatServiceContext,\n  accessJwt: string,\n  convoId: string,\n  limit = 50,\n): Promise<any> {"
);
seed = seed.replace(
  /export async function getConvoForMembers\(client: XrpcClient, jwt: string, memberDids: string\[\]\) \{/,
  "export async function getConvoForMembers(client: XrpcClient, jwt: string, memberDids: string[]): Promise<any> {"
);
seed = seed.replace(
  /export async function sendMessage\(client: XrpcClient, jwt: string, convoId: string, text: string\) \{/,
  "export async function sendMessage(client: XrpcClient, jwt: string, convoId: string, text: string): Promise<any> {"
);
seed = seed.replace(
  /export async function listConvos\(client: XrpcClient, jwt: string, limit = 20\) \{/,
  "export async function listConvos(client: XrpcClient, jwt: string, limit = 20): Promise<any> {"
);
seed = seed.replace(
  /export async function getMessages\(client: XrpcClient, jwt: string, convoId: string, limit = 50\) \{/,
  "export async function getMessages(client: XrpcClient, jwt: string, convoId: string, limit = 50): Promise<any> {"
);
await Deno.writeTextFile("packages/atproto-client/seed.ts", seed);

console.log("Done");