"""Instrumentation layer for ATProto scenario scripts.

Provides Prometheus scraping, process monitoring, storage monitoring,
operation timing, and CPU profiling. All monitors use background threads
for non-blocking sampling.

Requires: psutil (pip install psutil)
"""

from __future__ import annotations

import json
import logging
import os
import re
import statistics
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional

import psutil
import requests

logger = logging.getLogger("atproto.instrumentation")

_SAMPLE_INTERVAL = 2.0  # seconds


# ---------------------------------------------------------------------------
# Prometheus text format parser
# ---------------------------------------------------------------------------

def parse_prometheus_text(text: str) -> dict[str, float]:
    """Parse Prometheus exposition text into a flat metric dict.

    Only parses numeric gauges and counters. Histograms and summaries
    are skipped (we scrape the aggregated values from admin endpoints
    instead).

    Returns:
        dict mapping metric_name{label_key="label_val",...} to float value.
    """
    metrics: dict[str, float] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Format: metric_name{label="val",...} value
        match = re.match(r'^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{[^}]*\})?\s+([0-9eE.+-]+)$', line)
        if match:
            name = match.group(1)
            labels = match.group(2) or ""
            value_str = match.group(3)
            key = f"{name}{labels}"
            try:
                metrics[key] = float(value_str)
            except ValueError:
                pass
    return metrics


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------

@dataclass
class MetricsSample:
    """A single snapshot of metrics from one service."""
    timestamp: float
    metrics: dict[str, float]


@dataclass
class MetricsTimeSeries:
    """Time-series data for a single metric."""
    metric_name: str
    samples: list[tuple[float, float]] = field(default_factory=list)

    @property
    def values(self) -> list[float]:
        return [v for _, v in self.samples]

    @property
    def min(self) -> float:
        return min(self.values) if self.values else 0.0

    @property
    def max(self) -> float:
        return max(self.values) if self.values else 0.0

    @property
    def mean(self) -> float:
        return statistics.mean(self.values) if self.values else 0.0

    def percentile(self, p: float) -> float:
        if not self.values:
            return 0.0
        sorted_vals = sorted(self.values)
        idx = int(len(sorted_vals) * p / 100.0)
        idx = min(idx, len(sorted_vals) - 1)
        return sorted_vals[idx]

    @property
    def p50(self) -> float:
        return self.percentile(50)

    @property
    def p95(self) -> float:
        return self.percentile(95)

    @property
    def p99(self) -> float:
        return self.percentile(99)

    def to_dict(self) -> dict[str, Any]:
        return {
            "metric_name": self.metric_name,
            "sample_count": len(self.samples),
            "min": self.min,
            "max": self.max,
            "mean": self.mean,
            "p50": self.p50,
            "p95": self.p95,
            "p99": self.p99,
            "samples": self.samples,
        }


@dataclass
class ProcessSample:
    """A single process sample."""
    timestamp: float
    rss_bytes: int
    vms_bytes: int
    cpu_pct: float
    thread_count: int
    fd_count: int
    disk_read_bytes: int
    disk_write_bytes: int


@dataclass
class ProcessStats:
    """Aggregated process statistics."""
    service_name: str
    pid: int
    samples: list[ProcessSample] = field(default_factory=list)

    @property
    def peak_rss(self) -> int:
        return max((s.rss_bytes for s in self.samples), default=0)

    @property
    def peak_cpu(self) -> float:
        return max((s.cpu_pct for s in self.samples), default=0.0)

    @property
    def avg_cpu(self) -> float:
        vals = [s.cpu_pct for s in self.samples]
        return statistics.mean(vals) if vals else 0.0

    @property
    def final_rss(self) -> int:
        return self.samples[-1].rss_bytes if self.samples else 0

    @property
    def initial_rss(self) -> int:
        return self.samples[0].rss_bytes if self.samples else 0

    @property
    def rss_growth_pct(self) -> float:
        if self.initial_rss == 0:
            return 0.0
        return ((self.final_rss - self.initial_rss) / self.initial_rss) * 100.0

    @property
    def total_disk_read(self) -> int:
        return sum(s.disk_read_bytes for s in self.samples)

    @property
    def total_disk_write(self) -> int:
        return sum(s.disk_write_bytes for s in self.samples)

    def to_dict(self) -> dict[str, Any]:
        return {
            "service_name": self.service_name,
            "pid": self.pid,
            "sample_count": len(self.samples),
            "peak_rss_bytes": self.peak_rss,
            "peak_cpu_pct": self.peak_cpu,
            "avg_cpu_pct": self.avg_cpu,
            "initial_rss_bytes": self.initial_rss,
            "final_rss_bytes": self.final_rss,
            "rss_growth_pct": round(self.rss_growth_pct, 1),
            "total_disk_read_bytes": self.total_disk_read,
            "total_disk_write_bytes": self.total_disk_write,
            "samples": [
                {
                    "timestamp": s.timestamp,
                    "rss_bytes": s.rss_bytes,
                    "vms_bytes": s.vms_bytes,
                    "cpu_pct": s.cpu_pct,
                    "thread_count": s.thread_count,
                    "fd_count": s.fd_count,
                }
                for s in self.samples
            ],
        }


