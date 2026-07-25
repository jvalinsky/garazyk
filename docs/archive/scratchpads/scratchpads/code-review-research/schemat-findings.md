# schemat package research findings

## Query 1: Docker Compose YAML generation

The search results reinforced a familiar but important point: hand-built string concatenation is a poor way to generate YAML. The JavaScript template-literal article called out the core failure modes of concatenation — missing spaces, broken line breaks, and hard-to-read control flow — and those map directly onto YAML generation, where tiny formatting mistakes change semantics. The relevant code-review concern for `schemat` is not just readability; it is data corruption risk. Unquoted env values containing `:`, `#`, leading/trailing whitespace, or newline content can be reinterpreted by YAML parsers, and booleans/null-like strings can be coerced unexpectedly if the emitter is not intentionally preserving strings.

The Docker Compose merge discussion added another important angle: Compose has non-obvious merge rules for environment variables, ports, volumes, and labels. That means generated YAML should stay structural and deterministic, ideally by serializing a typed object model rather than emitting text fragments. For `schemat`, the strongest takeaway is that `renderComposeYaml()` should not rely on ad hoc concatenation or raw `Record<string, any>` objects; it should construct a constrained schema and then use a real YAML serializer so quoting, block scalars, and list/map formatting are handled consistently.

## Query 2: Docker Compose health checks

The healthcheck results support `curl -f` as a reasonable default when the image already includes curl. The accepted answers in the search results consistently used `curl --fail` or `curl -f` for HTTP readiness checks, often with `-sS` to keep noise low while still surfacing errors. They also show that `wget` is a practical alternative on Alpine-based or minimal images, especially when curl is not installed. The broader pattern is: the healthcheck command should be as small and boring as possible, and it should probe a readiness endpoint that reflects actual service availability rather than merely checking that a process exists.

The timing guidance was also consistent: keep the check lightweight, set `interval` to something in the 30s–2m range for most services, use `timeout` that is short enough to fail fast, and add a `start_period` for slower boots. The search results also highlighted a common Compose pitfall: if a healthcheck uses shell operators like pipes or redirects, it must use `CMD-SHELL` or an explicit shell wrapper. For `schemat`, that means `extractContainerPort()` should not silently choose the first published port as the health target; the health port needs to be explicit in the topology definition, and the healthcheck should be generated from that source of truth.

## Query 3: Path traversal in Docker volumes

The path-traversal search results point to a broader security lesson: path safety is about the whole filesystem resolution process, not just string normalization. The mergerfs discussion showed that access can fail or succeed based on permissions on a parent directory higher in the tree, which is a reminder that the effective path seen by the kernel matters. The OWASP Docker Security Cheat Sheet further emphasizes minimizing attack surface, using read-only mounts when possible, and avoiding unsafe host-level exposures. Taken together, these sources suggest that `relative()` plus `startsWith("..")` is not a sufficient security boundary on its own.

For `schemat`, the main code-review concern is that a path normalized in userland can still be subverted by symlinks, mount-point tricks, or time-of-check/time-of-use races if the code later opens or writes the path without re-validating the resolved location. A more robust approach is to validate against a trusted root after realpath resolution, reject symlink escapes, and treat volume writes as a privileged operation that should be tightly scoped. This is especially relevant if `compileTopology()` emits files into directories derived from user-controlled topology fields.

## Query 4: SigNoz OTel stack

The SigNoz material showed a fairly standard Compose pattern for observability stacks: pin image tags, externalize collector config, and pass environment-specific values through `.env` or Compose environment blocks. The examples used explicit version pins such as `signoz/signoz-otel-collector:${OTELCOL_TAG:-0.79.7}` and `gliderlabs/logspout:v3.2.14`, which is a strong signal against using floating `latest`-style tags. They also relied on a mounted OpenTelemetry Collector config file plus environment variables for endpoints and ingestion keys, which keeps deployment-specific values out of image definitions.

The search results also surfaced a subtle but important constraint: the SigNoz stack often uses Docker socket access for log shipping, which is operationally convenient but expands the trust boundary. For `schemat`, the key review concern is that hardcoding SigNoz service topology in `renderSigNozServices()` makes the feature brittle across environments. A better design would allow the OTel collector image tag, collector config path, log shipping mechanism, and any optional socket mounts to be parameterized, with sane defaults but an explicit configuration surface. That would also make version pinning and upgrade planning much easier.

