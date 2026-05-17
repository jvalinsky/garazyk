import { expandGlob } from "jsr:@std/fs/expand-glob";

const replacements = [
  // docker-client
  { search: /from ".*\/lib\/deno\/docker\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_api\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_events\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_binary\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_cleanup\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_compose\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_health\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/docker_types\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { search: /from ".*\/lib\/deno\/container_stats\.ts"/g, replace: 'from "@garazyk/docker-client"' },

  // atproto-topology
  { search: /from ".*\/lib\/deno\/topology\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { search: /from ".*\/lib\/deno\/topology_compiler\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { search: /from ".*\/lib\/deno\/topology_list\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { search: /from ".*\/lib\/deno\/topology_manifest\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { search: /from ".*\/lib\/deno\/topology_schema\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { search: /from ".*\/lib\/deno\/topology_types\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { search: /from ".*\/lib\/deno\/topology_registry\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },

  // atproto-client
  { search: /from ".*\/lib\/deno\/client\.ts"/g, replace: 'from "@garazyk/atproto-client"' },
  { search: /from ".*\/lib\/deno\/transport\.ts"/g, replace: 'from "@garazyk/atproto-client"' },
  { search: /from ".*\/lib\/deno\/firehose\.ts"/g, replace: 'from "@garazyk/atproto-client"' },
  { search: /from ".*\/lib\/deno\/seed\.ts"/g, replace: 'from "@garazyk/atproto-client/seed"' },

  // scenario-runner (catch-all for the rest)
  { search: /from ".*\/lib\/deno\/diagnostics\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/scenario_metadata\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/scenario_selector\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/run_loop\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/process_lifecycle\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/report_writer\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/otel\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/runner\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/run_scenarios_types\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/config\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/assertions\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { search: /from ".*\/lib\/deno\/browser_flow\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
];

async function main() {
  for await (const entry of expandGlob("scripts/**/*.{ts,tsx}")) {
    if (!entry.isFile) continue;
    
    let content = await Deno.readTextFile(entry.path);
    let modified = false;

    for (const rule of replacements) {
      const newContent = content.replace(rule.search, rule.replace);
      if (newContent !== content) {
        content = newContent;
        modified = true;
      }
    }

    if (modified) {
      await Deno.writeTextFile(entry.path, content);
      console.log(`Updated ${entry.path}`);
    }
  }
}

main();