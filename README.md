# ID72001 Assessment 3 — Starter Repository

A secure, observable microservice platform on Kubernetes, orchestrated with
Terraform, on **AWS, Azure or Catalyst Cloud** — you choose.

This repository is **deliberately incomplete**. About half of it is supplied so
you are not retyping lab code; the rest is yours to write, and the assessment
measures that half.

> **Start with [`TASKS.md`](TASKS.md).** It lists every file as *given*,
> *worked example* or *to write*, says which task and how many marks each one
> carries, and explains why the line falls where it does.

```bash
./scripts/check-progress.sh          # what is still unwritten
./scripts/check-progress.sh azure    # once you have chosen a cloud
```

---

## What you are building

| Component | Role | Reachable from outside? |
|---|---|---|
| `frontend` | Renders the page. Owns no data. | Yes — via the Ingress, over HTTPS |
| `catalog` | Owns the product list. No dependencies. | No |
| `orders` | Validates orders, writes to Redis. | No |
| `redis` | Order store, on a PersistentVolume | No |

Published on your own hostname, served over TLS from a certificate authority
you build inside the cluster, and monitored end to end by Prometheus across
five layers.

One Ingress reaches the internet. Everything else is `ClusterIP`.

---

## Where to read what

| If you want to… | Read |
|---|---|
| Know what to write and what you were given | **`TASKS.md`** |
| Know what stage 1 must produce, on any cloud | **`docs/CLOUD-CONTRACT.md`** |
| Know the order to do things in | **`RUNBOOK.md`** |
| Know what a specific file must contain | the skeleton file itself — each one carries its own requirements, traps and checks |
| Understand Ingress and cert-manager — neither was in the labs | **`docs/INGRESS-AND-TLS-PRIMER.md`**, then `docs/examples/EXAMPLE-ingress.yaml` |
| Fix something broken | **`docs/TROUBLESHOOTING.md`** |
| Write Task 8 | **`docs/CRITICAL-EVALUATION-TEMPLATE.md`** |
| Know how the dashboard is marked | **`monitoring/README-dashboard.md`** |

The skeletons are where the detail lives. `manifests/06-tls.yaml` is a hundred
lines of comments and no YAML; that is not an oversight.

---

## Choosing a cloud

All three are equally creditable and Criterion 1 is marked identically across
them. Only stage 1 differs — roughly 85% of this repository is the same
whichever you pick, including the bootstrap script.

- **AWS Academy Learner Lab** — credentials expire every few hours, which
  interrupts long applies; no managed DNS, so you use `sslip.io`.
- **Azure** — the school subscription is stable and you get a free hostname.
  Watch the ~4 vCPU cap, the restricted VM sizes and the per-student allowed
  regions.
- **Catalyst Cloud** — a New Zealand provider, so data stays onshore. Plain
  OpenStack, which makes it the most transferable of the three.

`docs/CLOUD-CONTRACT.md` has the full comparison. `RUNBOOK.md` §0 has the
pre-flight commands for each — run them before you commit to one, because
quota, not skill, is what usually decides this.

Delete the two `terraform/infra-*` directories you do not use before you
submit.

---

## How much comes from the labs

| Task | Source |
|---|---|
| 1 — Terraform, cloud foundation | New. Lab structure carries over; the provider does not |
| 2 — Platform orchestration | New, and cloud-neutral |
| 3 — Microservices and images | **Lab 9.3**, nearly unchanged — the source is supplied |
| 4 — Workloads, config, storage | **Lab 9.3** manifests, plus ConfigMap/Secret from **9.2** and a PVC |
| 5 — Hostname and TLS | New, and the hardest thing here |
| 6 — Prometheus, end to end | **Lab 9.4** — instrumentation, ServiceMonitors, rules |
| 7 — Grafana dashboard | **Lab 9.4** — same panel ideas, your namespace |
| 8–9 — Evaluation and defense | Entirely your own |

Go back to your own lab work before you go to the internet. You have built most
of this before.

---

## Things that will cost you marks, collected in one place

**Clicking instead of coding.** Resources in Tasks 1 and 2 created by hand in a
web console earn nothing in those criteria, even if the system works.

**A committed secret.** A live credential, private key, kubeconfig or real
password anywhere in the submitted archive caps Criterion 4 at *Not achieved*.
`.gitignore` already excludes state, `.terraform/` and `k8s-key*` — do not
weaken it.

**Storage the platform can discard.** On Azure especially, `/mnt` is a
temporary disk whose contents are destroyed on deallocation. The supplied
bootstrap mounts your data disk at `/datadisk` on every cloud for exactly this
reason. Check with `findmnt /datadisk` rather than assuming.

**A hardcoded hostname.** `scripts/render.sh` substitutes `__SHOP_HOST__`.
Type your own hostname into the manifests instead and the repository stops
being reproducible for anyone, including your marker.

**One self-signed certificate instead of a chain.** If subject and issuer
match, Criterion 5 caps at a bare pass however well the site works.

**A dashboard that only exists in your Grafana.** Export the JSON and commit
it. The VM is gone by the time it is marked.

**A working deployment you cannot explain.** Tasks 8 and 9 are 20 marks for
reasoning, not building. Every criterion's upper bands ask *why*, not *does it
run*.

---

## Platform-independent gotchas worth knowing now

- **The ServiceMonitor selector.** kube-prometheus-stack only discovers
  ServiceMonitors and rules carrying its release label unless you tell it
  otherwise. Yours will be created successfully and silently ignored. Nothing
  is logged. See `monitoring/servicemonitors.yaml`.
- **`flask_http_request_total` has no `endpoint` label.** Group a counter by a
  label it does not carry and PromQL returns one empty-labelled series rather
  than an error. See `monitoring/alerts.yaml`.
- **One gunicorn worker.** `prometheus_client` holds counters in process
  memory, so several workers each report a partial count. Scale by Pod.
- **ReadWriteOnce and rolling updates do not mix.** See
  `manifests/02-redis.yaml`.
- **Two Terraform stages, not one.** Provider configuration is evaluated at
  plan time, before the cluster exists. See `terraform/platform/main.tf`.

Each of these is a question you may be asked in the code defense.
