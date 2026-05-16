/** Mock Twilio SMS verification server for E2E testing. @module mock_twilio */

export interface MockVerificationState {
  code: string;
  createdAt: number;
  verified: boolean;
}

export interface MockState {
  store: Record<string, MockVerificationState>;
  alwaysApproveCodes: string[];
}

/** Client for controlling a mock Twilio server via its __control HTTP API. */
export class MockTwilioServer {
  private baseUrl: string;
  private process: Deno.ChildProcess | null = null;
  private port: number;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
    this.port = new URL(baseUrl).port ? parseInt(new URL(baseUrl).port) : 8081;
  }

  get url(): string {
    return this.baseUrl;
  }

  async waitForHealth(timeoutMs = 10000): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      try {
        const res = await fetch(`${this.baseUrl}/__control/health`);
        const ok = res.ok;
        await res.body?.cancel();
        if (ok) return;
      } catch {
        // server not ready yet
      }
      await new Promise((r) => setTimeout(r, 200));
    }
    throw new Error(`Mock Twilio server not healthy after ${timeoutMs}ms`);
  }

  async setCode(phone: string, code: string): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/setCode`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone, code }),
    });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to set code: ${res.status} ${body}`);
    }
  }

  async setAlwaysApprove(codes: string[]): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/setAlwaysApprove`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ codes }),
    });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to set always-approve: ${res.status} ${body}`);
    }
  }

  async getState(): Promise<MockState> {
    const res = await fetch(`${this.baseUrl}/__control/state`);
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to get state: ${res.status} ${body}`);
    }
    return JSON.parse(body);
  }

  async reset(): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/reset`, { method: "POST" });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to reset: ${res.status} ${body}`);
    }
  }

  async getHealth(): Promise<boolean> {
    try {
      const res = await fetch(`${this.baseUrl}/__control/health`);
      const ok = res.ok;
      await res.body?.cancel();
      return ok;
    } catch {
      return false;
    }
  }

  startProcess(): void {
    if (this.process) return;
    const root = new URL("../../", import.meta.url).pathname;
    const cmd = new Deno.Command("deno", {
      args: [
        "run", "-A",
        "--config", `${root}deno.json`,
        new URL("../../mock-twilio-server.ts", import.meta.url).pathname,
        `--port=${this.port}`,
      ],
      stdout: "null",
      stderr: "inherit",
    });
    this.process = cmd.spawn();
  }

  stopProcess(): void {
    if (this.process) {
      try { this.process.kill("SIGTERM"); } catch { /* ignore */ }
      this.process = null;
    }
  }
}

/** Start a mock Twilio server process and wait for it to become healthy. */
export async function startMockTwilioServer(port = 8081): Promise<MockTwilioServer> {
  const server = new MockTwilioServer(`http://127.0.0.1:${port}`);
  server.startProcess();
  await server.waitForHealth();
  return server;
}

/** Stop a mock Twilio server process. */
export function stopMockTwilioServer(server: MockTwilioServer): void {
  server.stopProcess();
}
