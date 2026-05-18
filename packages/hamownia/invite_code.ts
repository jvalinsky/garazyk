/** SSH-based invite code helpers for Garazyk account provisioning. */

function sqlString(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

async function commandWithInput(
  command: string,
  args: string[],
  input: string,
): Promise<{ code: number; stdout: string; stderr: string }> {
  const child = new Deno.Command(command, {
    args,
    stdin: "piped",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(input));
  await writer.close();
  const output = await child.output();
  return {
    code: output.code,
    stdout: new TextDecoder().decode(output.stdout),
    stderr: new TextDecoder().decode(output.stderr),
  };
}

/** Insert an invite code into the remote PDS SQLite database via SSH. */
export async function insertInviteCodeViaSsh(
  sshHost: string,
  dbPath: string,
  code: string,
  accountDid: string,
  maxUses = 1,
): Promise<void> {
  const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const id = crypto.randomUUID();
  const sql =
    `INSERT INTO invite_codes (id, code, account_did, created_at, uses, max_uses, disabled) VALUES (${
      sqlString(id)
    }, ${sqlString(code)}, ${sqlString(accountDid)}, ${
      sqlString(now)
    }, 0, ${maxUses}, 0);`;
  const result = await commandWithInput("ssh", [
    "-T",
    sshHost,
    "sqlite3",
    dbPath,
  ], sql);
  if (result.code !== 0) {
    throw new Error(
      `Failed to insert invite code via SSH: ${
        result.stderr.trim() || "ssh command failed"
      }`,
    );
  }
}

/** Fetch the first unused invite code from the remote PDS SQLite database via SSH. */
export async function getExistingInviteCodeViaSsh(
  sshHost: string,
  dbPath: string,
): Promise<string | null> {
  const sql =
    "SELECT code FROM invite_codes WHERE disabled = 0 AND uses < max_uses LIMIT 1;";
  const result = await commandWithInput("ssh", [
    "-T",
    sshHost,
    "sqlite3",
    dbPath,
  ], sql);
  if (result.code !== 0) {
    throw new Error(
      `Failed to query invite codes via SSH: ${
        result.stderr.trim() || "ssh command failed"
      }`,
    );
  }
  const code = result.stdout.trim();
  return code || null;
}
