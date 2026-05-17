/** Mock Twilio SMS verification server for E2E testing. @module mock_twilio */

/** State for a single verification code tracked by the mock server. */
export interface MockVerificationState {
  /** Verification code stored for the phone number. */
  code: string;
  /** Unix timestamp in milliseconds when the code was created. */
  createdAt: number;
  /** Whether the code has been verified. */
  verified: boolean;
}

/** Serializable snapshot of the mock Twilio server state. */
export interface MockState {
  /** Verification records keyed by phone number. */
  store: Record<string, MockVerificationState>;
  /** Codes that should be approved without verification. */
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

  /** Returns the base URL for the mock Twilio server. */
  get url(): string {
    return this.baseUrl;
  }

  /** Waits until the server responds successfully to the health check. @param timeoutMs - Maximum time to wait in milliseconds. @throws If the server does not become healthy before the timeout expires. */
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

  /** Sets the verification code for a phone number. @param phone - Phone number to update. @param code - Verification code to store. @returns A promise that resolves when the code is updated. @throws If the control endpoint returns a non-OK response. */
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

  /** Marks verification codes that should always be approved. @param codes - Codes to approve without verification. @returns A promise that resolves when the codes are updated. @throws If the control endpoint returns a non-OK response. */
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

  /** Returns the current server state snapshot. @returns A promise that resolves to the current mock server state. @throws If the control endpoint returns a non-OK response. */
  async getState(): Promise<MockState> {
    const res = await fetch(`${this.baseUrl}/__control/state`);
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to get state: ${res.status} ${body}`);
    }
    return JSON.parse(body);
  }

  /** Resets the mock server state. @returns A promise that resolves when the state has been cleared. @throws If the control endpoint returns a non-OK response. */
  async reset(): Promise<void> {
    const res = await fetch(`${this.baseUrl}/__control/reset`, { method: "POST" });
    const body = await res.text();
    if (!res.ok) {
      throw new Error(`Failed to reset: ${res.status} ${body}`);
    }
  }

  /** Checks whether the server responds successfully to the health endpoint. @returns A promise that resolves to true when the server is healthy, otherwise false. */
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

  /** Starts the mock Twilio server process if it is not already running. @returns Nothing. @throws If spawning the process fails. */
  startProcess(): void {
    if (this.process) return;
    const root = new URL("../../", import.meta.url).pathname;
    const cmd = new Deno.Command("deno", {
      args: [
        "run",
        "-A",
        "--config",
        `${root}deno.json`,
        new URL("../../scripts/mock-twilio-server.ts", import.meta.url).pathname,
        `--port=${this.port}`,
      ],
      stdout: "null",
      stderr: "inherit",
    });
    this.process = cmd.spawn();
  }

  /** Stops the mock Twilio server process if it is running. @returns Nothing. */
  stopProcess(): void {
    if (this.process) {
      try {
        this.process.kill("SIGTERM");
      } catch { /* ignore */ }
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
