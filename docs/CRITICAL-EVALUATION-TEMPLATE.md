# Task 8 — Critical Evaluation (1500 words max)

This is a **structure with the queries that produce each number**, not a report
to copy. The marks are for your measurements and your reasoning about them.

The band boundary, stated plainly in the rubric: a report that asserts "the
system performed well" earns little. One that shows a latency histogram, names
the percentile, identifies the saturating resource and ties it to a specific
configuration decision earns the top band. **Reference your metrics by query,
not by impression.**

---

## 1. Performance under load (~400 words)

Run `./scripts/generate-load.sh <host> 600 mixed 8` and record:

| Measurement | Query |
|---|---|
| Request rate | `sum(rate(flask_http_request_total{namespace="shop"}[5m]))` |
| Rate per service | `sum by (job) (rate(flask_http_request_total{namespace="shop"}[5m]))` |
| p50 / p95 / p99 | `histogram_quantile(0.95, sum by (le) (rate(flask_http_request_duration_seconds_bucket{namespace="shop"}[5m])))` |
| Error ratio | `sum(rate(flask_http_request_total{namespace="shop",status=~"5.."}[5m])) / sum(rate(flask_http_request_total{namespace="shop"}[5m]))` |
| CPU per pod | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="shop",container!=""}[5m]))` |
| CPU throttling | `sum by (pod) (rate(container_cpu_cfs_throttled_seconds_total{namespace="shop",container!=""}[5m]))` |
| Memory vs limit | `container_memory_working_set_bytes{namespace="shop",container!=""} / container_spec_memory_limit_bytes{namespace="shop",container!=""}` |

**Identify the first component to degrade, and prove it was that one.**

Do not stop at "latency went up". Say *which* service's latency, at *which*
percentile, and what its resource graphs were doing at the same moment. The
strongest evidence is usually CPU throttling: a container that hits its limit
is not slowed smoothly, it is *stopped* until the next scheduling period, so
latency rises while average CPU still looks comfortable. If you see throttling
above zero, that is almost certainly your answer — say so and show both graphs
on the same time range.

Two things worth checking that students often miss:

- **The cache hit ratio** —
  `sum(rate(order_catalog_cache_lookups_total{outcome="hit"}[5m])) / sum(rate(order_catalog_cache_lookups_total[5m]))`.
  Under load this should *rise*, because more requests arrive inside the 30s TTL.
  If it falls, say why.
- **Where the bottleneck is not.** Ruling out the ingress or the node is itself
  evidence, if you show the numbers.

---

## 2. Behaviour under failure (~400 words)

Run `./scripts/failure-drill.sh <host>` and report Experiments A and B.

**The point of this section is that A and B are different failures**, and your
system reports them differently.

| | Catalog removed (A) | Datastore removed (B) |
|---|---|---|
| Page HTTP status | 200 | 200 |
| Page latency | normal | normal — this matters |
| What the page says | catalog unreachable | order service healthy, *datastore* unreachable |
| Past orders | still listed | not listed |
| New orders | refused, 503 | refused, 503 |
| Which metric reveals it | `up{job=~".*catalog.*"}` | `store_available` in the orders API |

Explain **which design choices produced that behaviour**:

- `fetch_products()` and `fetch_orders()` return a success flag instead of
  raising, so one dead dependency disables one feature rather than the page.
- The readiness probe deliberately does **not** check Redis. Explain what would
  happen if it did — every orders replica would fail readiness at once, the
  Service would empty, and callers would get a connection error instead of the
  handled message. A degraded service would become an unreachable one.
- The order service's Redis client is configured `Retry(NoBackoff(), retries=0)`
  with 1s timeouts. Without that it would retry with backoff and take seconds to
  answer, so the *frontend* would time out and wrongly report the order service
  as down. Measure the response time in Experiment B to show it stays fast.

Distinguish **graceful degradation** from **outage** explicitly. One feature
lost is not the same as the service being down, and your evidence should show
you can tell them apart from the metrics alone.

---

## 3. Scaling (~350 words)

From Experiment C:

```bash
kubectl -n shop get pods          # note the AGE column
kubectl -n shop get endpoints catalog
```

Report the request distribution across the five catalog replicas (the drill
prints it). Note what you did **not** have to do: no manifest edited, no service
restarted, nothing told the frontend the replica count changed. The label
selector absorbed it the moment each Pod passed readiness.

**What would you scale first under a traffic increase, and what is the limit?**

The honest answer on a single node is memory, and you should prove it rather
than assert it:

```promql
sum(kube_pod_container_resource_requests{namespace="shop",resource="memory"})
  / sum(kube_node_status_allocatable{resource="memory"})
```

The observability stack holds 2–3 GiB before your application starts. On an
8 GiB VM the scheduler stops placing Pods once requests exhaust allocatable
memory, and they sit `Pending` with an insufficient-memory event. Show a
`Pending` Pod's `describe` output if you can produce one.

Then make the stronger point: **replicas on one node share a fault domain**.
Scaling improves throughput but not availability — if the VM dies, five
replicas die with it. The real fix is more nodes, which is a different
architecture and a different bill.

---

## 4. Critical reflection (~350 words)

Identify the **two weakest points** and give concrete, costed remediation.
Strong candidates, in rough order of how defensible they are:

1. **Single node, single point of failure.** Everything — control plane,
   workloads, datastore, monitoring — is on one VM. Remediation: a managed
   multi-node cluster. Cost: more vCPU quota than a student subscription has,
   plus the control-plane management you no longer do yourself.
2. **Redis is a `Deployment` with one replica.** It has a PVC so it survives
   Pod deletion, but there is no replication and no failover. Remediation: a
   `StatefulSet` with replication, or a managed cache. Say what that costs in
   complexity.
3. **No network policy.** Every Pod can reach every other Pod. Nothing stops a
   compromised frontend talking straight to Redis. Remediation: `NetworkPolicy`
   objects — cheap to add, which is itself worth saying.
4. **The certificate is not publicly trusted.** Defensible here, and you should
   explain *why* it is defensible rather than apologising for it: the shared
   rate limit on `cloudapp.azure.com` makes public issuance unreliable for a
   cohort, and an internal CA is normal for service-to-service traffic anyway.
   What a public CA adds is third-party attestation to clients who have never
   met the operator.
5. **Secrets are base64 in etcd.** Not encrypted. Remediation: encryption at
   rest plus RBAC, or an external secret store.

Pick two, go deep, and cost them. Listing five shallowly scores worse than
analysing two properly.

---

## Common ways to lose marks here

- Describing what you did instead of what you measured.
- "The system performed well under load" with no numbers.
- Screenshots of dashboards with no time range visible, so nobody can tell when
  they were taken or whether they overlap.
- Treating Experiments A and B as the same event.
- Claiming a bottleneck without showing the resource graph that proves it.
- Going over 1500 words. The limit is part of the exercise.
