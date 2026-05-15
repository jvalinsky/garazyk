/**
 * Docker Compose lifecycle operations.
 *
 * @module docker_compose
 */

/** Run `docker compose up -d --build` with the given compose files. */
export async function composeUp(
  composeProject: string,
  composeFiles: string[],
): Promise<void> {
  const args = ["compose", "-p", composeProject];
  for (const f of composeFiles) {
    args.push("-f", f);
  }
  args.push("up", "-d", "--build");

  const proc = new Deno.Command("docker", {
    args,
    stdout: "inherit",
    stderr: "inherit",
  });
  const { code } = await proc.output();
  if (code !== 0) {
    throw new Error(`docker compose up failed (exit ${code})`);
  }
}

/** Run `docker compose down -v --remove-orphans`. */
export async function composeDown(
  composeProject: string,
  composeFiles?: string[],
): Promise<void> {
  const args = ["compose", "-p", composeProject];
  if (composeFiles) {
    for (const f of composeFiles) {
      args.push("-f", f);
    }
  }
  args.push("down", "-v", "--remove-orphans");

  const proc = new Deno.Command("docker", {
    args,
    stdout: "inherit",
    stderr: "inherit",
  });
  await proc.output();
}
