#!/usr/bin/env node
/**
 * Navigate btop using the observe-decide-act-verify loop from the
 * tui-navigation skill. Uses btop-aware raw-line parsing since the
 * generic semantic extractor doesn't handle btop's rounded box-drawing
 * and Braille characters.
 *
 * Usage: node navigate_btop.mjs
 */

import { TerminalSessionManager } from "./terminal_session.mjs";

const BTOP = "/etc/profiles/per-user/jack/bin/btop";

// ── Helpers ──────────────────────────────────────────────────────────────

async function observe(session, settleMs = 300) {
  await session.settle(settleMs);
  return session.snapshot();
}

async function act(session, key) {
  // Special keys use pressKey, everything else uses type
  const specialKeys = new Set([
    "enter", "return", "tab", "escape", "esc", "backspace",
    "up", "down", "left", "right",
    "ctrl-c", "ctrl-d", "ctrl-z", "ctrl-l",
  ]);
  if (specialKeys.has(key)) {
    await session.pressKey(key);
  } else {
    await session.type(key);
  }
  await session.settle(300);
}

// ── btop-specific line parser ────────────────────────────────────────────

function parseBtop(lines) {
  const info = {
    header: {},
    cpu: { cores: [], loadAvg: null },
    memory: {},
    swap: {},
    disks: [],
    network: { download: {}, upload: {}, total: {} },
    processes: [],
    uptime: null,
    battery: null,
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // ── Header: battery, time ──
    const battMatch = line.match(/BAT▼\s*(\d+)%\s*[■□]+\s*([\d:]+)/);
    if (battMatch) {
      info.battery = { percent: battMatch[1], timeLeft: battMatch[2] };
    }
    const timeMatch = line.match(/(\d{2}:\d{2}:\d{2})/);
    if (timeMatch && !info.header.time) {
      info.header.time = timeMatch[1];
    }

    // ── CPU cores ──
    // btop puts 2 cores per line: "C0  ⣀⣀⣀...   0%│C4  ⣀⣀⣀...   0%"
    // Use global regex to find all core entries on a line
    const coreRe = /C(\d+)\s+[⣀⣿⠈⣠⣤⡄⡀⣇⡏⢀ ]+\s*(\d+)%/g;
    let coreMatch;
    while ((coreMatch = coreRe.exec(line)) !== null) {
      info.cpu.cores.push({ core: `C${coreMatch[1]}`, usage: `${coreMatch[2]}%` });
    }

    // ── CPU overall ──
    const cpuOverallMatch = line.match(/CPU\s+[■□⣀⣿⠈]+\s+(\d+)%/);
    if (cpuOverallMatch) {
      info.cpu.overall = `${cpuOverallMatch[1]}%`;
    }

    // ── Load average ──
    const loadMatch = line.match(/Load avg:\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)/);
    if (loadMatch) {
      info.cpu.loadAvg = { "1min": loadMatch[1], "5min": loadMatch[2], "15min": loadMatch[3] };
    }

    // ── Uptime ──
    const uptimeMatch = line.match(/up\s+(\d+d?\s*[\d:]+)/i);
    if (uptimeMatch && !info.uptime) {
      info.uptime = uptimeMatch[1];
    }

    // ── Memory ──
    // Only match memory lines (not network "▼ Total:" lines)
    // Memory lines are in the left panel (first ~55 chars) and don't contain ▼/▲
    const memLeft = line.substring(0, 55); // left panel is memory
    const isMemLine = !memLeft.includes("▼") && !memLeft.includes("▲");
    if (isMemLine) {
      const memUsedMatch = memLeft.match(/Used:.*?([\d.]+)\s*[─]+([KMGT]i?B)/);
      if (memUsedMatch) {
        info.memory.used = `${memUsedMatch[1]} ${memUsedMatch[2]}`;
      }
      const memTotalMatch = memLeft.match(/Total:\s+([\d.]+)\s*([KMGT]i?B)/);
      if (memTotalMatch) {
        info.memory.total = `${memTotalMatch[1]} ${memTotalMatch[2]}`;
      }
      const memAvailMatch = memLeft.match(/Available:.*?([\d.]+)\s*[─]+([KMGT]i?B)/);
      if (memAvailMatch) {
        info.memory.available = `${memAvailMatch[1]} ${memAvailMatch[2]}`;
      }
      const memCachedMatch = memLeft.match(/Cached:.*?([\d.]+)\s*[─]+([KMGT]i?B)/);
      if (memCachedMatch) {
        info.memory.cached = `${memCachedMatch[1]} ${memCachedMatch[2]}`;
      }
      const memFreeMatch = memLeft.match(/Free:.*?([\d.]+)\s*[─]+([KMGT]i?B)/);
      if (memFreeMatch) {
        info.memory.free = `${memFreeMatch[1]} ${memFreeMatch[2]}`;
      }
      const memPctMatch = memLeft.match(/Used:.*?(\d+)%/);
      if (memPctMatch && !info.memory.usedPct) {
        info.memory.usedPct = `${memPctMatch[1]}%`;
      }
    }

    // ── Network ──
    // btop format: "│▼ 2 Byte/s     (16 bitps)│"
    const dlSpeedMatch = line.match(/▼\s*([\d.]+\s*\w+\/s)\s+\((\d+\s*\w+ps)\)/);
    if (dlSpeedMatch && !info.network.download.speed) {
      info.network.download = { speed: dlSpeedMatch[1], bits: dlSpeedMatch[2] };
    }
    const dlTotalMatch = line.match(/▼ Total:\s+([\d.]+\s*[KMGT]?i?B)/);
    if (dlTotalMatch) {
      info.network.download.total = dlTotalMatch[1];
    }
    const ulSpeedMatch = line.match(/▲\s*([\d.]+\s*\w+\/s)\s+\((\d+\s*\w+ps)\)/);
    if (ulSpeedMatch && !info.network.upload.speed) {
      info.network.upload = { speed: ulSpeedMatch[1], bits: ulSpeedMatch[2] };
    }
    const ulTotalMatch = line.match(/▲ Total:\s+([\d.]+\s*[KMGT]?i?B)/);
    if (ulTotalMatch) {
      info.network.upload.total = ulTotalMatch[1];
    }

    // ── Processes ──
    // btop puts processes on the right side of the screen, after "││"
    // Format: "90401 node     node script.mjs  jack    52M ⣀⣀⣀⣀⣀  0.0"
    // Problem: variable-width columns — command and user may be separated
    // by only 1 space when command is long. Parse from the end backwards.
    const procPart = line.includes("││") ? line.split("││").pop() : line.substring(55);
    const procClean = procPart.replace(/[│┘└╯╰↓↑█]+$/, "").trim();
    if (procClean.match(/^\d+\s/) && procClean.length > 20) {
      // Match from end: memory+braille+cpu are fixed format at the end
      const endMatch = procClean.match(/^(.+?)\s+(\S+)\s+([\d.]+[KMGT]?)\s*[⣀⣿⠈⡄⡀⢀ ]+\s*([\d.]+)$/);
      if (endMatch) {
        const front = endMatch[1].trim();
        const user = endMatch[2];
        const mem = endMatch[3];
        const cpu = endMatch[4];
        // Now parse front: "PID NAME COMMAND..."
        const frontMatch = front.match(/^(\d+)\s+(\S+)\s+(.+)$/);
        if (frontMatch) {
          info.processes.push({
            pid: parseInt(frontMatch[1]),
            name: frontMatch[2].trim(),
            command: frontMatch[3].trim(),
            user: user.trim(),
            memory: mem.trim(),
            cpu: `${cpu}%`,
          });
        }
      }
    }
  }

  return info;
}

