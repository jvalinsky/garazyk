# `@garazyk/scenario-dashboard`

Fresh web dashboard and terminal UI for Garazyk scenario runs.

## Commands

From a Garazyk checkout:

```bash
deno task dashboard
deno task dashboard:tui
```

From JSR after publishing:

```bash
deno run -A jsr:@garazyk/scenario-dashboard/cli tui --root /path/to/garazyk
```

The tool resolves the checkout root from `--root`, `GARAZYK_ROOT`, or the
current working directory.

The Fresh web dashboard remains a checkout-local app via `deno task dashboard`.
