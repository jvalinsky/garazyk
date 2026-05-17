/** Side-effect-light telemetry hooks for Docker primitives. @module telemetry */

/** Attribute value accepted by local telemetry hooks. */
export type MetricAttributeValue = string | number | boolean;

/** Attributes attached to a metric or span event. */
export type MetricAttributes = Record<string, MetricAttributeValue>;

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
  _name: string,
  _attributes?: MetricAttributes,
): Promise<void> {}

/** Record a gauge sample when telemetry is attached by an embedding application. */
export async function recordGauge(
  _name: string,
  _value: number,
  _attributes?: MetricAttributes,
): Promise<void> {}

/** Record a counter sample when telemetry is attached by an embedding application. */
export async function recordCounter(
  _name: string,
  _value: number,
  _attributes?: MetricAttributes,
): Promise<void> {}
