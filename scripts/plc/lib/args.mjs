/**
 * Shared CLI argument parser for PLC scripts.
 *
 * Provides a declarative option definition system with:
 *   - Short and long flags
 *   - Type coercion (string, int, boolean)
 *   - Environment variable fallbacks (PLC_SERVER, PLC_AFTER, etc.)
 *   - Automatic --help generation
 *   - Unknown option detection
 *
 * Used by: verify_plc_operation.mjs, simulate_plc_sync.mjs, audit_plc_export.mjs
 */

// ── Option definition ─────────────────────────────────────────────

/**
 * Define a CLI option.
 *
 * @param {object} spec
 * @param {string} spec.name       - Key in the returned args object
 * @param {string} spec.flag       - Long flag (e.g. '--server')
 * @param {string} [spec.short]    - Short flag (e.g. '-s')
 * @param {'string'|'int'|'boolean'} spec.type
 * @param {*}      spec.default     - Default value
 * @param {string} [spec.env]      - Environment variable override
 * @param {string} spec.description - For --help output
 * @param {(v: string) => *} [spec.parse] - Custom parser (overrides type)
 */
export function option(spec) {
  return {
    type: "string",
    parse: null,
    short: null,
    env: null,
    ...spec,
  };
}

// ── Parser ────────────────────────────────────────────────────────

/**
 * Parse argv against a list of option definitions.
 *
 * Returns { args, rest } where args is the parsed options object
 * and rest is an array of positional arguments.
 *
 * Environment variables take lowest priority; CLI flags override them.
 */
export function parseArgs(argv, options) {
  const args = {};
  for (const opt of options) {
    // Start with default
    let value = opt.default;

    // Apply env var override
    if (opt.env && process.env[opt.env] !== undefined) {
      value = coerce(process.env[opt.env], opt);
    }

    args[opt.name] = value;
  }

  // Build flag lookup
  const flagMap = new Map();
  for (const opt of options) {
    flagMap.set(opt.flag, opt);
    if (opt.short) flagMap.set(opt.short, opt);
  }

  const rest = [];
  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    const opt = flagMap.get(arg);

    if (opt) {
      if (opt.type === "boolean" || (opt.parse && opt.parse === Boolean)) {
        args[opt.name] = true;
      } else {
        const val = argv[++i];
        if (val === undefined) {
          console.error(`Error: ${arg} requires a value`);
          process.exit(2);
        }
        args[opt.name] = coerce(val, opt);
      }
    } else if (arg === "-h" || arg === "--help") {
      return { args, rest, helpRequested: true };
    } else if (arg.startsWith("-")) {
      console.error(`Error: unknown option ${arg}`);
      process.exit(2);
    } else {
      rest.push(arg);
    }
  }

  return { args, rest, helpRequested: false };
}

function coerce(val, opt) {
  if (opt.parse) return opt.parse(val);
  if (opt.type === "int") return parseInt(val, 10);
  if (opt.type === "boolean") return val !== "false" && val !== "0";
  return val;
}

// ── Help generation ───────────────────────────────────────────────

/**
 * Generate a formatted --help section from option definitions.
 *
 * @param {string} description - One-line description of the script
 * @param {string} usage - Usage line (e.g. 'node script.mjs [options] <did>')
 * @param {object[]} options - Array of option() definitions
 * @param {string} [examples] - Optional examples section
 * @returns {string}
 */
export function formatHelp(description, usage, options, examples) {
  const flagWidth = Math.max(...options.map((o) => {
    let s = o.flag;
    if (o.short) s = `${o.short}, ${o.flag}`;
    if (o.type !== "boolean") s += ` <${o.type === "int" ? "n" : o.type}>`;
    return s.length;
  }));

  const lines = [description, "", "Usage:", `  ${usage}`, "", "Options:"];

  for (const opt of options) {
    let flag = opt.flag;
    if (opt.short) flag = `${opt.short}, ${opt.flag}`;
    if (opt.type !== "boolean") flag += ` <${opt.type === "int" ? "n" : opt.type}>`;

    let desc = opt.description;
    const defaults = [];
    if (opt.env) defaults.push(`env: ${opt.env}`);
    if (opt.type !== "boolean" && opt.default !== undefined && opt.default !== null) {
      defaults.push(`default: ${opt.default}`);
    }
    if (defaults.length > 0) desc += ` (${defaults.join(", ")})`;

    lines.push(`  ${flag.padEnd(flagWidth + 2)} ${desc}`);
  }

  if (examples) {
    lines.push("", "Examples:", examples);
  }

  return lines.join("\n");
}

/**
 * Print help and exit.
 */
export function printHelpAndExit(description, usage, options, examples) {
  console.log(formatHelp(description, usage, options, examples));
  process.exit(0);
}
