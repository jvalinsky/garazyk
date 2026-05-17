/** Summary cards — shows pass/fail/skip counts with optional label. @module SummaryCards */

interface SummaryCardsProps {
  passed: number;
  failed: number;
  skipped: number;
  label?: string;
}

/** Render pass/fail/skip summary cards. */
export default function SummaryCards({ passed, failed, skipped, label }: SummaryCardsProps) {
  return (
    <div>
      <div class="summary-row">
        <div class="summary-card passed">
          <div class="label">Passed</div>
          <div class="value">{passed}</div>
        </div>
        <div class="summary-card failed">
          <div class="label">Failed</div>
          <div class="value">{failed}</div>
        </div>
        <div class="summary-card skipped">
          <div class="label">Skipped</div>
          <div class="value">{skipped}</div>
        </div>
      </div>
      {label && (
        <div style="margin-top: var(--space-md); font-size: var(--font-size-sm); color: var(--color-text-secondary);">
          {label}
        </div>
      )}
    </div>
  );
}
