# Task 7 — the Grafana dashboard

There is no skeleton file for this one, deliberately. You build the dashboard
in the Grafana UI and export it, which is how dashboards are really made.

**Deliverable:** `monitoring/grafana-dashboard.json`, exported from Grafana and
committed to this repository. Export it with *Dashboard settings → JSON Model*,
or *Share → Export → Export for sharing externally*.

A dashboard that exists only in your Grafana instance does not count. The VM is
destroyed at the end of the assessment and the marker cannot see it.

---

## What it has to show

One dashboard, covering every layer you instrumented in Task 6. Twelve panels
is a reasonable size; fewer than eight will struggle to cover the layers.

| Layer | Where the metrics come from | At least one panel showing |
|---|---|---|
| Host | node-exporter | CPU, memory or disk on the VM itself |
| Cluster objects | kube-state-metrics | Deployment replicas desired vs ready |
| Containers | kubelet / cAdvisor | Per-Pod CPU and memory |
| Ingress edge | ingress-nginx | Request rate or latency at the edge |
| Application | the services' own `/metrics` | Request rate, error rate, latency — and your business counters |

The brief names five layers, with business metrics as part of the application
layer. Task 7 explicitly requires datastore cache effectiveness, so give the
cache its own panel.

## How to organise it

Lead with **RED** — Rate, Errors, Duration — for the three services. Those three
answer "is the application healthy?" and belong at the top where someone
glances first.

Put **USE** — Utilisation, Saturation, Errors — for the host and containers
below. Those answer "why is it unhealthy?" and are only consulted once the top
row says something is wrong.

A dashboard that opens on a CPU graph is a dashboard built around what was easy
to measure rather than around what someone needs to know. Criterion 7 notices
the difference.

## Things that will cost you marks

**Panels with no units.** A y-axis reading `0.0847` is not information. Set the
unit on every panel — seconds, percent (0.0–1.0), requests/sec, bytes.

**Averages where a percentile is needed.** Latency is the obvious case. Show
p95 or p99, and say which.

**A single number where a time series is needed, or the reverse.** A current
error rate is a stat panel; an error rate over the incident is a graph. Task 8
needs the graphs.

**Hardcoded Pod names in queries.** Pods are replaced constantly. Query by
label — `namespace`, `app`, `job` — never by an instance name you read off a
`kubectl get pods` this morning.

**No variables.** A `$namespace` or `$service` template variable turns six
near-identical panels into one. Not required, but it is the difference between
a dashboard you built once and a dashboard someone else could use.

**Counters shown raw.** A line that only goes up is not telling you anything.
Rate it.

## The label trap

`flask_http_request_total` has no `endpoint` label — the exporter puts the
grouping label on the duration histogram instead. Grouping a counter by a label
it does not carry returns one series with an empty label and no error. See the
note in `alerts.yaml`; it applies to panels just as much as to rules.

Check before you build:

```promql
count by (__name__) ({namespace="shop"})
```

and in the Prometheus UI, click a metric name to see its real label set.

## How to check it works

Export the JSON, then **import it into a clean Grafana** and confirm it still
renders. Exports frequently carry a datasource UID that only exists on the
machine they came from, and the panels come up empty on anyone else's. Fix the
datasource reference before you submit — your marker will import it.

Run `scripts/generate-load.sh <host> 600 mixed 8` and screenshot the dashboard
under load. An empty dashboard proves nothing; the evidence is that it moves.
