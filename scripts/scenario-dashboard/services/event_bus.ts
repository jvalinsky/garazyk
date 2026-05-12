/**
 * Typed event bus for live dashboard updates.
 * Used to broadcast scenario step completions, run status changes,
 * and service health events to WebSocket clients.
 */

export interface StepCompleteEvent {
  type: "step_complete";
  runId: string;
  scenarioId: string;
  step: { name: string; status: string; detail: string; durationMs: number };
}

export interface ScenarioCompleteEvent {
  type: "scenario_complete";
  runId: string;
  scenarioId: string;
  result: { name: string; passed: number; failed: number; skipped: number; ok: boolean };
}

export interface RunCompleteEvent {
  type: "run_complete";
  runId: string;
  summary: { passed: number; failed: number; skipped: number; total: number; ok: boolean };
}

export interface ServiceStatusEvent {
  type: "service_status";
  service: string;
  status: string;
  healthy?: boolean;
}

export interface ServiceLogEvent {
  type: "service_log";
  service: string;
  line: string;
}

export type DashboardEvent =
  | StepCompleteEvent
  | ScenarioCompleteEvent
  | RunCompleteEvent
  | ServiceStatusEvent
  | ServiceLogEvent;

type Listener = (event: DashboardEvent) => void;

export class EventBus {
  private listeners: Set<Listener> = new Set();

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  emit(event: DashboardEvent): void {
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch {
        // Swallow errors in listeners
      }
    }
  }
}

/** Global event bus singleton */
export const eventBus = new EventBus();
