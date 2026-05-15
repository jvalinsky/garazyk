---
title: Alerting
---

# Alerting

Garazyk PDS uses Prometheus and Alertmanager for monitoring. This guide covers alert rules, thresholds, and notification routing.

## Principles

Alert on user-facing symptoms. Internal causes like exhausted database pools are diagnostic details for incident response, but the primary alert should trigger when a user experiences failures.

Every alert must be actionable. If an event does not require immediate intervention, it belongs on a dashboard rather than in an alert notification.

## Categories

- **Critical:** Requires immediate response. Triggers when the service is down, error rates exceed 5%, or data loss is imminent.
- **Warning:** Requires attention but can wait for business hours. Triggers on elevated error rates (1-5%), performance degradation, or high disk usage (>80%).
- **Informational:** Logs noteworthy events like deployments or scheduled maintenance without paging.

## Prometheus Alert Rules

Configure rules in your Prometheus instance to monitor service health.

### Availability and Errors

```yaml
groups:
  - name: pds_availability
    rules:
      - alert: PDSDown
        expr: up{job="garazyk-pds"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PDS instance is down"
          description: "{{ $labels.instance }} has been unreachable for 1 minute."

      - alert: PDSHighErrorRate
        expr: |
          (rate(pds_http_responses_total{status=~"5.."}[5m]) / 
           rate(pds_http_responses_total[5m])) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate"
          description: "Error rate is {{ $value | humanizePercentage }} (threshold: 5%)"
```

### Performance

```yaml
  - name: pds_performance
    rules:
      - alert: PDSHighLatency
        expr: |
          histogram_quantile(0.95, rate(pds_http_request_duration_seconds_bucket[5m])) > 2.0
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High request latency"
          description: "P95 latency is {{ $value }}s (threshold: 2s)"
```

### Resource Usage

```yaml
  - name: pds_resources
    rules:
      - alert: PDSDiskSpaceCritical
        expr: |
          (pds_blob_storage_bytes + pds_database_size_bytes) / (100 * 1024 * 1024 * 1024) > 0.95
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Disk space critical"
          description: "Disk usage exceeds 95%"
```

## Notification Routing

Alertmanager handles notification delivery.

```yaml
route:
  group_by: ['alertname', 'instance']
  group_wait: 10s
  repeat_interval: 12h
  receiver: 'slack'
  routes:
    - match:
        severity: critical
      receiver: 'pagerduty'

receivers:
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<key>'
  - name: 'slack'
    slack_configs:
      - api_url: '<url>'
        channel: '#ops-alerts'
```

## Threshold Guidelines

| Metric | Warning | Critical |
|--------|---------|----------|
| Error rate | 1% | 5% |
| P95 latency | 2x baseline | 5x baseline |
| Disk usage | 80% | 95% |
| Memory usage | 80% | 90% |

## Runbooks

Every alert should link to a resolution procedure.

### PDSDown
1. Check process status: `ps aux | grep kaszlak`
2. Inspect logs: `tail -f /var/log/pds/server.log`
3. Restart service: `docker compose restart pds`

### PDSHighErrorRate
1. Check error types: `grep ERROR /var/log/pds/server.log`
2. Verify database connectivity: `sqlite3 data/service.db "SELECT 1"`
3. Check for external dependency failures (Relay/PLC).

## Related

- [Metrics Collection](./metrics-collection)
- [Logging Strategy](./logging-strategy)
- [Troubleshooting](./troubleshooting)
- [Documentation Map](./documentation-map)

