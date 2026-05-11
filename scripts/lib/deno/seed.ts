import { BskyAgent } from "@atproto/api";

export const DEFAULT_ACCOUNTS = [
  { handle: "alice.test", email: "alice@test.com", password: "password123" },
  { handle: "bob.test", email: "bob@test.com", password: "password123" },
  { handle: "carol.test", email: "carol@test.com", password: "password123" },
];

export async function createAccountOrLogin(agent: BskyAgent, handle: string, email: string, password: string) {
  try {
    await agent.createAccount({ handle, email, password });
    return agent.session;
  } catch (e: any) {
    if (e.message && e.message.toLowerCase().includes("already exists")) {
       await agent.login({ identifier: handle, password });
       return agent.session;
    } else {
      throw e;
    }
  }
}
