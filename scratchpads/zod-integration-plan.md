# Detailed Zod Integration Plan for Garażyk

**Objective:** Standardize and expand the use of `zod` across all workspace packages to provide runtime type safety, robust API validation, and schema-driven E2E testing.

---

## 1. `@garazyk/schemat` (Topology / Schematics)
*Focus: Enhancing existing validation and reporting.*

### 1.1 Cross-Service Dependency Validation
- **Action**: Modify `normalizeTopologyPreset` in `topology_schema.ts`.
- **Logic**: After the Zod `safeParse` of the top-level object, implement a `.superRefine` or a post-parse pass that:
    - Iterates through all `dependsOn` arrays.
    - Verifies that every target service name exists in the `services` or `sidecars` map.
    - Checks for circular dependencies in the service graph.
- **Outcome**: Catch configuration errors (like typos in dependency names) at the schema level rather than during Docker Compose generation.

### 1.2 Path-Specific Error Formatting
- **Action**: Expand `formatZodError` in `topology_schema.ts`.
- **Logic**: Map Zod's `ZodIssue[]` to more human-readable strings.
    - `invalid_type`: "Expected string for service 'pds' port, but got number."
    - `unrecognized_keys`: "Unknown property 'extra_config' in service 'relay'."
- **Outcome**: A "Compiler-like" experience for topology authors.

---

## 2. `@garazyk/gruszka` (ATProto Client / Concrete Mixer)
*Focus: Automated schema generation from Lexicons.*

### 2.1 Updated Generator Logic (`scripts/generate.ts`)
- **Mapping Table**:
    - `string` -> `z.string()`
    - `integer` -> `z.number().int()`
    - `boolean` -> `z.boolean()`
    - `array` -> `z.array(child)`
    - `object` -> `z.object({ properties })`
    - `union` -> `z.discriminatedUnion('$type', options)`
- **Recursion Support**: For types that can reference themselves (like `app.bsky.feed.defs#postView`), the generator must output `z.lazy(() => schema)`.
- **Custom Scalars**: Create a `scalars.ts` file with:
    - `cidSchema`: `z.string().regex(/^[a-z0-9]+$/)` (or more precise CID regex).
    - `atUriSchema`: `z.string().startsWith('at://')`.
    - `blobSchema`: `z.object({ $type: z.literal('blob'), ref: z.any(), mimeType: z.string(), size: z.number() })`.

### 2.2 File Splitting & Lazy Loading
- **Current Problem**: `lexicons.ts` is 6k lines; Zod will triple this.
- **Strategy**: 
    - Output schemas into a `lexicons/` directory.
    - One file per top-level namespace (e.g., `lexicons/app.bsky.ts`, `lexicons/com.atproto.ts`).
    - Use a "Barrel" file that provides **Getters** for each schema:
      ```typescript
      export const PostSchema = () => import('./app.bsky.ts').then(m => m.Post);
      ```
- **Outcome**: Minimal startup overhead for the client.

---

## 3. `@garazyk/laweta` (Docker Client / Tow Truck)
*Focus: Validating Docker Engine API responses.*

### 3.1 Docker Schema Library (`docker_schemas.ts`)
- **Implement**:
    - `ContainerInspectSchema`: Focus on `State`, `Config.Labels`, and `NetworkSettings`.
    - `DockerEventSchema`: Validate `Action`, `Type`, and `Actor.Attributes`.
    - `ContainerStatsSchema`: Strictly define the nested CPU and Memory usage objects.
- **Integration**:
    - In `docker_api.ts`, modify `request<T>` to optionally accept a Zod schema.
    - If a schema is provided, perform `.parse()` on the response body before returning.

---

## 4. `@garazyk/hamownia` (Scenario Runner / Dynamometer)
*Focus: Schema-driven assertions and diagnostic cleaning.*

### 4.1 New Assertion API (`assertions.ts`)
- **Implement**: `assert.schema(data: unknown, schema: z.ZodSchema, message?: string)`.
- **Error Handling**: On failure, the assertion should format the Zod error and include the first 500 characters of the failing JSON in the `ScenarioResult` log.

### 4.2 Diagnostic "Cleaning"
- **Logic**: When a scenario captures a response for a diagnostic report, it can pass it through a schema's `.strip()` method.
- **Outcome**: Removes ephemeral or irrelevant fields (like internal IDs or debug timestamps) from the report, keeping snapshots stable for regression testing.

---

## 5. Timeline & Verification
1. **Week 1**: Implement `gruszka` generator updates and `hamownia` assertion helpers.
2. **Week 2**: Define `laweta` Docker schemas and enhance `schemat` validation rules.
3. **Verification**:
    - Run `deno task check` to ensure no circular imports were introduced by lazy loading.
    - Create a test lexicon and verify Zod handles its constraints (maxLength, pattern).
