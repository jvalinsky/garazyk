#!/usr/bin/env -S deno run -A

import * as colors from "jsr:@std/fmt/colors";
import { Spinner } from "jsr:@std/cli/unstable-spinner";
import { join } from "jsr:@std/path";
import { TextLineStream } from "jsr:@std/streams";

interface Task {
  name: string;
  command: string[];
  cwd?: string;
  env?: Record<string, string>;
  isBuildStep?: boolean;
  parseXCTestOutput?: boolean;
}

const tasks: Task[] = [
  {
    name: "XcodeGen Generate",
    command: ["xcodegen", "generate"],
    isBuildStep: true,
  },
  {
    name: "Build AllTests",
    command: ["xcodebuild", "-scheme", "AllTests", "build"],
    isBuildStep: true,
  },
  {
    name: "Check UI Design System",
    command: ["./scripts/test/check_ui_design_system.sh"],
  },
  {
    name: "XCTest Suite (Unit & Integration)",
    command: ["build/tests/AllTests"],
    parseXCTestOutput: true,
  },
  {
    name: "Deno Package Tests",
    command: ["deno", "task", "test"],
  },
  {
    name: "E2E Scenario Tests",
    command: ["deno", "task", "hamownia", "run"],
  }
];

interface TestResult {
  name: string;
  success: boolean;
  durationMs: number;
  isBuildStep?: boolean;
  details?: any;
}

