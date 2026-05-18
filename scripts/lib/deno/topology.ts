export * from "@garazyk/schemat";
import { TopologyRegistry } from "@garazyk/schemat";
import type { WebClientTopology } from "@garazyk/schemat";

export const WEB_CLIENT_PRESETS: Record<string, WebClientTopology> = new Proxy(
  {} as Record<string, WebClientTopology>,
  {
    get(_target, name: string) {
      return TopologyRegistry.getWebClient(name);
    },
    ownKeys() {
      return TopologyRegistry.listWebClients();
    },
    getOwnPropertyDescriptor(_target, name: string) {
      const client = TopologyRegistry.getWebClient(name);
      if (client) {
        return { configurable: true, enumerable: true, value: client };
      }
    },
  },
);
