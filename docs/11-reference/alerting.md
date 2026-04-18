---
title: Alerting
---

# Alerting

This guide covers alerting strategies for Garazyk PDS, including alert rules, thresholds, notification channels, and best practices for production monitoring.

## Overview

Effective alerting helps you:

- **Detect issues early**: Catch problems before users notice
- **Reduce downtime**: Respond quickly to incidents
- **Track SLOs**: Monitor service level objectives
- **Prevent outages**: Identify trends before they become critical
- **On-call efficiency**: Alert on actionable issues only

## Alerting Philosophy

### Alert on Symptoms, Not Causes

**Good**: "API error rate > 5%" (user-facing symptom)  
**Bad**: "Database connection pool exhausted" (internal cause)

Users care about symptoms. Root cause analysis happens during incident response.

### Actionable Alerts Only

Every alert should require human action. If an alert doesn't need immediate response, it's not an alert—it's a dashboard metric.

**Questions to ask**:
- Does this require immediate action?
- Can this wait until business hours?
- Is this already covered by another alert?

### Avoid Alert Fatigue

Too many alerts → ignored alerts → missed incidents

**Strategies**:
- Set appropriate thresholds
- Use alert aggregation
- Implement alert suppression during maintenance
- Review and tune alerts regularly

## Alert Categories

### Critical Alerts (Page Immediately)

Issues requiring immediate response:

- **Service down**: Server not responding
- **High error rate**: > 5% of requests failing
- **Data loss risk**: Database corruption, backup failures
- **Security breach**: Unauthorized access attempts
- **Resource exhaustion**: Disk full, memory exhausted

### Warning Alerts (Notify, Don't Page)

Issues requiring attention but not immediate:

- **Elevated error rate**: 1-5% of requests failing
- **Performance degradation**: P95 latency > 2x baseline
- **Resource pressure**: Disk > 80% full
- **Certificate expiration**: SSL cert expires in < 7 days
- **Backup delays**: Last backup > 24 hours old

### Informational Alerts (Log Only)

Noteworthy events that don't require action:

- **Deployment completed**: New version deployed
- **Scheduled maintenance**: Planned downtime
- **Configuration changes**: Config updated
- **Capacity changes**: Scaled up/down

## Prometheus Alert Rules

Garazyk PDS exports metrics in Prometheus format. Configure alerts in Prometheus:

### Service Availability

```yaml
groups:
  - name: pds_availability
    interval: 30s
    rules:
      - alert: PDSDown
        expr: up{job="garazyk-pds"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PDS instance is down"
          description: "PDS instance {{ $labels.instance }} has been down for more than 1 minute."
          
      - alert: PDSHighErrorRate
        expr: |
          (
            rate(pds_http_responses_total{status=~"5.."}[5m])
            /
            rate(pds_http_responses_total[5m])
          ) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High error rate on PDS"
          description: "Error rate is {{ $value | humanizePercentage }} (threshold: 5%)"
```

### Performance Degradation

```yaml
  - name: pds_performance
    interval: 1m
    rules:
      - alert: PDSHighLatency
        expr: |
          histogram_quantile(0.95,
            rate(pds_http_request_duration_seconds_bucket[5m])
          ) > 2.0
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High request latency on PDS"
          description: "P95 latency is {{ $value }}s (threshold: 2s)"
          
      - alert: PDSSlowDatabaseQueries
        expr: pds_database_query_duration_seconds > 1.0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Slow database queries detected"
          description: "Database queries taking > 1s"
```

### Resource Utilization

```yaml
  - name: pds_resources
    interval: 1m
    rules:
      - alert: PDSDiskSpaceHigh
        expr: |
          (
            pds_blob_storage_bytes + pds_database_size_bytes
          ) / (100 * 1024 * 1024 * 1024) > 0.80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PDS disk usage high"
          description: "Disk usage is {{ $value | humanizePercentage }} (threshold: 80%)"
          
      - alert: PDSDiskSpaceCritical
        expr: |
          (
            pds_blob_storage_bytes + pds_database_size_bytes
          ) / (100 * 1024 * 1024 * 1024) > 0.95
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "PDS disk space critical"
          description: "Disk usage is {{ $value | humanizePercentage }} (threshold: 95%)"
```

### Repository Operations

```yaml
  - name: pds_repository
    interval: 1m
    rules:
      - alert: PDSRepositoryCreationFailed
        expr: |
          rate(pds_repository_creation_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Repository creation failures"
          description: "{{ $value }} repository creation failures per second"
          
      - alert: PDSBlobUploadFailed
        expr: |
          rate(pds_blob_upload_errors_total[5m]) > 1.0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Blob upload failures"
          description: "{{ $value }} blob upload failures per second"
```

### Firehose Health

```yaml
  - name: pds_firehose
    interval: 1m
    rules:
      - alert: PDSFirehoseSubscribersHigh
        expr: pds_firehose_active_subscribers > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High number of firehose subscribers"
          description: "{{ $value }} active subscribers (threshold: 100)"
          
      - alert: PDSFirehoseBackpressure
        expr: pds_firehose_backpressure_events_total > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Firehose experiencing backpressure"
          description: "Backpressure events detected, subscribers may be slow"
```

