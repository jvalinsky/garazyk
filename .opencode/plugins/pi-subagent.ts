import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"
import { join } from "path"
import { homedir } from "os"
import { mkdirSync } from "fs"

interface PiConfig {
  modelSource: "pi" | "opencode"
  model?: string
  thinkingLevel?: string
  timeout: number
}

class PiRpcClient {
  private proc: import("bun").Subprocess | null = null
  private lineBuffer = ""
  private accumulatedText = ""
  private pendingTask: {
    resolve: (text: string) => void
    reject: (err: Error) => void
    timer: ReturnType<typeof setTimeout>
  } | null = null
  private config: PiConfig
  private workdir: string
  running = false

  constructor(workdir: string, config: PiConfig) {
    this.workdir = workdir
    this.config = config
  }

  async start(): Promise<void> {
    const args = ["--mode", "rpc", "--no-session"]
    const env = { ...process.env } as Record<string, string>

    if (this.config.modelSource === "opencode") {
      await this.setupOpenCodeProvider(env)
    }

    if (this.config.model) args.push("--model", this.config.model)
    if (this.config.thinkingLevel) args.push("--thinking", this.config.thinkingLevel)

    try {
      this.proc = Bun.spawn(["pi", ...args], {
        cwd: this.workdir,
        env,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "inherit",
      })
      this.running = true
      this.readLoop().catch(() => {
        this.running = false
      })
    } catch (e: any) {
      console.error("[pi-subagent] Failed to start pi:", e.message)
      this.running = false
    }
  }

