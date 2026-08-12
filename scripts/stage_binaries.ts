#!/usr/bin/env -S deno run -A
/**
 * stage_binaries.ts — Build Linux ELF binaries inside Docker for local-network.
 *
 * This is a Deno-native replacement for stage-docker-binaries.sh.
 * It builds the binaries using the Dockerfile.gnustep builder stage and
 * populates the local staging directory used by Docker Compose.
 */

import { parseArgs } from "@std/cli";
import { fromFileUrl, join } from "@std/path";
import { exists } from "@std/fs";

const scriptDir = fromFileUrl(new URL(".", import.meta.url));
const repoRoot = join(scriptDir, "..");
const stagingDir = join(repoRoot, "docker/local-network/staging");
const dockerfile = join(repoRoot, "docker/Dockerfile.gnustep");
const builderTarget = "builder";
const imageTag = "garazyk-staging-builder:latest";

const BINARIES = [
  "kaszlak",
  "campagnola",
  "zuk",
  "syrena",
  "mikrus",
  "beskid",
  "jelcz",
  "syrena-chat",
  "germ",
];

const args = parseArgs(Deno.args, {
  boolean: ["check", "help"],
  alias: { h: "help" },
});

if (args.help) {
  console.log(`Usage: stage_binaries.ts [options]

  --check    Verify staging binaries are Linux ELF (don't build)
  --help     Show this help message`);
  Deno.exit(0);
}

/** Verify that a file is a Linux ELF binary. */
async function isElf(path: string): Promise<boolean> {
  const proc = new Deno.Command("file", {
    args: ["-b", path],
    stdout: "piped",
  });
  const { stdout } = await proc.output();
  const info = new TextDecoder().decode(stdout);
  return info.includes("ELF");
}

async function checkMode() {
  let ok = true;
  const binDir = join(stagingDir, "bin");

  for (const binary of BINARIES) {
    const path = join(binDir, binary);
    if (!await exists(path)) {
      console.log(`MISSING: ${binary}`);
      ok = false;
      continue;
    }

    const infoProc = new Deno.Command("file", {
      args: ["-b", path],
      stdout: "piped",
    });
    const { stdout } = await infoProc.output();
    const info = new TextDecoder().decode(stdout).trim();

    if (info.includes("ELF")) {
      console.log(`OK:     ${binary.padEnd(12)} — ${info}`);
    } else {
      console.log(`WRONG:  ${binary.padEnd(12)} — ${info} (expected ELF)`);
      ok = false;
    }
  }

  if (ok) {
    console.log("\nAll staging binaries are Linux ELF.");
    Deno.exit(0);
  } else {
    console.error("\nSome staging binaries are missing or wrong format.");
    Deno.exit(1);
  }
}

async function runDocker(
  cmd: string,
  args: string[],
  options: Deno.CommandOptions = {},
) {
  const proc = new Deno.Command("docker", {
    args: [cmd, ...args],
    ...options,
  });
  const { code, stderr } = await proc.output();
  if (code !== 0) {
    const err = new TextDecoder().decode(stderr);
    throw new Error(`Docker ${cmd} failed (exit ${code}): ${err}`);
  }
}

/**
 * Copy a directory tree while replacing symbolic links with their targets.
 *
 * Docker rejects staging-context symlinks whose targets live outside the
 * context. The source asset trees intentionally link to the shared design
 * system, so staging must materialize those links as ordinary files.
 */
async function copyTreeDereferencingSymlinks(
  source: string,
  target: string,
  ancestors = new Set<string>(),
): Promise<void> {
  const resolvedSource = await Deno.realPath(source);
  const sourceInfo = await Deno.stat(resolvedSource);

  if (sourceInfo.isDirectory) {
    if (ancestors.has(resolvedSource)) {
      throw new Error(`Asset symlink cycle detected at ${source}`);
    }

    ancestors.add(resolvedSource);
    try {
      await Deno.mkdir(target, { recursive: true });
      for await (const entry of Deno.readDir(resolvedSource)) {
        await copyTreeDereferencingSymlinks(
          join(resolvedSource, entry.name),
          join(target, entry.name),
          ancestors,
        );
      }
    } finally {
      ancestors.delete(resolvedSource);
    }
    return;
  }

  if (sourceInfo.isFile) {
    await Deno.mkdir(join(target, ".."), { recursive: true });
    await Deno.copyFile(resolvedSource, target);
    await Deno.chmod(target, sourceInfo.mode ?? 0o644);
    return;
  }

  throw new Error(`Unsupported asset entry type: ${source}`);
}

