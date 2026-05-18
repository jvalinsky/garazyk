# Inventory Matrix — Typing Issues

## @garazyk/gruszka — Grade D
| Area | Count | Severity | ROI |
|------|-------|----------|-----|
| search.ts: `Promise<any>` returns | 7 methods | HIGH | High |
| contact.ts: `Promise<any>` returns | 8 methods | HIGH | High |
| seed.ts: `as any` hiding type mismatch | 1 site | HIGH | High |
| raw.ts: fallback `Promise<any>` → `unknown` | 4 sigs | MEDIUM | Medium |
| raw.ts: `as any` casts in typed branches | 4 sites | MEDIUM | Medium |
| lexicons.ts: unresolved refs | 7 defs | MEDIUM | Medium |
| lexicons.ts: blob `any` annotations | 12 defs | MEDIUM | Medium |
| client.ts: `RawCaller`/`AgentCaller` call() any | 2 sites | LOW | Low |
| lexicons.ts: open-union `Record<string, any>` | 83 defs | LOW (by design) | None |

## @garazyk/narzedzia — Grade A (source), 9 missing types
| Area | Count | Severity | ROI |
|------|-------|----------|-----|
| CLI `*Main` missing `Promise<void>` | 7 fns | MEDIUM | High |
| `lineStartOffsets` missing `number[]` | 1 fn | MEDIUM | High |
| Exit code swallowed in scripts/docs/repo_docs.ts | 1 site | HIGH | High |
| JSON.parse untyped in ops_command.ts | 1 site | LOW | Medium |

## @garazyk/hamownia — Grade C
| Area | Count | Severity | ROI |
|------|-------|----------|-----|
| otel.ts: `any` on tracer/meter/gauge/counter | 7 sites | HIGH | High |
| otel.ts: SpanStatusCode semantic bug | 1 site | MEDIUM | High |
| otel.ts: `as any` on provider.flush/shutdown | 4 sites | MEDIUM | Medium |
| service_command.ts: missing `Promise<void>` | 1 fn | HIGH | High |
| instrumentation.ts: `Record<string, any>` | 1 site | HIGH | Medium |
| run_command.ts: missing return type | 1 fn | HIGH | High |
| run_loop.ts: missing return type | 1 fn | HIGH | High |
| account_discovery.ts: `as unknown[]` | 3 sites | LOW | Low |

## @garazyk/schemat — Grade B
| Area | Count | Severity | ROI |
|------|-------|----------|-----|
| topology_compiler.ts: `any` param | 1 site | MEDIUM | Medium |
| topology_compiler.ts: `Record<string, any>` | 7 sites | MEDIUM | Medium |

## @garazyk/laweta — Grade A
No source-code issues. Test mock casts are acceptable.

## @garazyk/dashboard — Grade A
No source-code issues. Not JSR-published.
