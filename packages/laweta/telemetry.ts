/** Side-effect-light telemetry hooks for Docker primitives. @module telemetry */

/** Attribute value accepted by local telemetry hooks. */
export type MetricAttributeValue = string | number | boolean;

/** Attributes attached to a metric or span event. */
export type MetricAttributes = Record<string, MetricAttributeValue>;

interface TelemetryTestHook {
  recordGauge?: (
    name: string,
    value: number,
    attributes?: MetricAttributes,
  ) => void | Promise<void>;
  recordCounter?: (
    name: string,
    value: number,
    attributes?: MetricAttributes,
  ) => void | Promise<void>;
  addSpanEvent?: (
    name: string,
    attributes?: MetricAttributes,
  ) => void | Promise<void>;
}

let telemetryTestHook: TelemetryTestHook | null = null;

/** Install a package-internal telemetry hook for tests. */
export function setTelemetryTestHook(hook: TelemetryTestHook | null): void {
  telemetryTestHook = hook;
}

/** Whether Docker primitive telemetry is enabled for this process. */
export function isOtelEnabled(): boolean {
  return Deno.env.get("OTEL_DENO") === "true" ||
    Deno.env.get("ATPROTO_OTEL") === "true";
}

/** Run an operation, preserving the call shape used by richer telemetry layers. */
export async function withSpan<T>(
  _name: string,
  fn: () => Promise<T> | T,
  _attributes?: MetricAttributes,
): Promise<T> {
  return await fn();
}

/** Record a span event when an embedding application supplies telemetry elsewhere. */
export async function addSpanEvent(
  name: string,
  attributes?: MetricAttributes,
): Promise<void> {
  await telemetryTestHook?.addSpanEvent?.(name, attributes);
}

/** Record a gauge sample when telemetry is attached by an embedding application. */
export async function recordGauge(
  name: string,
  value: number,
  attributes?: MetricAttributes,
): Promise<void> {
  await telemetryTestHook?.recordGauge?.(name, value, attributes);
}

/** Record a counter sample when telemetry is attached by an embedding application. */
export async function recordCounter(
  name: string,
  value: number,
  attributes?: MetricAttributes,
): Promise<void> {
  await telemetryTestHook?.recordCounter?.(name, value, attributes);
}