### Authentication Issues

```yaml
  - name: pds_auth
    interval: 1m
    rules:
      - alert: PDSHighAuthFailureRate
        expr: |
          (
            rate(pds_auth_failures_total[5m])
            /
            rate(pds_auth_attempts_total[5m])
          ) > 0.20
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High authentication failure rate"
          description: "Auth failure rate is {{ $value | humanizePercentage }} (threshold: 20%)"
          
      - alert: PDSPossibleBruteForce
        expr: |
          rate(pds_auth_failures_total[1m]) > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Possible brute force attack"
          description: "{{ $value }} auth failures per second"
```

## Notification Channels

### Alertmanager Configuration

Configure Alertmanager to route alerts to appropriate channels:

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    # Critical alerts go to PagerDuty
    - match:
        severity: critical
      receiver: 'pagerduty'
      continue: true
    
    # Warning alerts go to Slack
    - match:
        severity: warning
      receiver: 'slack'
    
    # Informational alerts go to email
    - match:
        severity: info
      receiver: 'email'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://localhost:5001/'
  
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<pagerduty-integration-key>'
        description: '{{ .GroupLabels.alertname }}'
  
  - name: 'slack'
    slack_configs:
      - api_url: '<slack-webhook-url>'
        channel: '#pds-alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
  
  - name: 'email'
    email_configs:
      - to: 'ops@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.example.com:587'
        auth_username: 'alertmanager@example.com'
        auth_password: '<password>'

inhibit_rules:
  # Inhibit warning if critical is firing
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'instance']
```

## PagerDuty Integration

For critical alerts requiring immediate response:

```yaml
receivers:
  - name: 'pagerduty'
    pagerduty_configs:
      - service_key: '<integration-key>'
        description: '{{ .CommonAnnotations.summary }}'
        details:
          firing: '{{ .Alerts.Firing | len }}'
          resolved: '{{ .Alerts.Resolved | len }}'
          instance: '{{ .CommonLabels.instance }}'
        severity: '{{ .CommonLabels.severity }}'
```

### Slack Integration

For warning alerts and team notifications:

```yaml
receivers:
  - name: 'slack'
    slack_configs:
      - api_url: '<webhook-url>'
        channel: '#pds-alerts'
        username: 'Alertmanager'
        icon_emoji: ':warning:'
        title: '{{ .CommonAnnotations.summary }}'
        text: |
          {{ range .Alerts }}
          *Alert:* {{ .Labels.alertname }}
          *Severity:* {{ .Labels.severity }}
          *Description:* {{ .Annotations.description }}
          *Instance:* {{ .Labels.instance }}
          {{ end }}
        actions:
          - type: button
            text: 'View in Prometheus'
            url: '{{ .GeneratorURL }}'
          - type: button
            text: 'Silence'
            url: '{{ .SilenceURL }}'
```

### Email Integration

For informational alerts and daily summaries:

```yaml
receivers:
  - name: 'email'
    email_configs:
      - to: 'ops-team@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'alertmanager@example.com'
        auth_password: '<app-password>'
        headers:
          Subject: '[PDS Alert] {{ .GroupLabels.alertname }}'
        html: |
          <h2>{{ .CommonAnnotations.summary }}</h2>
          <table>
          {{ range .Alerts }}
            <tr>
              <td>{{ .Labels.alertname }}</td>
              <td>{{ .Annotations.description }}</td>
              <td>{{ .StartsAt }}</td>
            </tr>
          {{ end }}
          </table>
```

## Alert Thresholds

### Determining Thresholds

Use historical data to set appropriate thresholds:

```yaml
# Calculate P95 latency over last 30 days
histogram_quantile(0.95,
  rate(pds_http_request_duration_seconds_bucket[30d])
)

# Calculate typical error rate
rate(pds_http_responses_total{status=~"5.."}[30d])
/
rate(pds_http_responses_total[30d])

# Calculate typical resource usage
avg_over_time(pds_blob_storage_bytes[30d])
```

## Threshold Guidelines

| Metric | Warning | Critical | Notes |
|--------|---------|----------|-------|
| Error rate | 1% | 5% | Percentage of 5xx responses |
| P95 latency | 2x baseline | 5x baseline | Compared to 30-day average |
| Disk usage | 80% | 95% | Of total available space |
| Memory usage | 80% | 90% | Of allocated memory |
| CPU usage | 70% | 90% | Sustained over 5 minutes |
| Auth failures | 10% | 20% | Of total auth attempts |
| Database connections | 80% | 95% | Of pool size |

### Dynamic Thresholds

Use anomaly detection for dynamic thresholds:

```yaml
# Alert if current value is 3 standard deviations from mean
abs(
  rate(pds_http_requests_total[5m])
  -
  avg_over_time(rate(pds_http_requests_total[5m])[1h:5m])
) > 3 * stddev_over_time(rate(pds_http_requests_total[5m])[1h:5m])
```

## Alert Runbooks

Every alert should have a runbook with:

1. **Description**: What the alert means
2. **Impact**: How it affects users
3. **Diagnosis**: How to investigate
4. **Resolution**: How to fix it
5. **Prevention**: How to avoid it

### Example Runbook: PDSDown

**Description**: The PDS server is not responding to health checks.

**Impact**: All API requests are failing. Users cannot access the service.

**Diagnosis**:
```bash
# Check if process is running
ps aux | grep kaszlak

