/**
 * OpenTelemetry wrapper for the Garazyk test harness.
 *
 * Uses Deno's built-in OTel support (stable since Deno 2.4) plus
 * `@opentelemetry/api` for custom span creation. When `OTEL_DENO` is
 * not set, all operations are no-ops — zero overhead.
 *
 * Deno's built-in OTel automatically instruments:
 *   - Outgoing `fetch()` calls
 *   - Incoming `Deno.serve` handlers
 *   - `console.*` logs
 *
 * This module adds:
 *   - Custom spans for Docker API calls
 *   - Custom spans for scenario execution
 *   - Graceful shutdown to flush pending spans
 *
 * @module otel
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

import type {
  Counter,
  Exception,
  Gauge,
  Meter,
  Span,
  Tracer,
} from "@opentelemetry/api";

/** Local SpanStatusCode constants (avoids runtime import of OTel API when disabled). */
const OTEL_STATUS = { UNSET: 0, OK: 1, ERROR: 2 } as const;

/** Minimal interface for SDK provider flush/shutdown. */
interface SdkProvider {
  forceFlush(): Promise<void>;
  shutdown(): Promise<void>;
}

export interface TracingConfig {
  /** Service name for OTel resource attributes. */
  serviceName: string;
  /** OTLP endpoint (e.g. "http://localhost:4318"). */
  endpoint?: string;
  /** Additional resource attributes. */
  resourceAttributes?: Record<string, string>;
  /** OTLP protocol. Default: "http/protobuf". */
  protocol?: "http/protobuf" | "http/json" | "grpc";
}

// ---------------------------------------------------------------------------
// Lazy-loaded OpenTelemetry API
// ---------------------------------------------------------------------------

let _tracer: Tracer | null = null;
let _meter: Meter | null = null;
let _initialized = false;
let _config: TracingConfig | null = null;

/**
 * The OpenTelemetry Tracer instance.
 *
 * Returns a no-op tracer when OTel is not enabled.
 */
async function getTracer(): Promise<Tracer> {
  if (_tracer) return _tracer;
  if (!isOtelEnabled()) return noopTracer;
  try {
    const api = await import("@opentelemetry/api");
    _tracer = api.trace.getTracer("garazyk-e2e", "0.1.0");
    return _tracer;
  } catch {
    return noopTracer;
  }
}

/**
 * The OpenTelemetry Meter instance.
 *
 * Returns a no-op meter when OTel is not enabled.
 */