@dataclass
class StorageSample:
    """A single storage sample."""
    timestamp: float
    db_size_bytes: int
    wal_size_bytes: int
    total_bytes: int


@dataclass
class StorageStats:
    """Aggregated storage statistics."""
    label: str
    db_path: str
    samples: list[StorageSample] = field(default_factory=list)

    @property
    def peak_db(self) -> int:
        return max((s.db_size_bytes for s in self.samples), default=0)

    @property
    def peak_wal(self) -> int:
        return max((s.wal_size_bytes for s in self.samples), default=0)

    @property
    def final_db(self) -> int:
        return self.samples[-1].db_size_bytes if self.samples else 0

    @property
    def final_wal(self) -> int:
        return self.samples[-1].wal_size_bytes if self.samples else 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "db_path": self.db_path,
            "sample_count": len(self.samples),
            "peak_db_bytes": self.peak_db,
            "peak_wal_bytes": self.peak_wal,
            "final_db_bytes": self.final_db,
            "final_wal_bytes": self.final_wal,
            "samples": [
                {
                    "timestamp": s.timestamp,
                    "db_size_bytes": s.db_size_bytes,
                    "wal_size_bytes": s.wal_size_bytes,
                    "total_bytes": s.total_bytes,
                }
                for s in self.samples
            ],
        }


@dataclass
class OperationStats:
    """Aggregated statistics for one operation type."""
    name: str
    count: int = 0
    _durations_ns: list[int] = field(default_factory=list)

    def record(self, duration_ns: int) -> None:
        self.count += 1
        self._durations_ns.append(duration_ns)

    @property
    def min_ns(self) -> int:
        return min(self._durations_ns) if self._durations_ns else 0

    @property
    def max_ns(self) -> int:
        return max(self._durations_ns) if self._durations_ns else 0

    @property
    def mean_ns(self) -> int:
        if not self._durations_ns:
            return 0
        return int(statistics.mean(self._durations_ns))

    def percentile_ns(self, p: float) -> int:
        if not self._durations_ns:
            return 0
        sorted_d = sorted(self._durations_ns)
        idx = int(len(sorted_d) * p / 100.0)
        idx = min(idx, len(sorted_d) - 1)
        return sorted_d[idx]

    @property
    def p50_ns(self) -> int:
        return self.percentile_ns(50)

    @property
    def p95_ns(self) -> int:
        return self.percentile_ns(95)

    @property
    def p99_ns(self) -> int:
        return self.percentile_ns(99)

    @property
    def total_ns(self) -> int:
        return sum(self._durations_ns)

    @property
    def throughput_per_sec(self) -> float:
        if not self._durations_ns or self.total_ns == 0:
            return 0.0
        return self.count / (self.total_ns / 1e9)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "count": self.count,
            "min_ms": round(self.min_ns / 1e6, 2),
            "max_ms": round(self.max_ns / 1e6, 2),
            "mean_ms": round(self.mean_ns / 1e6, 2),
            "p50_ms": round(self.p50_ns / 1e6, 2),
            "p95_ms": round(self.p95_ns / 1e6, 2),
            "p99_ms": round(self.p99_ns / 1e6, 2),
            "throughput_per_sec": round(self.throughput_per_sec, 1),
        }


@dataclass
class CpuSample:
    """A single CPU sample."""
    timestamp: float
    user_ms: int
    system_ms: int
    cpu_pct: float


