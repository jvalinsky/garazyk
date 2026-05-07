"""Scenario result reporting for ATProto scenario scripts.

Collects step results, prints a colored terminal summary, and writes
a machine-readable JSON report for CI/agent consumption.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional


class StepStatus(str, Enum):
    PASSED = "passed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class StepResult:
    """Result metadata for one named scenario step.

    detail is written to both the terminal summary and the JSON report, so it
    should describe the observable result rather than internal control flow.
    duration_ms is optional because some scenarios only measure coarse success.
    """

    name: str
    status: StepStatus
    detail: str = ""
    duration_ms: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status.value,
            "detail": self.detail,
            "duration_ms": self.duration_ms,
        }


@dataclass
class ScenarioResult:
    """Collects step results and report output for one scenario run.

    The runner records start/finish timestamps here, then uses ok/exit_code to
    decide the process status. Skipped steps are reported but do not fail the
    scenario; this supports optional service coverage such as firehose or chat.
    """

    scenario_name: str
    steps: list[StepResult] = field(default_factory=list)
    started_at: Optional[float] = None
    finished_at: Optional[float] = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def start(self) -> None:
        self.started_at = time.time()

    def finish(self) -> None:
        self.finished_at = time.time()

    def step(
        self,
        name: str,
        status: StepStatus,
        detail: str = "",
        duration_ms: int = 0,
    ) -> StepResult:
        """Append and return a step result for this scenario."""
        result = StepResult(name=name, status=status, detail=detail, duration_ms=duration_ms)
        self.steps.append(result)
        return result

    def step_passed(self, name: str, detail: str = "", duration_ms: int = 0) -> StepResult:
        return self.step(name, StepStatus.PASSED, detail, duration_ms)

    def step_failed(self, name: str, detail: str = "", duration_ms: int = 0) -> StepResult:
        return self.step(name, StepStatus.FAILED, detail, duration_ms)

    def step_skipped(self, name: str, detail: str = "", duration_ms: int = 0) -> StepResult:
        return self.step(name, StepStatus.SKIPPED, detail, duration_ms)

    @property
    def passed(self) -> int:
        return sum(1 for s in self.steps if s.status == StepStatus.PASSED)

    @property
    def failed(self) -> int:
        return sum(1 for s in self.steps if s.status == StepStatus.FAILED)

    @property
    def skipped(self) -> int:
        return sum(1 for s in self.steps if s.status == StepStatus.SKIPPED)

    @property
    def total(self) -> int:
        return len(self.steps)

    @property
    def ok(self) -> bool:
        """True if no steps failed (skips are OK)."""
        return self.failed == 0

    @property
    def exit_code(self) -> int:
        return 0 if self.ok else 1

    # ── Terminal output ──────────────────────────────────────────────

    def summary(self) -> str:
        """Return a colored terminal summary suitable for human logs."""
        lines = []
        lines.append(f"\n{'='*60}")
        lines.append(f"  Scenario: {self.scenario_name}")
        lines.append(f"{'='*60}")

        for step in self.steps:
            icon = _status_icon(step.status)
            color = _status_color(step.status)
            reset = "\033[0m"
            detail_str = f" — {step.detail}" if step.detail else ""
            lines.append(f"  {color}{icon}{reset} {step.name}{detail_str}")

        lines.append(f"{'-'*60}")
        p_color = "\033[0;32m"
        f_color = "\033[0;31m" if self.failed else ""
        s_color = "\033[1;33m" if self.skipped else ""
        lines.append(
            f"  {p_color}{self.passed} passed{reset}, "
            f"{f_color}{self.failed} failed{reset}, "
            f"{s_color}{self.skipped} skipped{reset} "
            f"({self.total} total)"
        )

        if self.ok:
            lines.append(f"  \033[0;32mRESULT: ALL PASSED\033[0m")
        else:
            lines.append(f"  \033[0;31mRESULT: {self.failed} FAILED\033[0m")

        lines.append(f"{'='*60}")
        return "\n".join(lines)

    def print_summary(self) -> None:
        print(self.summary())

    # ── JSON output ─────────────────────────────────────────────────

    def to_dict(self) -> dict[str, Any]:
        """Return the stable JSON-serializable report structure."""
        return {
            "scenario": self.scenario_name,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
            "duration_s": (
                round(self.finished_at - self.started_at, 2)
                if self.started_at and self.finished_at
                else None
            ),
            "steps": [s.to_dict() for s in self.steps],
            "summary": {
                "passed": self.passed,
                "failed": self.failed,
                "skipped": self.skipped,
                "total": self.total,
            },
            "ok": self.ok,
            "metadata": self.metadata,
        }

    def to_json(self, indent: int = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent)

    def write_report(self, output_dir: str = "reports") -> str:
        """Write JSON report to a file. Returns the file path."""
        os.makedirs(output_dir, exist_ok=True)
        ts = time.strftime("%Y%m%d-%H%M%S", time.gmtime())
        safe_name = self.scenario_name.replace(" ", "_").lower()
        filename = f"{ts}-{safe_name}.json"
        path = os.path.join(output_dir, filename)
        with open(path, "w") as f:
            f.write(self.to_json())
        return path


# ── Helpers ─────────────────────────────────────────────────────────

def _status_icon(status: StepStatus) -> str:
    if status == StepStatus.PASSED:
        return "PASS"
    elif status == StepStatus.FAILED:
        return "FAIL"
    return "SKIP"


def _status_color(status: StepStatus) -> str:
    if status == StepStatus.PASSED:
        return "\033[0;32m"
    elif status == StepStatus.FAILED:
        return "\033[0;31m"
    return "\033[1;33m"
