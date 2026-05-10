"""HTML dashboard generator for ATProto instrumentation reports.

Produces a self-contained HTML file with inline CSS and inline SVG
sparkline charts. No external dependencies — opens directly in a browser.
"""

from __future__ import annotations

import html
import math
from typing import Any

from .instrumentation import InstrumentationReport


# ---------------------------------------------------------------------------
# SVG sparkline
# ---------------------------------------------------------------------------

def _sparkline_svg(
    values: list[float],
    width: int = 200,
    height: int = 40,
    color: str = "#4a90d9",
    fill_color: str = "#4a90d920",
) -> str:
    """Generate an inline SVG sparkline from a list of numeric values."""
    if not values or len(values) < 2:
        return f'<svg width="{width}" height="{height}"><text x="4" y="{height // 2}" font-size="11" fill="#999">no data</text></svg>'

    n = len(values)
    min_v = min(values)
    max_v = max(values)
    range_v = max_v - min_v if max_v != min_v else 1.0

    # Padding
    pad_x = 2
    pad_y = 4
    plot_w = width - 2 * pad_x
    plot_h = height - 2 * pad_y

    points: list[str] = []
    fill_points: list[str] = []

    for i, v in enumerate(values):
        x = pad_x + (i / (n - 1)) * plot_w
        y = pad_y + plot_h - ((v - min_v) / range_v) * plot_h
        points.append(f"{x:.1f},{y:.1f}")
        fill_points.append(f"{x:.1f},{y:.1f}")

    # Close the fill polygon at the bottom
    fill_points.append(f"{pad_x + plot_w:.1f},{pad_y + plot_h:.1f}")
    fill_points.append(f"{pad_x:.1f},{pad_y + plot_h:.1f}")

    polyline = " ".join(points)
    fill_poly = " ".join(fill_points)

    # Min/max labels
    max_label = _format_value(max_v)
    min_label = _format_value(min_v)

    return (
        f'<svg width="{width}" height="{height}" xmlns="http://www.w3.org/2000/svg">'
        f'<polygon points="{fill_poly}" fill="{fill_color}" />'
        f'<polyline points="{polyline}" fill="none" stroke="{color}" stroke-width="1.5" />'
        f'<text x="{width - 4}" y="10" font-size="9" fill="#666" text-anchor="end">{html.escape(max_label)}</text>'
        f'<text x="{width - 4}" y="{height - 2}" font-size="9" fill="#666" text-anchor="end">{html.escape(min_label)}</text>'
        f'</svg>'
    )


def _format_value(v: float) -> str:
    """Format a numeric value for display."""
    if abs(v) >= 1e9:
        return f"{v / 1e9:.1f}G"
    if abs(v) >= 1e6:
        return f"{v / 1e6:.1f}M"
    if abs(v) >= 1e3:
        return f"{v / 1e3:.1f}K"
    if abs(v) < 0.01:
        return f"{v:.4f}"
    return f"{v:.1f}"


def _format_bytes(b: int) -> str:
    """Format a byte count for display."""
    if b >= 1 << 30:
        return f"{b / (1 << 30):.1f} GB"
    if b >= 1 << 20:
        return f"{b / (1 << 20):.1f} MB"
    if b >= 1 << 10:
        return f"{b / (1 << 10):.1f} KB"
    return f"{b} B"


def _format_ms(ns: int) -> str:
    """Format nanoseconds as milliseconds."""
    return f"{ns / 1e6:.1f}ms"


def _latency_color(ms: float, thresholds: tuple[float, float] = (100, 500)) -> str:
    """Return a CSS color based on latency thresholds."""
    if ms <= thresholds[0]:
        return "#2ca02c"  # green
    if ms <= thresholds[1]:
        return "#f5a623"  # yellow/orange
    return "#d0021b"  # red


def _error_rate_color(pct: float) -> str:
    """Return a CSS color based on error rate."""
    if pct <= 0.1:
        return "#2ca02c"
    if pct <= 1.0:
        return "#f5a623"
    return "#d0021b"


# ---------------------------------------------------------------------------
# HTML generation
# ---------------------------------------------------------------------------

