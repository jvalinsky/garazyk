import { expandGlob } from "jsr:@std/fs/expand-glob";

const replacements = [
  // docker-client
  { file: /packages\/docker-client\/.*\.ts$/, search: /from "\.\/otel\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { file: /packages\/docker-client\/.*\.ts$/, search: /from "\.\/format\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { file: /packages\/docker-client\/.*\.ts$/, search: /from "\.\/docker_config\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { file: /packages\/docker-client\/.*\.ts$/, search: /from "\.\/docker_diagnostics\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },

  // atproto-topology
  { file: /packages\/atproto-topology\/.*\.ts$/, search: /from "\.\/scenario_metadata\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },
  { file: /packages\/atproto-topology\/.*\.ts$/, search: /from "\.\/scenario_selector\.ts"/g, replace: 'from "@garazyk/scenario-runner"' },

  // scenario-runner
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_events\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_api\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_binary\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_cleanup\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_compose\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_health\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_types\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/container_stats\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_runner\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker\.ts"/g, replace: 'from "@garazyk/docker-client"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/docker_config\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },

  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/topology\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/topology_schema\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/topology_types\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
  { file: /packages\/scenario-runner\/.*\.ts$/, search: /from "\.\/topology_registry\.ts"/g, replace: 'from "@garazyk/atproto-topology"' },
];

async function main() {
  for await (const entry of expandGlob("packages/**/*.ts")) {
    if (!entry.isFile) continue;
    
    let content = await Deno.readTextFile(entry.path);
    let modified = false;

    for (const rule of replacements) {
      if (rule.file.test(entry.path)) {
        const newContent = content.replace(rule.search, rule.replace);
        if (newContent !== content) {
          content = newContent;
          modified = true;
        }
      }
    }

    if (modified) {
      await Deno.writeTextFile(entry.path, content);
      console.log(`Updated ${entry.path}`);
    }
  }
}

main();