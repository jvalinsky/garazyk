/** Single step row — displays step name, status icon, duration, and optional detail. @module StepRow */
import { ScenarioStatus } from "../services/types.ts";
import { formatDurationMs, STATUS_ICONS } from "../utils.ts";

/** Props for the StepRow component. */
interface StepRowProps {
  name: string;
  status: ScenarioStatus;
  detail?: string;
  durationMs?: number;
}

/** Render a single step row with status icon, name, and duration. */
export default function StepRow({ name, status, detail, durationMs }: StepRowProps) {
  return (
    <>
      <div class="step-row">
        <span class={`step-icon ${status}`}>{STATUS_ICONS[status]}</span>
        <span class="step-name">{name}</span>
        <span class="step-duration">{durationMs ? formatDurationMs(durationMs) : ""}</span>
      </div>
      {detail && <div class="step-detail">{detail}</div>}
    </>
  );
}
