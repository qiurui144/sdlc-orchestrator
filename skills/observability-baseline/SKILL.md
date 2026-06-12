---
name: observability-baseline
description: Use when releasing a service / changing service tier / setting up new endpoint. Defines RED (Rate/Errors/Duration for request-driven) or USE (Utilization/Saturation/Errors for resource-driven) metrics. Specifies log schema + sampling + traces + alerts.
---

# observability-baseline

## When to use

- implementer adding a new service endpoint
- releaser before production rollout
- cicd-designer pipeline emission
- `/sdlc:obs` (future v0.2 command) or invoked indirectly by other agents

## When NOT to use

- Internal library / non-deployable code
- Pure CLI tools (no service surface)

## Method selection

Pick ONE framework:

- **RED** — for request-driven services (API, RPC, web): track **R**ate (req/s), **E**rrors (rate of failed req), **D**uration (latency histogram)
- **USE** — for resource-driven systems (cache, queue, DB): track **U**tilization (% busy), **S**aturation (queued/dropped), **E**rrors (system-level)

Most services need RED; backing stores get USE; large platforms need both.

## Steps

1. **Pick metrics framework** (RED or USE or both)
2. **Define structured log schema** with required fields:
   - timestamp (ISO 8601 UTC+8)
   - level (ERROR|WARN|INFO|DEBUG)
   - service_name
   - request_id (correlation)
   - user_id (if auth'd; pseudonymized if PII concern)
   - operation
   - duration_ms
   - status (200/4xx/5xx or success/failure)
   - error_message (if applicable)
3. **Define log sampling strategy**:
   - ERROR: 100%
   - WARN: 100%
   - INFO: 100% for low-volume, 10% for high-volume
   - DEBUG: 0% in production
4. **Define traces** (OpenTelemetry / Jaeger / Zipkin compatible):
   - Span per major operation
   - Parent span propagation across service boundaries
   - Trace ID matches request_id in logs
5. **Define alert thresholds**:
   - Errors rate > 1% over 5min -> page
   - p99 latency > SLO x 2 over 10min -> page
   - Saturation > 80% over 15min -> ticket
   - All resolved within < 24h or escalate
6. **Output**: `docs/observability/<service>-baseline.md` + sample Prometheus/Grafana config + sample alert YAML

## Output schema

```yaml
schema_version: 1
service: <service-name>
framework: RED | USE | both
metrics:
  - name: http_requests_total
    type: counter
    labels: [method, route, status_class]
  - name: http_request_duration_seconds
    type: histogram
    labels: [method, route]
    buckets: [0.01, 0.05, 0.1, 0.5, 1, 5]
logs:
  schema_version: 1
  required_fields: [timestamp, level, service_name, request_id, operation, status]
  sampling:
    ERROR: 1.0
    INFO: 0.1
traces:
  exporter: otlp
  endpoint: http://collector:4317
  sampling_ratio: 0.1
alerts:
  - name: high_error_rate
    expr: rate(errors[5m]) > 0.01
    severity: page
self_score:
  metrics_completeness: 5
  log_schema_correctness: 5
  alert_slo_traceability: 5
```

## Failure modes

1. Framework selection ambiguous -> both
2. Logs missing required field -> reject; can't correlate
3. Alert threshold guessed ("seems high") -> require SLO-derived
4. No tracing infra -> emit local-only spans + flag for v.next
5. PII in logs -> require pseudonymization rule

## Error-code taxonomy (SE21) — project requirement

A project MUST have a **documented, stable, numbered** error/return-code taxonomy — NOT error
strings scattered as literals. Model: nginx return codes, bluez error enums, `errno(3)`.
- One registry (a doc / enum / module): code → meaning → exit/return mapping, **stable across versions**.
- Logs + API errors reference the **CODE** (not just a message) so callers/operators can branch on it.
- Reviewer checks: registry exists? codes stable (not renamed each release)? referenced in logs?
- Absent / ad-hoc literals → **SE21 finding**.

## Logging applies to ALL deployables (SE22) — not just request-services

The RED/USE metrics above are for services. **Structured, leveled logging is required for libraries,
daemons, and CLIs too** — bluez/nginx are daemons/libs (not request services) yet have exemplary
leveled logging. Minimum: **level** (debug/info/warn/error) + **timestamp** + the SE21 **error-code**
on errors + grep-able structure (key=value or JSON). Scattered bare `print`/`println` → **SE22 finding**.

## Linked

- [[performance-analyst]] (SLO defines alert thresholds)
- [[cicd-designer]] (pipeline emits observability config)
- [[incident-responder]] (postmortem references alerts that did/didn't fire)
- spec §11 SE10 / SE21 (error-code taxonomy) / SE22 (structured logging)