@dataclass
class CpuStats:
    """Aggregated CPU statistics."""
    service_name: str
    samples: list[CpuSample] = field(default_factory=list)

    @property
    def peak_pct(self) -> float:
        return max((s.cpu_pct for s in self.samples), default=0.0)

    @property
    def avg_pct(self) -> float:
        vals = [s.cpu_pct for s in self.samples]
        return statistics.mean(vals) if vals else 0.0

    @property
    def total_user_ms(self) -> int:
        return sum(s.user_ms for s in self.samples)

    @property
    def total_system_ms(self) -> int:
        return sum(s.system_ms for s in self.samples)

    def to_dict(self) -> dict[str, Any]:
        return {
            "service_name": self.service_name,
            "sample_count": len(self.samples),
            "peak_pct": self.peak_pct,
            "avg_pct": self.avg_pct,
            "total_user_ms": self.total_user_ms,
            "total_system_ms": self.total_system_ms,
            "samples": [
                {
                    "timestamp": s.timestamp,
                    "user_ms": s.user_ms,
                    "system_ms": s.system_ms,
                    "cpu_pct": s.cpu_pct,
                }
                for s in self.samples
            ],
        }


@dataclass
class InstrumentationReport:
    """Combined instrumentation report from all monitors."""
    operation_stats: dict[str, OperationStats] = field(default_factory=dict)
    metrics_time_series: dict[str, MetricsTimeSeries] = field(default_factory=dict)
    process_stats: dict[str, ProcessStats] = field(default_factory=dict)
    storage_stats: dict[str, StorageStats] = field(default_factory=dict)
    cpu_stats: dict[str, CpuStats] = field(default_factory=dict)
    phase_timings: dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "operations": {k: v.to_dict() for k, v in self.operation_stats.items()},
            "metrics": {k: v.to_dict() for k, v in self.metrics_time_series.items()},
            "process": {k: v.to_dict() for k, v in self.process_stats.items()},
            "storage": {k: v.to_dict() for k, v in self.storage_stats.items()},
            "cpu": {k: v.to_dict() for k, v in self.cpu_stats.items()},
            "phase_timings": self.phase_timings,
        }

    def write_json(self, path: str | Path) -> str:
        """Write JSON report. Returns the file path."""
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(self.to_dict(), indent=2), encoding="utf-8")
        return str(p)

    def write_html(self, path: str | Path, title: str = "Instrumentation Report") -> str:
        """Write HTML dashboard. Returns the file path."""
        from .dashboard import generate_dashboard_html
        p = Path(path)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(generate_dashboard_html(self, title), encoding="utf-8")
        return str(p)


# ---------------------------------------------------------------------------
# PrometheusScraper
# ---------------------------------------------------------------------------

class PrometheusScraper:
    """Background thread that polls Prometheus/admin metrics endpoints.

    Supports:
    - PDS /metrics (Prometheus text format)
    - Relay /api/relay/metrics (JSON)
    - AppView /admin/appview/metrics/stats (JSON)
    """

    def __init__(
        self,
        endpoints: dict[str, str],
        interval: float = _SAMPLE_INTERVAL,
        headers: dict[str, str] | None = None,
    ):
        """Args:
            endpoints: mapping of service_name -> URL to poll.
            interval: seconds between samples.
            headers: optional HTTP headers (e.g., auth for admin endpoints).
        """
        self._endpoints = endpoints
        self._interval = interval
        self._headers = headers or {}
        self._samples: dict[str, list[MetricsSample]] = {name: [] for name in endpoints}
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> dict[str, MetricsTimeSeries]:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=self._interval * 2)
        return self.get_time_series()

    def get_time_series(self) -> dict[str, MetricsTimeSeries]:
        """Convert collected samples into per-metric time series."""
        result: dict[str, MetricsTimeSeries] = {}
        for service_name, samples in self._samples.items():
            for sample in samples:
                for metric_key, value in sample.metrics.items():
                    if metric_key not in result:
                        result[metric_key] = MetricsTimeSeries(metric_name=metric_key)
                    result[metric_key].samples.append((sample.timestamp, value))
        return result

    def _run(self) -> None:
        session = requests.Session()
        while not self._stop_event.is_set():
            for name, url in self._endpoints.items():
                try:
                    self._scrape_one(session, name, url)
                except Exception as exc:
                    logger.debug("Prometheus scrape failed for %s: %s", name, exc)
            self._stop_event.wait(self._interval)

    def _scrape_one(self, session: requests.Session, name: str, url: str) -> None:
        resp = session.get(url, headers=self._headers, timeout=5)
        now = time.time()
        content_type = resp.headers.get("Content-Type", "")

        if "text/plain" in content_type or "text/version" in content_type or url.endswith("/metrics"):
            # Prometheus text format
            metrics = parse_prometheus_text(resp.text)
        else:
            # JSON format
            try:
                data = resp.json()
                metrics = self._flatten_json_metrics(data)
            except (json.JSONDecodeError, ValueError):
                metrics = {}

        self._samples[name].append(MetricsSample(timestamp=now, metrics=metrics))

    @staticmethod
    def _flatten_json_metrics(
        data: dict[str, Any],
        prefix: str = "",
    ) -> dict[str, float]:
        """Flatten a nested JSON dict into dot-separated metric keys."""
        result: dict[str, float] = {}
        for key, value in data.items():
            full_key = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                result.update(PrometheusScraper._flatten_json_metrics(value, full_key))
            elif isinstance(value, (int, float)):
                result[full_key] = float(value)
            elif isinstance(value, bool):
                result[full_key] = 1.0 if value else 0.0
        return result