_CSS = """
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    max-width: 1200px;
    margin: 0 auto;
    padding: 20px;
    background: #fafafa;
    color: #333;
}
h1 { color: #1a1a1a; border-bottom: 2px solid #4a90d9; padding-bottom: 8px; }
h2 { color: #2c3e50; margin-top: 32px; }
.card {
    background: white;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 16px 20px;
    margin: 8px 0;
    box-shadow: 0 1px 3px rgba(0,0,0,0.06);
}
.cards { display: flex; flex-wrap: wrap; gap: 12px; }
.cards .card { flex: 1 1 200px; min-width: 200px; }
.card .label { font-size: 12px; color: #888; text-transform: uppercase; letter-spacing: 0.5px; }
.card .value { font-size: 28px; font-weight: 600; margin-top: 4px; }
table {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0;
    background: white;
    border: 1px solid #e0e0e0;
    border-radius: 6px;
    overflow: hidden;
}
th { background: #f5f7fa; text-align: left; padding: 10px 14px; font-size: 12px; text-transform: uppercase; color: #666; }
td { padding: 8px 14px; border-top: 1px solid #eee; font-size: 13px; }
tr:hover td { background: #f9fafb; }
.sparkline-cell svg { display: block; }
.phase-tag {
    display: inline-block;
    background: #e8f0fe;
    color: #1a73e8;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 12px;
    margin: 2px;
}
.footer { margin-top: 40px; padding-top: 12px; border-top: 1px solid #ddd; font-size: 12px; color: #999; }
"""


def _summary_card(label: str, value: str, color: str = "#1a1a1a") -> str:
    return (
        f'<div class="card">'
        f'<div class="label">{html.escape(label)}</div>'
        f'<div class="value" style="color:{color}">{html.escape(value)}</div>'
        f'</div>'
    )


def _generate_operations_section(report: InstrumentationReport) -> str:
    """Generate the operation latency table."""
    if not report.operation_stats:
        return "<h2>Operation Latency</h2><p>No operations recorded.</p>"

    rows = []
    for name, stats in sorted(report.operation_stats.items()):
        p95_ms = stats.p95_ns / 1e6
        color = _latency_color(p95_ms)
        rows.append(
            f"<tr>"
            f'<td><strong>{html.escape(name)}</strong></td>'
            f"<td>{stats.count}</td>"
            f"<td>{_format_ms(stats.min_ns)}</td>"
            f"<td>{_format_ms(stats.mean_ns)}</td>"
            f"<td>{_format_ms(stats.p50_ns)}</td>"
            f'<td style="color:{color};font-weight:600">{_format_ms(stats.p95_ns)}</td>'
            f"<td>{_format_ms(stats.p99_ns)}</td>"
            f"<td>{_format_ms(stats.max_ns)}</td>"
            f"<td>{stats.throughput_per_sec:.1f}/s</td>"
            f"</tr>"
        )

    return (
        "<h2>Operation Latency</h2>"
        "<table>"
        "<tr><th>Operation</th><th>Count</th><th>Min</th><th>Mean</th><th>p50</th><th>p95</th><th>p99</th><th>Max</th><th>Throughput</th></tr>"
        + "".join(rows)
        + "</table>"
    )