async function runTask(task: Task): Promise<{ success: boolean; details?: any }> {
  const prefix = task.isBuildStep ? "[BUILD]" : "[TEST]";
  console.log(colors.cyan(`\n>> ${prefix} ${task.name}`));
  console.log(colors.gray(`   Command: ${task.command.join(" ")}`));
  console.log(colors.gray("-".repeat(80)));

  try {
    const env = { ...task.env, FORCE_COLOR: "1" };
    const cmd = new Deno.Command(task.command[0], {
      args: task.command.slice(1),
      cwd: task.cwd,
      env: env,
      stdout: "piped",
      stderr: "piped", 
    });

    const child = cmd.spawn();
    let testTimes: number[] = [];
    const logBuffer: string[] = [];
    let lastBuildPct = 0;
    
    let isTTY = false;
    try {
      isTTY = Deno.stdout.isTerminal();
    } catch {
      try {
        // @ts-ignore fallback for older Deno
        isTTY = Deno.isatty(Deno.stdout.rid);
      } catch {}
    }
    
    let totalXCTests = 0;
    const classTestCounts: Record<string, number> = {};
    if (task.parseXCTestOutput) {
      try {
        const listCmd = new Deno.Command(task.command[0], {
          args: [...task.command.slice(1), "-l", "-v"],
          cwd: task.cwd,
          env: task.env
        });
        const outBytes = listCmd.outputSync().stderr;
        const outStr = new TextDecoder().decode(outBytes);
        const m = outStr.match(/(\d+) methods/);
        if (m) totalXCTests = parseInt(m[1], 10);
        
        let parsingClass = "";
        for (const line of outStr.split('\n')) {
          const matchClass = line.match(/^([A-Za-z0-9_]+)\s*\(/);
          if (matchClass) {
            parsingClass = matchClass[1];
            classTestCounts[parsingClass] = 0;
          } else if (line.startsWith("  test") && parsingClass) {
            classTestCounts[parsingClass]++;
          }
        }
      } catch (e) {
        // ignore if fails to list
      }
    }

    let currentClassTestsCompleted = 0;
    let currentSuite = "";

    const handleLine = (line: string, isStderr: boolean) => {
      const lineTrimmed = line.trim();
      logBuffer.push(isStderr ? `[stderr] ${line}` : line);
      if (logBuffer.length > 5000) logBuffer.shift();

      if (lineTrimmed === "") return;
      let match: RegExpMatchArray | null;

      if (task.parseXCTestOutput) {
        if ((match = line.match(/Test Suite '(.*)' started/))) {
          const suiteName = match[1];
          if (suiteName !== "All Tests" && !suiteName.endsWith(".xctest")) {
            currentSuite = suiteName;
            currentClassTestsCompleted = 0;
            console.log(colors.blue(colors.bold(`\n  [CLASS] ${currentSuite}`)));
          }
        } 
        else if ((match = line.match(/Test Case '-\[(.*) (.*)\]' passed \((.*) seconds\)/))) {
          const timeSec = parseFloat(match[3]);
          testTimes.push(timeSec);
          currentClassTestsCompleted++;
          const timeStr = (timeSec * 1000).toFixed(1) + "ms";
          const testName = match[2];
          console.log(`    ${colors.green("+")} ${testName.padEnd(45)} ${colors.gray(`(${timeStr})`)}`);
        } 
        else if ((match = line.match(/Test Case '-\[(.*) (.*)\]' failed \((.*) seconds\)/))) {
          const timeSec = parseFloat(match[3]);
          testTimes.push(timeSec);
          currentClassTestsCompleted++;
          const timeStr = (timeSec * 1000).toFixed(1) + "ms";
          const testName = match[2];
          console.log(`    ${colors.red("-")} ${testName.padEnd(45)} ${colors.red(`(${timeStr})`)}`);
        } 
        else if ((match = line.match(/Executed (\d+) tests?, with (\d+) failures? .* in (.*) \((.*)\) seconds/))) {
          const numTests = match[1];
          const failures = match[2];
          const wallTime = match[4];
          if (failures === "0") {
            console.log(`    ${colors.green(`+ All ${numTests} passed`)} in ${colors.gray(`${wallTime}s`)}`);
          } else {
            console.log(`    ${colors.red(`- ${failures} failed`)} out of ${numTests} in ${colors.gray(`${wallTime}s`)}`);
          }
        } 
        else if (
          line.match(/Test Case '-\[.*\]' started/) || 
          line.match(/Test Suite '.*' (passed|failed) at/) ||
          line.match(/=== Starting Test Suite:/) ||
          line.match(/=== Test Suite Finished ===/) ||
          line.match(/Test suites: /)
        ) {
          // ignore completely
        } else {
          // Noise is ignored for XCTest
        }
      } else {
        const lower = line.toLowerCase();
        let isNoise = false;
        
        if (task.isBuildStep) {
          const pctMatch = lineTrimmed.match(/^\[\s*(\d+)%\]/);
          if (pctMatch) {
            lastBuildPct = parseInt(pctMatch[1], 10);
          }
          
          const isWarningOrError = lower.includes("warning:") || lower.includes("error:") || lower.includes("failed");
          isNoise = !isWarningOrError;
        } else {
          isNoise = 
            lower.includes("docker") || 
            lower.includes("level=debug") || 
            lower.includes("level=info") || 
            lower.includes("msg=") || 
            lower.includes("container") ||
            lower.includes("check-ui-design-system") ||
            lineTrimmed.startsWith("Download") ||
            lower.includes("checking ");
        }

        if (!isNoise) {
          const prefix = isStderr ? colors.red("    [stderr] ") : colors.gray("    | ");
          console.log(`${prefix}${line}`);
        }
      }
    };


    const stdoutStream = child.stdout
      .pipeThrough(new TextDecoderStream())
      .pipeThrough(new TextLineStream());

    const stderrStream = child.stderr
      .pipeThrough(new TextDecoderStream())
      .pipeThrough(new TextLineStream());

    const stdoutPromise = (async () => {
      for await (const line of stdoutStream) {
        handleLine(line, false);
      }
    })();

    const stderrPromise = (async () => {
      for await (const line of stderrStream) {
        handleLine(line, true);
      }
    })();

    await Promise.all([stdoutPromise, stderrPromise]);

    const status = await child.status;

    console.log(colors.gray("-".repeat(80)));
    
    const details = task.parseXCTestOutput ? { testTimes } : undefined;

    if (status.success) {
      console.log(colors.green(`+ ${task.name} completed successfully.`));
      return { success: true, details };
    } else {
      console.log(colors.red(`- ${task.name} failed with code ${status.code}.`));
      console.log(colors.yellow(`\n--- Last 50 lines of output for debugging ---`));
      const recentLogs = logBuffer.slice(-50);
      for (const l of recentLogs) {
        console.log(colors.gray(l));
      }
      console.log(colors.yellow(`---------------------------------------------`));
      return { success: false, details };
    }
  } catch (error) {
    console.log(colors.gray("-".repeat(80)));
    console.log(colors.red(`✖ ${task.name} failed to start or threw an exception.`));
    if (error instanceof Error) {
      console.log(colors.red(`  Error: ${error.message}`));
    }
    return { success: false };
  }
}

function printTimingStats(times: number[]) {
  if (!times || times.length === 0) return;
  
  times.sort((a, b) => a - b);
  const count = times.length;
  const sum = times.reduce((a, b) => a + b, 0);
  const mean = sum / count;
  const min = times[0];
  const max = times[count - 1];
  const p50 = times[Math.floor(count * 0.50)];
  const p90 = times[Math.floor(count * 0.90)];
  const p95 = times[Math.floor(count * 0.95)];
  const p99 = times[Math.floor(count * 0.99)];

  console.log(colors.magenta(colors.bold("\n📊 XCTest Timing Statistics")));
  console.log(colors.magenta("-".repeat(80)));
  
  const fmt = (n: number) => (n * 1000).toFixed(1).padStart(7) + "ms";
  
  console.log(`  ${colors.white("Count :")} ${count.toString().padStart(5)} tests    ${colors.white("Mean :")} ${fmt(mean)}`);
  console.log(`  ${colors.white("Median:")} ${fmt(p50)}          ${colors.white("P90  :")} ${fmt(p90)}`);
  console.log(`  ${colors.white("P95   :")} ${fmt(p95)}          ${colors.white("P99  :")} ${fmt(p99)}`);
  console.log(`  ${colors.white("Min   :")} ${fmt(min)}          ${colors.white("Max  :")} ${fmt(max)}`);
  
  console.log(colors.magenta(colors.bold("\n📈 Test Execution Time Distribution")));
  console.log(colors.magenta("-".repeat(80)));

  const predefinedBins = [
    { label: "< 10ms", max: 0.010, count: 0 },
    { label: "10-50ms", max: 0.050, count: 0 },
    { label: "50-100ms", max: 0.100, count: 0 },
    { label: "100-250ms", max: 0.250, count: 0 },
    { label: "250-500ms", max: 0.500, count: 0 },
    { label: "500ms-1s", max: 1.0, count: 0 },
    { label: "1s-2s", max: 2.0, count: 0 },
    { label: "2s-5s", max: 5.0, count: 0 },
    { label: "> 5s", max: Infinity, count: 0 },
  ];

  for (const t of times) {
    for (const bin of predefinedBins) {
      if (t <= bin.max) {
        bin.count++;
        break;
      }
    }
  }

  const maxCount = Math.max(...predefinedBins.map(b => b.count));
  const maxBarLength = 40;

  for (const bin of predefinedBins) {
    if (bin.count === 0 && bin.max > 0.500) continue; // skip trailing empty bins for large times
    const barLength = maxCount > 0 ? Math.round((bin.count / maxCount) * maxBarLength) : 0;
    
    // Gradient coloring based on duration
    let barColor = colors.cyan;
    if (bin.max > 1.0) barColor = colors.red;
    else if (bin.max > 0.250) barColor = colors.yellow;
    
    const bar = barColor("█".repeat(barLength));
    const labelStr = colors.white(bin.label.padEnd(12));
    const countStr = bin.count.toString().padStart(4);
    
    console.log(`  ${labelStr} | ${countStr} | ${bar}`);
  }
}

async function main() {
  console.log(colors.blue(colors.bold("================================================================================")));
  console.log(colors.blue(colors.bold("                     Garazyk Unified Test Suite Runner                          ")));
  console.log(colors.blue(colors.bold("================================================================================\n")));

  const results: TestResult[] = [];
  const startTime = Date.now();
  let allTestsPassed = true;
  let buildFailed = false;

  for (const task of tasks) {
    const taskStartTime = Date.now();
    const result = await runTask(task);
    const durationMs = Date.now() - taskStartTime;

    results.push({
      name: task.name,
      success: result.success,
      durationMs,
      isBuildStep: task.isBuildStep,
      details: result.details,
    });

    if (!result.success) {
      if (task.isBuildStep) {
        buildFailed = true;
        console.log(colors.yellow(`\n⚠ Stopping further execution because a required build step failed.`));
        break;
      } else {
        allTestsPassed = false;
      }
    }
  }

  const totalDurationMs = Date.now() - startTime;

  console.log(colors.blue(colors.bold("\n================================================================================")));
  console.log(colors.blue(colors.bold("                                  Summary                                       ")));
  console.log(colors.blue(colors.bold("================================================================================")));

  for (const result of results) {
    const durationStr = (result.durationMs / 1000).toFixed(2) + "s";
    const statusLabel = result.success ? colors.green("[PASS]") : colors.red("[FAIL]");
    const nameFormatted = colors.white(result.name.padEnd(55));
    const timeFormatted = colors.gray(durationStr.padStart(8));
    
    console.log(`${statusLabel} | ${nameFormatted} | ${timeFormatted}`);
  }

  // Find XCTest task details to print timing stats
  const xctestResult = results.find(r => r.name.includes("XCTest Suite"));
  if (xctestResult && xctestResult.details && xctestResult.details.testTimes) {
    printTimingStats(xctestResult.details.testTimes);
  }

  console.log(colors.blue(colors.bold("\n================================================================================")));
  console.log(colors.white(colors.bold(`Total Time: ${(totalDurationMs / 1000).toFixed(2)}s`)));
  
  try {
    const reportPath = join(Deno.cwd(), "test_run_summary.json");
    const reportData = {
      timestamp: new Date().toISOString(),
      totalDurationMs,
      allTestsPassed: allTestsPassed && !buildFailed,
      buildFailed,
      results
    };
    await Deno.writeTextFile(reportPath, JSON.stringify(reportData, null, 2));
    console.log(colors.gray(`\n📄 Detailed JSON report saved to: ${reportPath}`));
  } catch (err) {
    console.error(colors.red("\nFailed to save test results to file:"), err);
  }

  if (buildFailed) {
    console.log(colors.red(colors.bold("\n💥 Test suite aborted due to build failure.")));
    Deno.exit(1);
  } else if (allTestsPassed) {
    console.log(colors.green(colors.bold("\n🎉 All tasks and tests completed successfully!")));
    Deno.exit(0);
  } else {
    console.log(colors.red(colors.bold("\n💥 Some tests failed. Please review the output above.")));
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
