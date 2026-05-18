export {
  Character,
  CharacterRegistry,
  ScenarioConfig,
  ScenarioConfigOptions,
  WebClientConfig,
  createCharacterRegistry,
  createScenarioConfig,
} from "@garazyk/hamownia";

export {
  repoRoot,
  serviceUrl,
} from "@garazyk/schemat/runtime";

const pds1 = (Deno.env.get("PDS_URL") ?? Deno.env.get("ATPROTO_PDS_URL") ?? "http://localhost:2583").replace(/\/$/, "");
const pds2 = (Deno.env.get("PDS2_URL") ?? Deno.env.get("ATPROTO_PDS2_URL") ?? "http://localhost:2587").replace(/\/$/, "");
export const PDS1 = pds1;
export const PDS2 = pds2;

export const SERVICE_URLS: Record<string, string> = {
  pds: pds1,
  pds2: pds2,
  plc: (Deno.env.get("PLC_URL") ?? "http://localhost:2582").replace(/\/$/, ""),
  appview: (Deno.env.get("APPVIEW_URL") ?? "http://localhost:2585").replace(/\/$/, ""),
  relay: (Deno.env.get("RELAY_URL") ?? "http://localhost:2584").replace(/\/$/, ""),
};

export const APPVIEW_ADMIN_SECRET = Deno.env.get("APPVIEW_ADMIN_SECRET") ?? "admin-secret";
export const PDS_ADMIN_PASSWORD = Deno.env.get("PDS_ADMIN_PASSWORD") ?? "admin";
export const VIDEO_SERVICE_DID = Deno.env.get("VIDEO_SERVICE_DID") ?? "did:example:video";