def _generate_process_section(report: InstrumentationReport) -> str:
    """Generate the process monitoring section with RSS sparklines."""
    if not report.process_stats:
        return "<h2>Process Monitoring</h2><p>No process data collected.</p>"

    sections = []
    for name, stats in sorted(report.process_stats.items()):
        rss_values = [s.rss_bytes for s in stats.samples]
        cpu_values = [s.cpu_pct for s in stats.samples]

        rss_sparkline = _sparkline_svg(rss_values, color="#e74c3c", fill_color="#e74c3c20")
        cpu_sparkline = _sparkline_svg(cpu_values, color="#3498db", fill_color="#3498db20")

        sections.append(
            f'<div class="card" style="flex:1 1 500px">'
            f'<h3>{html.escape(name)} (pid {stats.pid})</h3>'
            f'<table>'
            f"<tr><th>Metric</th><th>Value</th><th>Sparkline</th></tr>"
            f'<tr><td>Peak RSS</td><td>{_format_bytes(stats.peak_rss)}</td>'
            f'<td class="sparkline-cell" rowspan="2">{rss_sparkline}</td></tr>'
            f'<tr><td>RSS Growth</td><td>{stats.rss_growth_pct:.1f}%</td></tr>'
            f'<tr><td>Peak CPU</td><td>{stats.peak_cpu:.1f}%</td>'
            f'<td class="sparkline-cell" rowspan="2">{cpu_sparkline}</td></tr>'
            f'<tr><td>Avg CPU</td><td>{stats.avg_cpu:.1f}%</td></tr>'
            f'<tr><td>Peak Threads</td><td>{max((s.thread_count for s in stats.samples), default=0)}</td><td></td></tr>'
            f'<tr><td>Peak FDs</td><td>{max((s.fd_count for s in stats.samples), default=0)}</td><td></td></tr>'
            f'<tr><td>Disk Read</td><td>{_format_bytes(stats.total_disk_read)}</td><td></td></tr>'
            f'<tr><td>Disk Write</td><td>{_format_bytes(stats.total_disk_write)}</td><td></td></tr>'
            f"</table>"
            f"</div>"
        )

    return (
        "<h2>Process Monitoring</h2>"
        f'<div class="cards">'
        + "".join(sections)
        + "</div>"
    )


def _generate_storage_section(report: InstrumentationReport) -> str:
    """Generate the storage monitoring section."""
    if not report.storage_stats:
        return "<h2>Storage</h2><p>No storage data collected.</p>"

    rows = []
    for name, stats in sorted(report.storage_stats.items()):
        db_values = [s.db_size_bytes for s in stats.samples]
        wal_values = [s.wal_size_bytes for s in stats.samples]

        db_sparkline = _sparkline_svg(db_values, color="#8e44ad", fill_color="#8e44ad20")
        wal_sparkline = _sparkline_svg(wal_values, color="#e67e22", fill_color="#e67e2220")

        rows.append(
            f"<tr>"
            f'<td><strong>{html.escape(name)}</strong></td>'
            f"<td>{_format_bytes(stats.final_db)}</td>"
            f"<td>{_format_bytes(stats.peak_db)}</td>"
            f'<td class="sparkline-cell">{db_sparkline}</td>'
            f"<td>{_format_bytes(stats.final_wal)}</td>"
            f"<td>{_format_bytes(stats.peak_wal)}</td>"
            f'<td class="sparkline-cell">{wal_sparkline}</td>'
            f"</tr>"
        )

    return (
        "<h2>Storage</h2>"
        "<table>"
        "<tr><th>Service</th><th>DB Size</th><th>Peak DB</th><th>DB Trend</th>"
        "<th>WAL Size</th><th>Peak WAL</th><th>WAL Trend</th></tr>"
        + "".join(rows)
        + "</table>"
    )


def _generate_metrics_section(report: InstrumentationReport) -> str:
    """Generate the Prometheus metrics section."""
    if not report.metrics_time_series:
        return "<h2>Service Metrics</h2><p>No metrics collected.</p>"

    rows = []
    for name, ts in sorted(report.metrics_time_series.items()):
        values = ts.values
        sparkline = _sparkline_svg(values, color="#27ae60", fill_color="#27ae6020")
        rows.append(
            f"<tr>"
            f'<td style="font-family:monospace;font-size:12px">{html.escape(name)}</td>'
            f"<td>{len(ts.samples)}</td>"
            f"<td>{_format_value(ts.min)}</td>"
            f"<td>{_format_value(ts.p50)}</td>"
            f"<td>{_format_value(ts.p95)}</td>"
            f"<td>{_format_value(ts.max)}</td>"
            f'<td class="sparkline-cell">{sparkline}</td>'
            f"</tr>"
        )

    return (
        "<h2>Service Metrics</h2>"
        "<table>"
        "<tr><th>Metric</th><th>Samples</th><th>Min</th><th>p50</th><th>p95</th><th>Max</th><th>Trend</th></tr>"
        + "".join(rows)
        + "</table>"
    )