async function getMeter(): Promise<Meter> {
  if (_meter) return _meter;
  if (!isOtelEnabled()) return noopMeter;
  try {
    const api = await import("@opentelemetry/api");
    _meter = api.metrics.getMeter("garazyk-e2e", "0.1.0");
    return _meter;
  } catch {
    return noopMeter;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Check if OpenTelemetry is enabled.
 *
 * OTel is enabled when `OTEL_DENO=true` or `OTEL_DENO=1` is set in the
 * environment. This is the standard Deno OTel activation mechanism.
 */
export function isOtelEnabled(): boolean {
  const val = Deno.env.get("OTEL_DENO");
  return val === "true" || val === "1";
}

/**
 * Initialize OpenTelemetry tracing.
 *
 * Configures the OTLP exporter endpoint and service name for the
 * `@opentelemetry/api` manual span path. This should be called once
 * at program startup, before any traced operations.
 *
 * **Important:** `OTEL_DENO` must be set before the Deno process
 * starts (e.g. `OTEL_DENO=true deno run ...`). Setting it via
 * `Deno.env.set()` after startup has no effect on Deno's built-in
 * OTel pipeline — only the manual `@opentelemetry/api` import path
 * will work.
 *
 * @param config - Tracing configuration
 * @returns true if OTel was successfully initialized
 */
export function initTracing(config: TracingConfig): boolean {
  _config = config;

  // Warn if OTEL_DENO is not set — Deno's built-in OTel won't activate
  if (!Deno.env.get("OTEL_DENO")) {
    console.warn(
      "[otel] OTEL_DENO is not set. Deno's built-in OTel pipeline will not activate.",
      "Set OTEL_DENO=true before process start for full instrumentation.",
      "Only manual @opentelemetry/api spans will be created.",
    );
  }

  // Set service name
  if (config.serviceName) {
    Deno.env.set("OTEL_SERVICE_NAME", config.serviceName);
  }

  // Set OTLP endpoint
  if (config.endpoint) {
    Deno.env.set("OTEL_EXPORTER_OTLP_ENDPOINT", config.endpoint);
  }

  // Set protocol
  if (config.protocol) {
    Deno.env.set("OTEL_EXPORTER_OTLP_PROTOCOL", config.protocol);
  }

  // Set resource attributes
  if (config.resourceAttributes) {
    const existing = Deno.env.get("OTEL_RESOURCE_ATTRIBUTES") || "";
    const attrs = Object.entries(config.resourceAttributes)
      .map(([k, v]) => `${k}=${v}`)
      .join(",");
    Deno.env.set(
      "OTEL_RESOURCE_ATTRIBUTES",
      existing ? `${existing},${attrs}` : attrs,
    );
  }

  _initialized = true;
  return true;
}

/**
 * Initialize OTel for the e2e test harness with sensible defaults.
 *
 * @param serviceName - Service name (e.g. "garazyk-e2e-runner")
 * @returns true if OTel was initialized
 */
export function initE2eTracing(serviceName: string): boolean {
  return initTracing({
    serviceName,
    endpoint: Deno.env.get("OTEL_EXPORTER_OTLP_ENDPOINT") ||
      "http://localhost:4318",
    protocol: "http/protobuf",
    resourceAttributes: {
      "service.version": "dev",
      "deployment.environment": "e2e",
    },
  });
}

/**
 * Create a traced span around an async function.
 *
 * When OTel is enabled, creates a real span with the given name and
 * attributes. When OTel is disabled, calls the function directly with
 * zero overhead.
 *
 * @param name - Span name (e.g. "docker.listContainers")
 * @param fn - Async function to trace
 * @param attributes - Optional span attributes
 * @returns The return value of fn
 * @typeParam T - The async function result type.
 */
export async function withSpan<T>(
  name: string,
  fn: () => Promise<T>,
  attributes?: Record<string, string | number | boolean>,
): Promise<T> {
  if (!isOtelEnabled()) {
    return await fn();
  }

  const tracer = await getTracer();
  return await tracer.startActiveSpan(
    name,
    { attributes },
    async (span: Span) => {
      try {
        const result = await fn();
        span.setStatus({ code: OTEL_STATUS.OK });
        return result;
      } catch (err) {
        span.setStatus({
          code: OTEL_STATUS.ERROR,
          message: err instanceof Error ? err.message : String(err),
        });
        span.recordException(err as Exception);
        throw err;
      } finally {
        span.end();
      }
    },
  );
}

/**
 * Add an attribute to the currently active span.
 *
 * No-op when OTel is not enabled.
 */
export async function addSpanAttribute(
  key: string,
  value: string | number | boolean,
): Promise<void> {
  if (!isOtelEnabled()) return;
  try {
    const api = await import("@opentelemetry/api");
    const span = api.trace.getActiveSpan();
    if (span) {
      span.setAttribute(key, value);
    }
  } catch {
    // OTel API not available
  }
}

/**
 * Add an event to the currently active span.
 *
 * No-op when OTel is not enabled.
 */
export async function addSpanEvent(
  name: string,
  attributes?: Record<string, string | number | boolean>,
): Promise<void> {
  if (!isOtelEnabled()) return;
  try {
    const api = await import("@opentelemetry/api");
    const span = api.trace.getActiveSpan();
    if (span) {
      span.addEvent(name, attributes);
    }
  } catch {
    // OTel API not available
  }
}

/**
 * Shutdown tracing and flush pending spans.
 *
 * Should be called before process exit to ensure all spans are
 * exported to the OTLP backend.
 */
export async function shutdownTracing(): Promise<void> {
  if (!_initialized || !isOtelEnabled()) return;

  // Try to flush pending spans via the OpenTelemetry SDK.
  // Deno's built-in OTel handles flush on process exit when
  // OTEL_DENO is set, but explicit shutdown gives us control
  // over timing and error reporting.
  try {
    const api = await import("@opentelemetry/api");
    const provider = api.trace.getTracerProvider();
    if (typeof (provider as unknown as SdkProvider).forceFlush === "function") {
      await Promise.race([
        (provider as unknown as SdkProvider).forceFlush(),
        new Promise<void>((resolve) => setTimeout(resolve, 2000)),
      ]);
    } else if (
      typeof (provider as unknown as SdkProvider).shutdown === "function"
    ) {
      await Promise.race([
        (provider as unknown as SdkProvider).shutdown(),
        new Promise<void>((resolve) => setTimeout(resolve, 2000)),
      ]);
    }
  } catch {
    // SDK not available or flush failed — Deno's built-in OTel
    // will flush on process exit anyway.
  }
}

/**
 * Get the current tracing configuration.
 */
export function getTracingConfig(): TracingConfig | null {
  return _config;
}

// ---------------------------------------------------------------------------
// Metrics API
// ---------------------------------------------------------------------------

/** Key-value attributes attached to metric observations. */
export interface MetricAttributes {
  [key: string]: string | number | boolean;
}

/**
 * Record a gauge observation (point-in-time value).
 *
 * Gauges are used for values like CPU %, memory usage, or PIDs count
 * that represent a measurement at a specific moment.
 *
 * No-op when OTel is not enabled.
 */
export async function recordGauge(
  name: string,
  value: number,
  attributes?: MetricAttributes,
): Promise<void> {
  if (!isOtelEnabled()) return;
  try {
    const meter = await getMeter();
    const gauge = meter.createGauge(name, {
      description: `Gauge: ${name}`,
    });
    gauge.record(value, attributes);
  } catch {
    // OTel API not available
  }
}

/**
 * Record a counter observation (cumulative value).
 *
 * Counters are used for values like network bytes, OOM failcnt,
 * or block I/O bytes that only increase over time.
 *
 * No-op when OTel is not enabled.
 */
export async function recordCounter(
  name: string,
  value: number,
  attributes?: MetricAttributes,
): Promise<void> {
  if (!isOtelEnabled()) return;
  try {
    const meter = await getMeter();
    const counter = meter.createCounter(name, {
      description: `Counter: ${name}`,
    });
    counter.add(value, attributes);
  } catch {
    // OTel API not available
  }
}

/**
 * Create a named gauge instrument for repeated observations.
 *
 * Returns the instrument directly so callers can call `.record()`
 * without re-creating the instrument each time.
 *
 * No-op when OTel is not enabled.
 */
export async function createGauge(
  name: string,
  description?: string,
): Promise<Gauge> {
  if (!isOtelEnabled()) return noopInstrument;
  try {
    const meter = await getMeter();
    return meter.createGauge(name, { description });
  } catch {
    return noopInstrument;
  }
}

/**
 * Create a named counter instrument for repeated observations.
 *
 * Returns the instrument directly so callers can call `.add()`
 * without re-creating the instrument each time.
 *
 * No-op when Otel is not enabled.
 */
export async function createCounter(
  name: string,
  description?: string,
): Promise<Counter> {
  if (!isOtelEnabled()) return noopInstrument;
  try {
    const meter = await getMeter();
    return meter.createCounter(name, { description });
  } catch {
    return noopInstrument;
  }
}

// ---------------------------------------------------------------------------
// No-op tracer (used when OTel is disabled)
// ---------------------------------------------------------------------------

const noopTracer = {
  startActiveSpan(
    _name: string,
    _opts: unknown,
    fn?: (span: Span) => unknown,
  ): unknown {
    const noopSpan = {
      setStatus() {},
      setAttribute() {},
      addEvent() {},
      recordException() {},
      end() {},
      isRecording() {
        return false;
      },
      updateName() {},
      getContext() {
        return { traceId: "", spanId: "", traceFlags: 0, isRemote: false };
      },
      spanContext() {
        return { traceId: "", spanId: "", traceFlags: 0, isRemote: false };
      },
    } as unknown as Span;
    if (typeof _opts === "function") {
      return (_opts as (span: Span) => unknown)(noopSpan);
    }
    return fn!(noopSpan);
  },
} as unknown as Tracer;

const noopMeter = {
  createGauge(_name: string, _opts?: unknown): Counter & Pick<Gauge, "record"> {
    return noopInstrument;
  },
  createCounter(_name: string, _opts?: unknown): Counter {
    return noopInstrument;
  },
  createHistogram(_name: string, _opts?: unknown) {
    return noopInstrument;
  },
  createUpDownCounter(_name: string, _opts?: unknown) {
    return noopInstrument;
  },
} as unknown as Meter;

const noopInstrument = {
  record(_value: number, _attrs?: Record<string, string | number | boolean>) {},
  add(_value: number, _attrs?: Record<string, string | number | boolean>) {},
} as unknown as Counter & Pick<Gauge, "record">;
