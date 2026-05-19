export {
  Character,
  createCharacterRegistry,
  createScenarioConfig,
} from "@garazyk/hamownia";
export type {
  CharacterRegistry,
  ScenarioConfig,
  ScenarioConfigOptions,
  WebClientConfig,
} from "@garazyk/hamownia";

export {
  repoRoot,
  serviceUrl,
} from "@garazyk/schemat/runtime";

import { createScenarioConfig, createCharacterRegistry } from "@garazyk/hamownia";
import type { WebClientConfig } from "@garazyk/hamownia";

const config = createScenarioConfig();

const pds1 = (Deno.env.get("PDS_URL") ?? Deno.env.get("ATPROTO_PDS_URL") ?? config.pds1).replace(/\/$/, "");
const pds2 = (Deno.env.get("PDS2_URL") ?? Deno.env.get("ATPROTO_PDS2_URL") ?? config.pds2).replace(/\/$/, "");
export const PDS1 = pds1;
export const PDS2 = pds2;

export const SERVICE_URLS: Record<string, string> = {
  ...config.serviceUrls,
  pds: pds1,
  pds2: pds2,
};

export const APPVIEW_ADMIN_SECRET = config.appviewAdminSecret;
export const PDS_ADMIN_PASSWORD = config.pdsAdminPassword;
export const UI_ADMIN_PASSWORD = config.uiAdminPassword;
export const VIDEO_SERVICE_DID = config.videoServiceDid;

export const WEB_CLIENT_TOPOLOGY: WebClientConfig | undefined = config.webClientTopology;

let registry = createCharacterRegistry();

export function resetCharacters(): void {
  registry = createCharacterRegistry();
}

export function getCharacter(name: string) {
  return registry.getCharacter(name);
}

export function getCharactersByRole(role: string) {
  return registry.getCharactersByRole(role);
}

export function getCharactersByPds(pdsUrl: string) {
  return registry.getCharactersByPds(pdsUrl);
}