/** Replace one staged asset tree atomically so failed runs leave no partial tree. */
async function stageAsset(name: string, source: string): Promise<void> {
  const target = join(stagingDir, name);
  const temporaryTarget = `${target}.tmp-${crypto.randomUUID()}`;
  console.log(`[stage] Copying ${name}...`);

  try {
    await copyTreeDereferencingSymlinks(source, temporaryTarget);
    await Deno.remove(target, { recursive: true }).catch(() => {});
    await Deno.rename(temporaryTarget, target);
  } catch (error) {
    await Deno.remove(temporaryTarget, { recursive: true }).catch(() => {});
    throw error;
  }
}

async function buildMode() {
  console.log("[stage] Building Linux binaries inside Docker...");
  console.log(`[stage] Using Dockerfile: ${dockerfile}`);

  const buildProc = new Deno.Command("docker", {
    args: [
      "build",
      "-f",
      dockerfile,
      "--target",
      builderTarget,
      "-t",
      imageTag,
      repoRoot,
    ],
    stdout: "inherit",
    stderr: "inherit",
  });
  const buildResult = await buildProc.output();
  if (buildResult.code !== 0) {
    throw new Error(`Docker build failed with exit code ${buildResult.code}`);
  }

  console.log("[stage] Extracting binaries from Docker image...");

  // Create temporary container
  const createProc = new Deno.Command("docker", {
    args: ["create", imageTag, "/bin/true"],
    stdout: "piped",
  });
  const { stdout: createStdout } = await createProc.output();
  const containerId = new TextDecoder().decode(createStdout).trim();

  try {
    const binDir = join(stagingDir, "bin");
    await Deno.mkdir(binDir, { recursive: true });

    for (const binary of BINARIES) {
      console.log(`[stage] Copying ${binary}...`);
      await runDocker("cp", [
        `${containerId}:/src/build/bin/${binary}`,
        join(binDir, binary),
      ]);
      await Deno.chmod(join(binDir, binary), 0o755);
    }

    console.log("[stage] Copying Admin UI assets...");
    const assetsDir = join(binDir, "Assets");
    await Deno.mkdir(assetsDir, { recursive: true });
    await runDocker("cp", [
      `${containerId}:/src/build/bin/Assets/.`,
      assetsDir,
    ]);

    console.log("[stage] Extracting libraries...");
    const libDir = join(stagingDir, "lib");
    await Deno.mkdir(libDir, { recursive: true });
    await runDocker("cp", [
      `${containerId}:/usr/GNUstep/Local/Library/Libraries/.`,
      libDir,
    ]);
    try {
      await runDocker("cp", [
        `${containerId}:/usr/GNUstep/Local/lib/.`,
        libDir,
      ]);
    } catch {
      // Ignore if /usr/GNUstep/Local/lib doesn't exist
    }

    console.log("[stage] Copying lexicons...");
    const lexiconStaging = join(stagingDir, "lexicons");
    await Deno.remove(lexiconStaging, { recursive: true }).catch(() => {});
    await Deno.mkdir(lexiconStaging, { recursive: true });
    await runDocker("cp", [
      `${containerId}:/src/Garazyk/Resources/lexicons/.`,
      lexiconStaging,
    ]);

    await stageAsset(
      "PLC-assets",
      join(repoRoot, "Garazyk/Sources/PLC/Assets"),
    );
    await stageAsset(
      "Auth-assets",
      join(repoRoot, "Garazyk/Sources/Auth/Assets"),
    );
    await stageAsset(
      "css-shared",
      join(repoRoot, "Garazyk/Sources/Shared/DesignSystem/css"),
    );

    console.log("[stage] Verifying binaries...");
    for (const binary of BINARIES) {
      const path = join(binDir, binary);
      const ok = await isElf(path);
      if (ok) {
        console.log(`  OK:   ${binary}`);
      } else {
        console.error(`  FAIL: ${binary} (expected ELF)`);
        Deno.exit(1);
      }
    }

    console.log(`[stage] Done. Linux ELF binaries are in ${binDir}`);
  } finally {
    await runDocker("rm", [containerId]);
  }
}

if (args.check) {
  await checkMode();
} else {
  await buildMode();
}