def _generate_cpu_section(report: InstrumentationReport) -> str:
    """Generate the CPU profiling section."""
    if not report.cpu_stats:
        return ""

    rows = []
    for name, stats in sorted(report.cpu_stats.items()):
        cpu_values = [s.cpu_pct for s in stats.samples]
        sparkline = _sparkline_svg(cpu_values, color="#e74c3c", fill_color="#e74c3c20")
        rows.append(
            f"<tr>"
            f'<td><strong>{html.escape(name)}</strong></td>'
            f"<td>{stats.peak_pct:.1f}%</td>"
            f"<td>{stats.avg_pct:.1f}%</td>"
            f"<td>{stats.total_user_ms / 1000:.1f}s</td>"
            f"<td>{stats.total_system_ms / 1000:.1f}s</td>"
            f'<td class="sparkline-cell">{sparkline}</td>'
            f"</tr>"
        )

    return (
        "<h2>CPU Usage</h2>"
        "<table>"
        "<tr><th>Service</th><th>Peak</th><th>Avg</th><th>User</th><th>System</th><th>Trend</th></tr>"
        + "".join(rows)
        + "</table>"
    )


def _generate_phase_section(report: InstrumentationReport) -> str:
    """Generate the phase breakdown section."""
    if not report.phase_timings:
        return ""

    rows = []
    for name, duration in sorted(report.phase_timings.items(), key=lambda x: x[1], reverse=True):
        rows.append(
            f"<tr>"
            f'<td><span class="phase-tag">{html.escape(name)}</span></td>'
            f"<td>{duration:.2f}s</td>"
            f"</tr>"
        )

    return (
        "<h2>Phase Breakdown</h2>"
        "<table>"
        "<tr><th>Phase</th><th>Duration</th></tr>"
        + "".join(rows)
        + "</table>"
    )


def _generate_summary_cards(report: InstrumentationReport) -> str:
    """Generate top-level summary cards."""
    cards = []

    # Total operations
    total_ops = sum(s.count for s in report.operation_stats.values())
    cards.append(_summary_card("Total Operations", f"{total_ops:,}"))

    # p95 latency (worst operation)
    if report.operation_stats:
        worst_p95 = max(s.p95_ns for s in report.operation_stats.values())
        color = _latency_color(worst_p95 / 1e6)
        cards.append(_summary_card("Worst p95 Latency", _format_ms(worst_p95), color))

    # Peak RSS
    if report.process_stats:
        peak_rss = max(s.peak_rss for s in report.process_stats.values())
        cards.append(_summary_card("Peak RSS", _format_bytes(peak_rss)))

    # Peak CPU
    if report.cpu_stats:
        peak_cpu = max(s.peak_pct for s in report.cpu_stats.values())
        cards.append(_summary_card("Peak CPU", f"{peak_cpu:.1f}%"))

    # DB size
    if report.storage_stats:
        final_db = sum(s.final_db for s in report.storage_stats.values())
        cards.append(_summary_card("Total DB Size", _format_bytes(final_db)))

    # WAL size
    if report.storage_stats:
        final_wal = sum(s.final_wal for s in report.storage_stats.values())
        cards.append(_summary_card("Total WAL Size", _format_bytes(final_wal)))

    return f'<div class="cards">{"".join(cards)}</div>'


def generate_dashboard_html(
    report: InstrumentationReport,
    title: str = "Instrumentation Report",
) -> str:
    """Generate a complete self-contained HTML dashboard.

    Args:
        report: The instrumentation report to render.
        title: Page title.

    Returns:
        Complete HTML string.
    """
    body_parts = [
        f"<h1>{html.escape(title)}</h1>",
        _generate_summary_cards(report),
        _generate_phase_section(report),
        _generate_operations_section(report),
        _generate_process_section(report),
        _generate_storage_section(report),
        _generate_cpu_section(report),
        _generate_metrics_section(report),
        '<div class="footer">Generated by Garazyk ATProto Instrumentation</div>',
    ]

    return (
        "<!DOCTYPE html>"
        "<html lang='en'>"
        "<head>"
        f"<title>{html.escape(title)}</title>"
        f"<style>{_CSS}</style>"
        "<meta name='viewport' content='width=device-width, initial-scale=1'>"
        "</head>"
        "<body>"
        + "".join(body_parts)
        + "</body>"
        "</html>"
    )
