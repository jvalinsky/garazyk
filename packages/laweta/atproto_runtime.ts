/**
 * Compatibility helpers for Garazyk's local ATProto test runtime.
 *
 * These are kept off the root export so `@garazyk/laweta` remains a
 * generic Docker package.
 *
 * @module atproto_runtime
 */

export type { LocalNetworkOptions, RunContext } from "./docker_types.ts";
export {
  initRunDir,
  neededPorts,
  repoRoot,
  SERVICE_PORTS,
  serviceUrl,
} from "./runtime_config.ts";
export {
  stopStaleDockerE2e,
  stopStaleHostProcesses,
} from "./docker_cleanup.ts";
export { startBinaryServices, stopBinaryServices } from "./docker_binary.ts";