# ---------------------------------------------------------------------------
# ProcessMonitor
# ---------------------------------------------------------------------------

class ProcessMonitor:
    """Background thread that samples process stats via psutil.

    Process discovery uses three strategies in order:
    1. PID file: read PIDs from the e2e run directory (binary mode).
    2. psutil binary search: match process name or cmdline against binary names.
    3. Docker container: find containers by compose service label and sample
       via ``docker stats`` (Docker mode).

    If no processes are found for a service, the monitor logs a warning and
    skips that service rather than failing the entire scenario.
    """

    def __init__(
        self,
        service_names: list[str],
        binary_names: list[str],
        interval: float = _SAMPLE_INTERVAL,
        pid_file: str | None = None,
        docker_compose_project: str | None = None,
    ):
        """Args:
            service_names: human-readable names (e.g., "pds", "relay", "appview").
            binary_names: corresponding process binary names for PID lookup.
            interval: seconds between samples.
            pid_file: path to PID file written by setup_local_network.sh.
            docker_compose_project: Docker Compose project name for container lookup.
        """
        self._service_names = service_names
        self._binary_names = binary_names
        self._interval = interval
        self._pid_file = pid_file
        self._docker_compose_project = docker_compose_project
        self._processes: dict[str, psutil.Process] = {}
        self._docker_containers: dict[str, str] = {}  # svc -> container_id
        self._stats: dict[str, ProcessStats] = {}
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._discover_processes()
        missing = set(self._service_names) - set(self._processes.keys()) - set(self._docker_containers.keys())
        if missing:
            logger.warning(
                "ProcessMonitor: could not discover processes for %s; "
                "those services will not have process stats",
                sorted(missing),
            )
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> dict[str, ProcessStats]:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=self._interval * 2)
        return dict(self._stats)

    @property
    def discovered_services(self) -> set[str]:
        """Services that were successfully discovered (process or container)."""
        return set(self._processes.keys()) | set(self._docker_containers.keys())

    def _discover_processes(self) -> None:
        """Find PIDs using PID file, psutil, or Docker container lookup."""
        # Strategy 1: PID file (binary mode)
        self._discover_from_pid_file()

        # Strategy 2: psutil binary-name search (for processes not yet found)
        self._discover_from_psutil()

        # Strategy 3: Docker container discovery (for services not yet found)
        self._discover_from_docker()

    def _discover_from_pid_file(self) -> None:
        """Read PIDs from the e2e run PID file."""
        if not self._pid_file or not os.path.isfile(self._pid_file):
            return

        # Map service names to PID file variable names
        svc_to_var = {
            "pds": "PDS_PID",
            "pds2": "PDS2_PID",
            "relay": "RELAY_PID",
            "appview": "APPVIEW_PID",
            "plc": "PLC_PID",
            "ui": "UI_PID",
        }

        try:
            with open(self._pid_file, "r") as f:
                for line in f:
                    line = line.strip()
                    for svc, var_name in svc_to_var.items():
                        if svc not in self._service_names:
                            continue
                        if line.startswith(f"{var_name}="):
                            try:
                                pid = int(line.split("=", 1)[1])
                                self._processes[svc] = psutil.Process(pid)
                                self._stats[svc] = ProcessStats(
                                    service_name=svc,
                                    pid=pid,
                                )
                                logger.info("ProcessMonitor: found %s from PID file (pid=%d)", svc, pid)
                            except (ValueError, psutil.NoSuchProcess, psutil.AccessDenied) as exc:
                                logger.debug("PID file entry %s failed: %s", line, exc)
                            break
        except OSError as exc:
            logger.debug("Failed to read PID file %s: %s", self._pid_file, exc)

    def _discover_from_psutil(self) -> None:
        """Find PIDs by binary name using psutil.process_iter."""
        missing = [svc for svc in self._service_names if svc not in self._processes]
        if not missing:
            return

        for svc, binary in zip(self._service_names, self._binary_names):
            if svc in self._processes:
                continue
            for proc in psutil.process_iter(["pid", "name", "cmdline"]):
                try:
                    name = proc.info.get("name", "") or ""
                    cmdline = proc.info.get("cmdline") or []
                    cmdline_str = " ".join(cmdline)
                    # Match on binary name appearing in process name or command line.
                    # Also handle macOS where process names may be truncated or
                    # differ from the actual binary filename.
                    if binary in name or binary in cmdline_str:
                        self._processes[svc] = psutil.Process(proc.info["pid"])
                        self._stats[svc] = ProcessStats(
                            service_name=svc,
                            pid=proc.info["pid"],
                        )
                        logger.info("ProcessMonitor: found %s via psutil (pid=%d)", svc, proc.info["pid"])
                        break
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    continue

    def _discover_from_docker(self) -> None:
        """Find Docker containers by compose service label."""
        missing = [svc for svc in self._service_names if svc not in self._processes]
        if not missing:
            return

        # Docker compose service names match our service_names
        compose_svc_map = {
            "pds": "pds",
            "pds2": "pds2",
            "relay": "relay",
            "appview": "appview",
            "plc": "plc",
        }

        try:
            import subprocess
            for svc in missing:
                compose_svc = compose_svc_map.get(svc, svc)
                # Find container by compose service label
                result = subprocess.run(
                    [
                        "docker", "ps",
                        "--filter", f"label=com.docker.compose.service={compose_svc}",
                        "--format", "{{.ID}}",
                    ],
                    capture_output=True, text=True, timeout=5,
                )
                container_id = result.stdout.strip().split("\n")[0] if result.stdout.strip() else None
                if container_id:
                    self._docker_containers[svc] = container_id
                    self._stats[svc] = ProcessStats(
                        service_name=svc,
                        pid=0,  # Docker mode: no host PID
                    )
                    logger.info("ProcessMonitor: found %s via Docker (container=%s)", svc, container_id[:12])
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
            logger.debug("Docker container discovery failed: %s", exc)

    def _run(self) -> None:
        while not self._stop_event.is_set():
            for svc, proc in self._processes.items():
                try:
                    self._sample_one(svc, proc)
                except (psutil.NoSuchProcess, psutil.AccessDenied) as exc:
                    logger.debug("Process sample failed for %s: %s", svc, exc)
            for svc, container_id in self._docker_containers.items():
                try:
                    self._sample_docker(svc, container_id)
                except Exception as exc:
                    logger.debug("Docker sample failed for %s: %s", svc, exc)
            self._stop_event.wait(self._interval)

    def _sample_one(self, svc: str, proc: psutil.Process) -> None:
        mem = proc.memory_info()
        cpu = proc.cpu_percent()
        try:
            threads = proc.num_threads()
        except psutil.AccessDenied:
            threads = 0
        try:
            fds = proc.num_fds() if hasattr(proc, "num_fds") else 0
        except psutil.AccessDenied:
            fds = 0
        try:
            io = proc.io_counters()
            disk_read = io.read_bytes
            disk_write = io.write_bytes
        except (psutil.AccessDenied, AttributeError):
            disk_read = 0
            disk_write = 0

        sample = ProcessSample(
            timestamp=time.time(),
            rss_bytes=mem.rss,
            vms_bytes=mem.vms,
            cpu_pct=cpu,
            thread_count=threads,
            fd_count=fds,
            disk_read_bytes=disk_read,
            disk_write_bytes=disk_write,
        )
        self._stats[svc].samples.append(sample)