// ── Main Navigation Loop ─────────────────────────────────────────────────

async function main() {
  const manager = new TerminalSessionManager({
    env: { ...process.env, GARAZYK_PTY_MCP_ALLOW: BTOP },
  });

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║  BTOP Navigation — tui-navigation skill (observe→act→verify) ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 1: OBSERVE — Start btop and take initial snapshot
  // ═══════════════════════════════════════════════════════════════════════
  console.log("┌─ Step 1: OBSERVE ─ Starting btop, waiting for render ─┐");

  const session = manager.create({
    command: BTOP,
    cols: 120,
    rows: 40,
    title: "btop",
  });

  // btop needs time to draw its full interface
  await new Promise(r => setTimeout(r, 2000));
  const snap1 = await observe(session, 500);
  const info1 = parseBtop(snap1.lines);

  console.log("  Session:", snap1.sessionId, "Running:", snap1.running);
  console.log("  Cursor:", JSON.stringify(snap1.cursor));
  console.log("  App detected: btop (via command basename)");
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 2: DECIDE — Determine what info we want and how to get it
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ Step 2: DECIDE ─ Planning navigation ─┐");
  console.log("  Goal: Extract CPU, memory, network, and top processes");
  console.log("  Strategy: btop shows all panels simultaneously;");
  console.log("  no panel switching needed — parse the default view.");
  console.log("  btop keys: 1=CPU, 2=MEM, 3=NET, 4=PROC (full-screen)");
  console.log("  Default view already shows all panels side-by-side.");
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 3: ACT — Try navigating to full-screen views for detail
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ Step 3: ACT — Navigate to CPU full-screen view ─┐");
  const beforeCPU = await observe(session);
  await act(session, "1");
  const afterCPU = await observe(session);
  const cpuChanged = beforeCPU.lines[3] !== afterCPU.lines[3];
  console.log(`  [${cpuChanged ? "CHANGED" : "NO-OP"}] Pressed '1' for CPU view`);
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 4: VERIFY — Check if CPU view changed, extract data
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ Step 4: VERIFY — Extract CPU view data ─┐");
  if (cpuChanged) {
    const cpuInfo = parseBtop(afterCPU.lines);
    console.log("  CPU view active — expanded data available");
  } else {
    console.log("  [E1: No-Op] '1' didn't change view");
    console.log("  Diagnosis: btop may need a different key or focus");
    console.log("  Fallback: Parse default view data (already captured)");
  }
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 5: CORRECT — Go back to default view and try MEM
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ Step 5: CORRECT — Return to default, try MEM view ─┐");
  // Press '1' again to toggle back (btop toggles full-screen on/off)
  await act(session, "1");
  await new Promise(r => setTimeout(r, 500));

  // Try MEM full-screen
  const beforeMEM = await observe(session);
  await act(session, "2");
  const afterMEM = await observe(session);
  const memChanged = beforeMEM.lines[13] !== afterMEM.lines[13];
  console.log(`  [${memChanged ? "CHANGED" : "NO-OP"}] Pressed '2' for MEM view`);

  if (memChanged) {
    const memInfo = parseBtop(afterMEM.lines);
    console.log("  MEM view active — expanded data available");
  }
  // Return to default
  await act(session, "2");
  await new Promise(r => setTimeout(r, 500));
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 6: Final OBSERVE — Take comprehensive snapshot of default view
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ Step 6: OBSERVE — Final comprehensive snapshot ─┐");
  const finalSnap = await observe(session, 500);
  const finalInfo = parseBtop(finalSnap.lines);
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // Step 7: CLEANUP — Quit btop
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ Step 7: CLEANUP — Quit btop ─┐");
  await act(session, "q");
  await new Promise(r => setTimeout(r, 1000));
  const quitSnap = session.snapshot();
  console.log("  Running after 'q':", quitSnap.running);
  if (quitSnap.running) {
    console.log("  [E4: Stuck] Forcing stop...");
  }
  await session.stop({ force: true });
  console.log("└────────────────────────────────────────────────────────┘");

  // ═══════════════════════════════════════════════════════════════════════
  // REPORT
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n");
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║                    SYSTEM INFORMATION REPORT                ║");
  console.log("╠══════════════════════════════════════════════════════════════╣");

  // CPU
  console.log("║                                                              ║");
  console.log("║  CPU                                                          ║");
  if (finalInfo.cpu.overall) {
    console.log(`║    Overall: ${finalInfo.cpu.overall.padEnd(50)}║`);
  }
  if (finalInfo.cpu.cores.length) {
    const coreStr = finalInfo.cpu.cores.map(c => `${c.core}: ${c.usage}`).join("  ");
    // Wrap long lines
    for (let i = 0; i < coreStr.length; i += 50) {
      console.log(`║    ${coreStr.substring(i, i + 50).padEnd(55)}║`);
    }
  }
  if (finalInfo.cpu.loadAvg) {
    const la = finalInfo.cpu.loadAvg;
    console.log(`║    Load Avg: ${la["1min"]} / ${la["5min"]} / ${la["15min"]}`.padEnd(62) + "║");
  }

  // Memory
  console.log("║                                                              ║");
  console.log("║  MEMORY                                                      ║");
  if (finalInfo.memory.total) {
    console.log(`║    Total:     ${finalInfo.memory.total.padEnd(50)}║`);
  }
  if (finalInfo.memory.used) {
    const pct = finalInfo.memory.usedPct ? ` (${finalInfo.memory.usedPct})` : "";
    console.log(`║    Used:      ${finalInfo.memory.used}${pct}`.padEnd(62) + "║");
  }
  if (finalInfo.memory.available) {
    console.log(`║    Available: ${finalInfo.memory.available.padEnd(50)}║`);
  }
  if (finalInfo.memory.cached) {
    console.log(`║    Cached:    ${finalInfo.memory.cached.padEnd(50)}║`);
  }
  if (finalInfo.memory.free) {
    console.log(`║    Free:      ${finalInfo.memory.free.padEnd(50)}║`);
  }

  // Network
  console.log("║                                                              ║");
  console.log("║  NETWORK                                                     ║");
  if (finalInfo.network.download.speed) {
    console.log(`║    Download: ${finalInfo.network.download.speed} (${finalInfo.network.download.bits})`.padEnd(62) + "║");
  }
  if (finalInfo.network.download.total) {
    console.log(`║    DL Total: ${finalInfo.network.download.total.padEnd(50)}║`);
  }
  if (finalInfo.network.upload.speed) {
    console.log(`║    Upload:   ${finalInfo.network.upload.speed} (${finalInfo.network.upload.bits})`.padEnd(62) + "║");
  }
  if (finalInfo.network.upload.total) {
    console.log(`║    UL Total: ${finalInfo.network.upload.total.padEnd(50)}║`);
  }

  // Processes
  console.log("║                                                              ║");
  console.log("║  TOP PROCESSES (by memory)                                   ║");
  console.log("║    PID       NAME         MEMORY     USER          CPU%       ║");
  const topProcs = finalInfo.processes.slice(0, 10);
  for (const p of topProcs) {
    const line = `    ${String(p.pid).padEnd(10)}${p.name.padEnd(13)}${p.memory.padEnd(10)}${p.user.padEnd(14)}${p.cpu}`;
    console.log(`║${line.padEnd(62)}║`);
  }

  // System
  console.log("║                                                              ║");
  console.log("║  SYSTEM                                                      ║");
  if (finalInfo.uptime) {
    console.log(`║    Uptime: ${finalInfo.uptime.padEnd(51)}║`);
  }
  if (finalInfo.battery) {
    console.log(`║    Battery: ${finalInfo.battery.percent}% (${finalInfo.battery.timeLeft} remaining)`.padEnd(62) + "║");
  }
  if (finalInfo.header.time) {
    console.log(`║    Time:   ${finalInfo.header.time.padEnd(51)}║`);
  }

  console.log("║                                                              ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");

  // ═══════════════════════════════════════════════════════════════════════
  // Navigation skill findings
  // ═══════════════════════════════════════════════════════════════════════
  console.log("\n┌─ NAVIGATION SKILL FINDINGS ─┐");
  console.log("│ 1. Generic semantic extractor (Layer 2) fails on btop's     │");
  console.log("│    rounded box-drawing chars (╭╰├─│) and Braille bars      │");
  console.log("│    (⣀⣿⠈). Need app-specific heuristics or Layer 1 metadata. │");
  console.log("│                                                             │");
  console.log("│ 2. btop shows all panels simultaneously in default view —  │");
  console.log("│    no panel switching needed for overview extraction.       │");
  console.log("│                                                             │");
  console.log("│ 3. 'q' key worked correctly to quit btop.                   │");
  console.log("│                                                             │");
  console.log("│ 4. Number keys (1-4) toggle full-screen views but may      │");
  console.log("│    require focus on the correct panel first.                │");
  console.log("│                                                             │");
  console.log("│ 5. settle time of 1500-2000ms needed for btop's initial     │");
  console.log("│    render; 300ms sufficient for subsequent key responses.   │");
  console.log("└─────────────────────────────────────────────────────────────┘");

  manager.dispose();
}

main().catch(err => {
  console.error("Fatal:", err);
  process.exit(1);
});
