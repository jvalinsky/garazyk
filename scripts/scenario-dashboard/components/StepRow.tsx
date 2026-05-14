import { ScenarioStatus } from "../services/types.ts";
import { STATUS_ICONS, formatDurationMs } from "../utils.ts";

interface StepRowProps {
  name: string;
  status: ScenarioStatus;
  detail?: string;
  durationMs?: number;
}

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
