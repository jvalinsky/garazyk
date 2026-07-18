# docs-site

Static documentation site for Garazyk, generated with
[Astro](https://astro.build) + [Starlight](https://starlight.astro.build).
The content covers building an ATProto Personal Data Server in Objective-C
under [Garazyk/](../), grouped into six sections: fundamentals, core
infrastructure, architecture, ATProto, auth, and federation. Starlight reads
`.md`/`.mdx` files from `src/content/docs/` and exposes each as a route.

The navigation structure and sidebar are defined in
[astro.config.mjs](./astro.config.mjs).

## Run

From this directory:

```sh
npm install
npm run dev       # dev server at http://localhost:4321
npm run build     # production build into ./dist
npm run preview
```

For repo-wide documentation tooling (link validation, registry generation,
orchestration), see [`scripts/docs/`](../../scripts/docs/README.md).
