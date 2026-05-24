# Product

## Register

product

## Users

Developers, protocol implementers, QA engineers, and operators testing local ATProto network stacks. The dashboard must work especially well for Garazyk development, but its mental model should stay generic enough for multiple ATProto service implementations, topologies, and runners.

Users are usually working in a local development environment with service logs, test output, and source code nearby. They need to see whether a full local network is healthy, run scenario suites against it, and understand failures quickly enough to return to code.

## Product Purpose

The scenario dashboard is a control surface for running integration scenarios across a full local ATProto network and triaging the issues those runs expose. It connects topology selection, service lifecycle, scenario execution, live progress, logs, and historical results into one task-focused tool.

Success means a user can answer three questions without hunting: what network am I testing, what is currently running, and where did the failure begin?

## Brand Personality

Tool-native, exacting, and calm.

The dashboard should feel like a serious engineering instrument: dense when density helps diagnosis, quiet when status is normal, and explicit when an action changes the network or test run. It should not feel like marketing, a decorative admin panel, or a generic metrics dashboard.

## Anti-references

- Garazyk-only framing that prevents other ATProto implementations from fitting the model.
- A card-heavy overview that hides relationships between topology, services, scenarios, logs, and failures.
- Controls whose scope is unclear, especially start, stop, restart, topology changes, runner selection, and scenario parameters.
- Status displays that rely on color alone or scatter related state across unrelated panels.
- Modal-first configuration when inline, staged, or panel-based controls would keep context visible.
- Decorative AppKit imitation, hero metrics, gradient text, glass effects, and ornamental motion.

## Design Principles

1. Keep the network model visible. Topology, service roles, runner mode, and implementation under test should be obvious before and during every run.
2. Make run state impossible to miss. Starting, running, stopping, failed, completed, and stale states need a consistent vocabulary across toolbar, sidebar, status bar, and detail views.
3. Triage from cause outward. Failed scenarios should lead to the relevant step, service, log line, and topology condition, not just a red count.
4. Treat implementations as swappable. Labels, configuration, health checks, and result views should describe ATProto roles and capabilities before Garazyk-specific names.
5. Put control scope next to controls. Any action that starts services, stops services, changes topology, or launches scenarios should show what it will affect.
6. Use density deliberately. Dense tables, split panes, log viewers, and compact controls are appropriate when they improve comparison and repeated debugging.

## Accessibility & Inclusion

Target WCAG AA at minimum. All controls must be keyboard reachable, focus states must be visible, and critical status cannot depend on color alone. Motion should respect reduced-motion preferences and should communicate state only. Logs, run IDs, service URLs, errors, and command output should remain readable, selectable, and copyable.