  private async setupOpenCodeProvider(env: Record<string, string>): Promise<void> {
    try {
      const authPath = join(homedir(), ".local/share/opencode/auth.json")
      const file = Bun.file(authPath)
      if (!(await file.exists())) {
        console.warn("[pi-subagent] OpenCode auth file not found at", authPath)
        return
      }

      const auth = await file.json()
      const providers: Record<string, any> = {}

      const goKey = auth["opencode-go"] ?? auth["go"] ?? null
      if (goKey) {
        providers["opencode-go"] = {
          baseUrl: "https://opencode.ai/zen/go/v1",
          api: "openai-completions",
          apiKey: goKey,
          models: [
            { id: "deepseek-v4-pro", name: "DeepSeek V4 Pro", contextWindow: 128000, maxTokens: 8192, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } },
            { id: "deepseek-v4-flash", name: "DeepSeek V4 Flash", contextWindow: 128000, maxTokens: 8192, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } },
            { id: "kimi-k2.6", name: "Kimi K2.6", contextWindow: 128000, maxTokens: 8192, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } },
            { id: "qwen3.6-plus", name: "Qwen 3.6 Plus", contextWindow: 128000, maxTokens: 8192, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } },
          ],
        }
      }

      const zenKey = auth["opencode-zen"] ?? auth["zen"] ?? null
      if (zenKey) {
        providers["opencode-zen"] = {
          baseUrl: "https://opencode.ai/zen/v1",
          api: "openai-completions",
          apiKey: zenKey,
          models: [
            { id: "claude-opus-4.7", name: "Claude Opus 4.7", contextWindow: 200000, maxTokens: 16384, cost: { input: 3.0, output: 15.0, cacheRead: 0.3, cacheWrite: 3.75 } },
            { id: "gpt-5.2", name: "GPT 5.2", contextWindow: 256000, maxTokens: 16384, cost: { input: 10.0, output: 40.0, cacheRead: 1.0, cacheWrite: 5.0 } },
          ],
        }
      }

      if (Object.keys(providers).length === 0) {
        console.warn("[pi-subagent] No OpenCode provider keys found in auth file")
        return
      }

      const tmpDir = join(process.env.TMPDIR || "/tmp", `pi-opencode-${Date.now()}`)
      mkdirSync(tmpDir, { recursive: true })
      await Bun.write(join(tmpDir, "models.json"), JSON.stringify({ providers }, null, 2))
      env.PI_AGENT_DIR = tmpDir
    } catch (e: any) {
      console.warn("[pi-subagent] Could not configure OpenCode provider:", e.message)
    }
  }

  private async readLoop(): Promise<void> {
    const reader = this.proc!.stdout.getReader()
    const decoder = new TextDecoder()

    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        this.lineBuffer += decoder.decode(value, { stream: true })

        while (true) {
          const idx = this.lineBuffer.indexOf("\n")
          if (idx === -1) break
          const line = this.lineBuffer.slice(0, idx).replace(/\r$/, "")
          this.lineBuffer = this.lineBuffer.slice(idx + 1)
          if (line.trim()) this.handleLine(line.trim())
        }
      }
    } catch {
      /* stream closed */
    }

    this.running = false
    this.failTask(new Error("Pi process exited unexpectedly"))
  }

  private handleLine(line: string): void {
    let msg: any
    try {
      msg = JSON.parse(line)
    } catch {
      return
    }

    if (msg.type === "response") {
      if (msg.command === "prompt" && !msg.success) {
        this.failTask(new Error(msg.error || "Pi rejected the prompt"))
      }
      if (msg.command === "abort" && msg.success) {
        this.failTask(new Error("Task aborted"))
      }
      return
    }

    if (msg.type === "message_update" && msg.assistantMessageEvent?.type === "text_delta") {
      this.accumulatedText += msg.assistantMessageEvent.delta
    }

    if (msg.type === "agent_end") {
      const text = this.accumulatedText
      this.accumulatedText = ""
      this.resolveTask(text)
    }

    if (msg.type === "message_end" && msg.message?.role === "assistant" && msg.message?.stopReason === "error") {
      this.failTask(new Error("Pi agent encountered an error"))
    }
  }

  async sendTask(task: string): Promise<string> {
    if (!this.running) throw new Error("Pi process is not running")
    if (this.pendingTask) throw new Error("Pi is already processing a task")

    this.accumulatedText = ""

    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.failTask(new Error(`Task timed out (${this.config.timeout / 1000}s)`))
      }, this.config.timeout)

      this.pendingTask = { resolve, reject, timer }
      const writer = this.proc!.stdin.getWriter()
      writer.write(JSON.stringify({ type: "prompt", message: task }) + "\n")
    })
  }

  private resolveTask(text: string): void {
    if (this.pendingTask) {
      clearTimeout(this.pendingTask.timer)
      this.pendingTask.resolve(text || "(no output)")
      this.pendingTask = null
    }
    this.accumulatedText = ""
  }

  private failTask(err: Error): void {
    if (this.pendingTask) {
      clearTimeout(this.pendingTask.timer)
      this.pendingTask.reject(err)
      this.pendingTask = null
    }
    this.accumulatedText = ""
  }

  abort(): void {
    try {
      this.proc?.stdin.getWriter().write(JSON.stringify({ type: "abort" }) + "\n")
    } catch {}
  }

  kill(): void {
    this.failTask(new Error("Pi process terminated"))
    this.proc?.kill(9)
    this.proc = null
    this.running = false
  }
}

export const PiSubagentPlugin: Plugin = async (ctx, options) => {
  const opts = (options ?? {}) as Record<string, any>
  const config: PiConfig = {
    modelSource: opts.modelSource ?? process.env.PI_MODEL_SOURCE ?? "pi",
    model: opts.model ?? process.env.PI_MODEL ?? undefined,
    thinkingLevel: opts.thinkingLevel ?? process.env.PI_THINKING_LEVEL ?? undefined,
    timeout: parseInt(opts.timeout ?? process.env.PI_TIMEOUT ?? "300000", 10),
  }

  const client = new PiRpcClient(ctx.worktree || ctx.directory, config)
  const startPromise = client.start()

  return {
    tool: {
      pi: tool({
        description:
          "Delegate a coding task to Pi, a separate AI agent running independently. " +
          "Pi has its own model, tools (bash, read, write, edit), and full context. " +
          "Use for complex multi-file work, research, parallel exploration, or when you want a fresh perspective.",
        args: {
          task: tool.schema
            .string()
            .describe("The full task description for Pi to execute"),
        },
        async execute(args) {
          await startPromise
          if (!client.running) {
            return "[Pi unavailable] Install pi: npm install -g @earendil-works/pi-coding-agent"
          }
          try {
            return await client.sendTask(args.task)
          } catch (err: any) {
            return `[Pi error] ${err.message}`
          }
        },
      }),
    },
  }
}