# ---------------------------------------------------------------------------
# StorageMonitor
# ---------------------------------------------------------------------------

class StorageMonitor:
    """Background thread that monitors database and WAL file sizes."""

    def __init__(
        self,
        paths: dict[str, list[str]],
        interval: float = _SAMPLE_INTERVAL,
    ):
        """Args:
            paths: mapping of label -> list of file paths to monitor.
                   Each list should contain [db_path, wal_path, ...].
            interval: seconds between samples.
        """
        self._paths = paths
        self._interval = interval
        self._stats: dict[str, StorageStats] = {
            label: StorageStats(label=label, db_path=paths_list[0] if paths_list else "")
            for label, paths_list in paths.items()
        }
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> dict[str, StorageStats]:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=self._interval * 2)
        return dict(self._stats)

    def _run(self) -> None:
        while not self._stop_event.is_set():
            for label, paths_list in self._paths.items():
                try:
                    self._sample_one(label, paths_list)
                except Exception as exc:
                    logger.debug("Storage sample failed for %s: %s", label, exc)
            self._stop_event.wait(self._interval)

    def _sample_one(self, label: str, paths_list: list[str]) -> None:
        db_size = 0
        wal_size = 0
        for path in paths_list:
            try:
                size = os.path.getsize(path)
                if path.endswith("-wal") or path.endswith("-wal"):
                    wal_size += size
                else:
                    db_size += size
            except OSError:
                pass

        sample = StorageSample(
            timestamp=time.time(),
            db_size_bytes=db_size,
            wal_size_bytes=wal_size,
            total_bytes=db_size + wal_size,
        )
        self._stats[label].samples.append(sample)