# Check server logs
tail -f /var/log/pds/server.log

# Check system resources
top
df -h

# Test connectivity
curl http://localhost:2583/xrpc/com.atproto.server.describeServer
```

**Resolution**:
```bash
# Restart the service
cd DEPLOY_DIR/objpds/docker/pds
docker compose restart pds

# If that fails, check for port conflicts
lsof -i :2583

# Check Docker logs
docker compose logs pds
```

**Prevention**:
- Monitor resource usage trends
- Set up auto-restart on failure
- Implement health check endpoints
- Review logs for warnings before failures

## Example Runbook: PDSHighErrorRate

**Description**: More than 5% of requests are returning 5xx errors.

**Impact**: Users experiencing intermittent failures.

**Diagnosis**:
```bash
# Check error distribution
curl -s http://localhost:2583/_pds/admin/metrics | grep pds_http_responses_total

# Check recent errors in logs
grep ERROR /var/log/pds/server.log | tail -20

# Check database connectivity
sqlite3 data/service.db "SELECT 1"

# Check disk space
df -h
```

**Resolution**:
- If database errors: Check database integrity
- If memory errors: Restart service to clear memory
- If disk full: Clean up old logs, rotate databases
- If external dependency: Check relay/PLC connectivity

**Prevention**:
- Monitor error trends
- Set up database backups
- Implement circuit breakers for external dependencies
- Add retry logic with exponential backoff

## Alert Silencing

### Planned Maintenance

Silence alerts during maintenance windows:

```bash
# Silence all alerts for 1 hour
amtool silence add \
  --alertmanager.url=http://localhost:9093 \
  --author="ops-team" \
  --comment="Planned maintenance" \
  --duration=1h \
  alertname=~".+"

# Silence specific alert
amtool silence add \
  --alertmanager.url=http://localhost:9093 \
  --author="ops-team" \
  --comment="Database migration" \
  --duration=30m \
  alertname="PDSHighLatency"
```

## Flapping Alerts

For alerts that fire and resolve repeatedly:

```yaml
# Add inhibition rule
inhibit_rules:
  - source_match:
      alertname: 'PDSHighLatency'
      severity: 'warning'
    target_match:
      alertname: 'PDSHighLatency'
      severity: 'warning'
    equal: ['instance']
```

Or increase the `for` duration:

```yaml
- alert: PDSHighLatency
  expr: pds_latency > 2.0
  for: 15m  # Increased from 5m to reduce flapping
```

## Alert Testing

### Testing Alert Rules

Validate alert rules before deploying:

```bash
# Check syntax
promtool check rules alerts.yml

# Test alert expression
promtool query instant http://localhost:9090 \
  'rate(pds_http_responses_total{status=~"5.."}[5m]) / rate(pds_http_responses_total[5m]) > 0.05'

# Simulate alert firing
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "PDSHighErrorRate",
      "severity": "critical",
      "instance": "localhost:2583"
    },
    "annotations": {
      "summary": "Test alert",
      "description": "This is a test"
    }
  }]'
```

## Alert Drills

Regularly test alert response:

1. **Trigger test alert**: Simulate failure condition
2. **Verify notification**: Confirm alert reaches on-call
3. **Follow runbook**: Execute resolution steps
4. **Document issues**: Update runbook if needed
5. **Review timing**: Measure time to detection and resolution

## Best Practices

### Do's

- **Alert on user-facing symptoms**: Error rate, latency, availability
- **Include context in alerts**: Instance, severity, description
- **Link to runbooks**: Every alert should have resolution steps
- **Test alerts regularly**: Ensure notifications work
- **Review and tune**: Adjust thresholds based on experience
- **Use alert grouping**: Reduce notification spam
- **Set appropriate severity**: Critical for pages, warning for notifications

### Don'ts

- **Don't alert on everything**: Only actionable issues
- **Don't use static thresholds blindly**: Consider baselines
- **Don't ignore alerts**: Fix or remove noisy alerts
- **Don't alert without runbooks**: Responders need guidance
- **Don't forget to silence**: During maintenance windows
- **Don't alert on predictions**: Alert on current state
- **Don't duplicate alerts**: One alert per issue

## Related Documentation

- [Metrics Collection](metrics-collection) - Metrics for alerting
- [Logging Strategy](logging-strategy) - Diagnostic information
- [Performance Monitoring](performance-monitoring) - Performance baselines
- [Troubleshooting](troubleshooting) - Common issues and solutions

## See Also

- [Prometheus Alerting](https://prometheus.io/docs/alerting/latest/overview/)
- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Google SRE Book - Monitoring](https://sre.google/sre-book/monitoring-distributed-systems/)
- [My Philosophy on Alerting](https://docs.google.com/document/d/199PqyG3UsyXlwieHaqbGiWVa8eMWi8zzAn0YfcApr8Q/edit)