## Query 5: Manifest versioning

The manifest-versioning search results favored additive evolution over disruptive schema replacement. The .NET releases metadata example showed a stable pattern: keep a top-level object for the current or highest version, add a versioned array for the expanded set, and evolve fields in a backward-compatible way whenever possible. The dbt versioning discussion reinforced the same philosophy: one latest version, older pinned versions, deprecation dates, and explicit rules for how consumers migrate. The major lesson is that versioning works best when older readers can safely ignore newer additive fields, and when “latest” stays discoverable without forcing consumers to understand the entire historical matrix.

For `schemat`, this makes a v1/v2 strategy defensible only if the shape changes remain compatible enough that old manifests still parse and newer manifests can be reasoned about deterministically. If v3 is likely, the code should not bake in a two-version special case. Instead, it should use a version registry or discriminated manifest schema with explicit validation and a documented migration path. That reduces the risk that `compileTopology()` or `validatePreset()` accrete one-off branches for each new manifest generation mode.

## Review Checklist

| Code review concern | What the research suggests | What to check in `schemat` |
| --- | --- | --- |
| Manual YAML generation | Hand-built YAML is brittle; quote and escape are easy to get wrong | Prefer typed objects + YAML serializer; verify env values containing `:`, `#`, newlines, booleans, and null-like strings are emitted safely |
| `renderComposeYaml()` uses `Record<string, any>` | Ad hoc objects hide schema mistakes | Replace with stricter types or a manifest model; avoid `any` for service/env/volume definitions |
| `validatePreset()` circular inheritance | Versioned schemas should evolve with explicit validation | Add cycle detection to preset inheritance before any render/write step |
| `extractContainerPort()` picks first port | Health probes should be explicit, not inferred by order | Add a dedicated health-port field or derive from a validated service contract instead of first-match behavior |
| `renderSigNozServices()` hardcodes services | Observability stack should be parameterized and pinned | Make collector image tag, config, and optional sidecars configurable; avoid hidden `latest` assumptions |
| `composeDown()` ignores exit code | Silent cleanup failures hide broken deployments | Propagate non-zero exit status and surface stderr/stdout to the caller |
| `compileTopology()` writes before validation completes | Partial writes can leave invalid or mixed-state output | Validate fully before touching the filesystem; if writes must happen early, write to a temp path and atomically move |
| `roleEnvKey()` implicit mapping | Hidden conventions become untestable and drift-prone | Make role-to-env mapping explicit, validated, and covered by tests |

## Cross-Cutting Concerns

- **Determinism matters across packages.** The same design pressure appears in YAML generation, manifest versioning, and healthcheck generation: once output is derived from a topology definition, it should be reproducible byte-for-byte for the same input.
- **Prefer explicit contracts over inference.** Port selection, role/env naming, and service grouping all become fragile when they are inferred from order or naming conventions instead of declared schema fields.
- **Validate before side effects.** The path traversal and compile/write findings both point to the same architecture rule: complete validation first, then perform filesystem writes or compose execution.
- **Pin runtime dependencies.** The SigNoz results and Compose best practices both argue for pinned image tags and explicit healthcheck commands rather than implicit base-image assumptions.
- **Watch the security boundary around paths and mounts.** Even if `schemat` only emits Compose files, it is still shaping what paths and volumes downstream operators will trust; symlink escapes, parent-directory permissions, and mount semantics deserve defensive treatment.
- **Use versioned schemas as a migration tool, not a special case.** If manifest v3 is plausible, the package should already have a generic version dispatch/validation layer instead of branching logic for “current” vs “next.”

## Notes on evidence quality

The search results were a mix of official docs, issue threads, and Stack Overflow examples. Where a source was opinionated rather than normative, I treated it as a pattern signal rather than a hard rule. The strongest evidence came from recurring themes across multiple sources: use a real serializer, keep health checks lightweight and explicit, pin images, and avoid relying on path strings alone for filesystem safety.