# ---------------------------------------------------------------------------
# OperationTimer
# ---------------------------------------------------------------------------

class OperationTimer:
    """Records per-operation latency with nanosecond precision.

    Usage:
        timer = OperationTimer()
        with timer.measure("create_post"):
            client.records.create_record(...)
        stats = timer.get_stats("create_post")
    """

    def __init__(self) -> None:
        self._stats: dict[str, OperationStats] = {}

    @contextmanager
    def measure(self, operation: str):
        """Context manager that times an operation."""
        start = time.perf_counter_ns()
        try:
            yield
        finally:
            duration = time.perf_counter_ns() - start
            if operation not in self._stats:
                self._stats[operation] = OperationStats(name=operation)
            self._stats[operation].record(duration)

    def get_stats(self, operation: str) -> OperationStats:
        return self._stats.get(operation, OperationStats(name=operation))

    def get_all_stats(self) -> dict[str, OperationStats]:
        return dict(self._stats)

    def to_dict(self) -> dict[str, Any]:
        return {k: v.to_dict() for k, v in self._stats.items()}


# ---------------------------------------------------------------------------
# CpuProfiler
# ---------------------------------------------------------------------------

class CpuProfiler:
    """Background thread that profiles CPU usage for target processes.

    Uses psutil.Process.cpu_percent() for per-process CPU%.
    """

    def __init__(
        self,
        service_names: list[str],
        processes: dict[str, psutil.Process],
        interval: float = _SAMPLE_INTERVAL,
    ):
        self._service_names = service_names
        self._processes = processes
        self._interval = interval
        self._stats: dict[str, CpuStats] = {
            name: CpuStats(service_name=name) for name in service_names
        }
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None

    def start(self) -> None:
        # Initialize cpu_percent (first call returns 0.0)
        for proc in self._processes.values():
            try:
                proc.cpu_percent()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self) -> dict[str, CpuStats]:
        self._stop_event.set()
        if self._thread:
            self._thread.join(timeout=self._interval * 2)
        return dict(self._stats)

    def _run(self) -> None:
        while not self._stop_event.is_set():
            for name in self._service_names:
                proc = self._processes.get(name)
                if not proc:
                    continue
                try:
                    cpu_pct = proc.cpu_percent()
                    cpu_times = proc.cpu_times()
                    sample = CpuSample(
                        timestamp=time.time(),
                        user_ms=int(cpu_times.user * 1000),
                        system_ms=int(cpu_times.system * 1000),
                        cpu_pct=cpu_pct,
                    )
                    self._stats[name].samples.append(sample)
                except (psutil.NoSuchProcess, psutil.AccessDenied):
                    pass
            self._stop_event.wait(self._interval)


# ---------------------------------------------------------------------------
# Phase timer helper
# ---------------------------------------------------------------------------

class PhaseTimer:
    """Records named phase durations for the instrumentation report."""

    def __init__(self) -> None:
        self._phases: dict[str, float] = {}
        self._current_phase: str | None = None
        self._current_start: float = 0.0

    def start_phase(self, name: str) -> None:
        self._current_phase = name
        self._current_start = time.perf_counter()

    def end_phase(self) -> None:
        if self._current_phase:
            elapsed = time.perf_counter() - self._current_start
            self._phases[self._current_phase] = elapsed
            self._current_phase = None

    def to_dict(self) -> dict[str, float]:
        return {k: round(v, 3) for k, v in self._phases.items()}
