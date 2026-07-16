export {
  blockUser,
  followUser,
  likePost,
  muteUser,
  postStatus,
  unmuteUser,
} from "@garazyk/hamownia";
export type {
  ScenarioConfig,
  ScenarioConfigOptions,
  WebClientConfig,
} from "@garazyk/hamownia";

export {
  DEFAULT_ADMIN_PASSWORD,
  DEFAULT_MOCK_TWILIO_PORT,
} from "@garazyk/schemat";

export { repoRoot, serviceUrl } from "@garazyk/schemat/runtime";

import {
  createCharacterRegistry,
  createScenarioConfig,
} from "@garazyk/hamownia";
import type { WebClientConfig } from "@garazyk/hamownia";

const config = createScenarioConfig();

function normalizeHostLoopback(url: string): string {
  return url.replace(/^http:\/\/localhost(?=[:/]|$)/, "http://127.0.0.1")
    .replace(/^ws:\/\/localhost(?=[:/]|$)/, "ws://127.0.0.1")
    .replace(/\/$/, "");
}

const pds1 = normalizeHostLoopback(
  Deno.env.get("PDS_URL") ?? Deno.env.get("ATPROTO_PDS_URL") ?? config.pds1,
);
const pds2 = normalizeHostLoopback(
  Deno.env.get("PDS2_URL") ?? Deno.env.get("ATPROTO_PDS2_URL") ?? config.pds2,
);
const configuredPds3 = Deno.env.get("PDS3_URL") ??
  Deno.env.get("ATPROTO_PDS3_URL");
export const PDS1 = pds1;
export const PDS2 = pds2;
/**
 * Optional third, independently operated PDS used by cross-PDS acceptance
 * scenarios. It is intentionally not aliased to PDS1 or PDS2.
 */
export const PDS3 = configuredPds3
  ? normalizeHostLoopback(configuredPds3)
  : undefined;

export const SERVICE_URLS: Record<string, string> = {
  ...Object.fromEntries(
    Object.entries(config.serviceUrls).map(([key, value]) => [
      key,
      normalizeHostLoopback(value),
    ]),
  ),
  pds: pds1,
  pds2: pds2,
  ...(PDS3 ? { pds3: PDS3 } : {}),
};

export const APPVIEW_ADMIN_SECRET = config.appviewAdminSecret;
export const PDS_ADMIN_PASSWORD = config.pdsAdminPassword;
export const UI_ADMIN_PASSWORD = config.uiAdminPassword;
export const VIDEO_SERVICE_DID = config.videoServiceDid;

export const WEB_CLIENT_TOPOLOGY: WebClientConfig | undefined =
  config.webClientTopology;

let registry = createCharacterRegistry();

export function resetCharacters(): void {
  registry = createCharacterRegistry();
}

export function getActor(name: string) {
  return registry.getActor(name);
}

export function getActorsByRole(role: string) {
  return registry.getActorsByRole(role);
}

export function getActorsByPds(pdsUrl: string) {
  return registry.getActorsByPds(pdsUrl);
}
