#!/usr/bin/env node
import { TerminalSessionManager } from "../terminal_session.mjs";
import { AsciicastRecorder } from "../recording.mjs";
import path from "node:path";
import fs from "node:fs";

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function renderPreview(session, cols, rows) {
  try {
    const buf = session.buffer;
    const lines = [];
    for (let y = 0; y < Math.min(rows, 5); y += 1) {
      const line = [];
      for (let x = 0; x < Math.min(cols, 120); x += 1) {
        const cell = buf.getCell(x, y);
        line.push(cell && cell.char !== " " ? cell.char : " ");
      }
      lines.push(line.join(""));
    }
    return lines.join(" | ");
  } catch { return "(preview unavailable)"; }
}

function showProgress(current, total) {
  const barWidth = 20;
  const done = Math.round((current / total) * barWidth);
  const bar = "\u2588".repeat(done) + "\u2591".repeat(barWidth - done);
  const pct = total > 0 ? Math.round((current / total) * 100) : 0;
  process.stderr.write("\r  " + bar + " " + pct + "% (" + current + "/" + total + ")");
}

function showPreview(session, cols, rows, title) {
  const preview = renderPreview(session, cols, rows);
  process.stderr.write("\r  [" + (title || "").substring(0, 20) + "] " + preview + "\n");
}

async function main() {
  const input = await readStdin();
  const { command, args, cols, rows, actions, title, outputDir, env, preview } = input;

  if (!command) {
    throw new Error("'command' is required");
  }

  const manager = new TerminalSessionManager({
    env: { ...process.env, ...(env || {}) },
  });

  const session = await manager.create({
    command,
    args: args || [],
    cols: cols || 80,
    rows: rows || 24,
    title: title || undefined,
  });
  await session.settle(100);

  const outDir = outputDir
    ? path.resolve(outputDir)
    : path.join(process.cwd(), "scripts", "scenarios", "reports", "pty-capture", `capture-${Date.now()}`);

  const recorder = new AsciicastRecorder({
    outputDir: outDir,
    cols: session.cols,
    rows: session.rows,
    title: title || path.basename(command),
    semanticOverlay: true,
    recordInput: false,
    command: [command, ...(args || [])].join(" "),
  });
  session.attachRecording(recorder);
  if (input.framerate !== 0) {
    const fps = Math.max(1, Math.min(60, input.framerate || 20));
    session.startScreenCapture(1000 / fps);
  }

  const showLive = preview !== false;
  if (showLive) {
    process.stderr.write("\n  \u001b[1m" + (title || path.basename(command)) + "\u001b[22m\n");
    process.stderr.write("  " + cols + "\u00D7" + rows + " terminal\n");
  }

  const steps = actions || [];
  for (let si = 0; si < steps.length; si += 1) {
    const step = steps[si];
    if (step.delay) await new Promise(r => setTimeout(r, step.delay));

    if (step.action === "press_key") {
      if (showLive) process.stderr.write("\r  \u2192 key: \u001b[36m" + step.value + "\u001b[39m");
      await session.pressKey(step.value);
      await session.settle(20);
    } else if (step.action === "type") {
      if (showLive) process.stderr.write("\r  \u2192 type: \u001b[36m" + step.value.substring(0, 30) + "\u001b[39m");
      await session.type(step.value);
      await session.settle(20);
    } else if (step.action === "write") {
      await session.rawWrite(step.value);
      await session.settle(20);
    } else if (step.action === "wait") {
      await new Promise(r => setTimeout(r, step.value || 1000));
    } else if (step.action === "snapshot") {
      const snap = session.semanticSnapshot("full", false);
      const filePath = path.join(outDir, `snapshot-${Date.now()}.json`);
      fs.writeFileSync(filePath, JSON.stringify(snap, null, 2));
    } else if (step.action === "quit") {
      if (!session.running) break;
      await session.pressKey(step.value || "q");
      await new Promise(r => setTimeout(r, 500));
      if (session.running) {
        await session.stop({ force: true });
      }
      break;
    }

    if (showLive) {
      showProgress(si + 1, steps.length);
      // Show a frame preview every few steps
      if (si % 3 === 0 || step.action === "wait") {
        showPreview(session, cols, rows, step.action);
      }
    }
  }

  session.stopScreenCapture();

  if (session.running) {
    await session.pressKey("q");
    await new Promise(r => setTimeout(r, 500));
    if (session.running) {
      await session.stop({ force: true });
    }
  }

  await recorder.close();
  manager.dispose();

  const result = {
    sessionId: session.sessionId,
    command,
    args: args || [],
    castPath: recorder.castPath,
    htmlPath: recorder.htmlPath,
    outputDir: outDir,
    cols: session.cols,
    rows: session.rows,
  };

  console.log(JSON.stringify(result));
}

main().catch(err => {
  console.error(JSON.stringify({ error: err.message, stack: err.stack }));
  process.exit(1);
});
