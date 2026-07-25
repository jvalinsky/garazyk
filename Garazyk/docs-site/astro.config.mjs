// @ts-check
import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

// https://astro.build/config
export default defineConfig({
  integrations: [
    starlight({
      title: "Build Your Own PDS in Obj-C",
      description:
        "A comprehensive deep dive into implementing an ATProto PDS from scratch in Objective-C.",
      customCss: ["./src/custom.css"],
      social: [
        { icon: "github", label: "GitHub", href: "https://github.com/jvalinsky/garazyk" },
      ],
      sidebar: [
        {
          label: "1. Fundamentals",
          items: [{ autogenerate: { directory: "fundamentals" } }],
        },
        {
          label: "2. Core Server Infrastructure",
          items: [{ autogenerate: { directory: "core-server" } }],
        },
        {
          label: "3. Advanced Architecture & Defenses",
          items: [{ autogenerate: { directory: "advanced-parsing" } }],
        },
        {
          label: "4. Implementing ATProto",
          items: [{ autogenerate: { directory: "atproto" } }],
        },
        {
          label: "5. Authentication & Keys",
          items: [{ autogenerate: { directory: "auth" } }],
        },
        {
          label: "6. Federation & Realtime",
          items: [{ autogenerate: { directory: "federation" } }],
        },
      ],
    }),
  ],
});
