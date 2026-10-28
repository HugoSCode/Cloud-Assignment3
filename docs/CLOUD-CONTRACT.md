# The cloud contract

This assessment runs on **AWS, Azure or Catalyst Cloud**. You pick one.

That is possible because the deployment is split at a deliberate boundary.
Understanding where that boundary is — and why it is where it is — is itself
assessed, so read this before you choose.

---

## The boundary

```
   CLOUD-NEUTRAL  (identical on all three providers)
   ----------------------------------------------------------
   monitoring/       ServiceMonitors, alert rules, dashboard
   manifests/        Deployments, Services, ConfigMap, Secret, PVC, Ingress, TLS
   app/              three Flask services
   terraform/platform/   cert-manager, ingress-nginx, kube-prometheus-stack
   terraform/shared/     cloud-init.yaml -- one bootstrap for all three
   ----------------------------------------------------------
   PROVIDER-SPECIFIC  (pick exactly one)
   terraform/infra-aws/   |  infra-azure/  |  infra-catalyst/
```

Roughly **85% of the repository is identical** regardless of which cloud you
choose. Only stage 1 differs, and even its bootstrap script is shared.

**Why the line is here.** Kubernetes is itself a portability layer: a
`Deployment` means the same thing everywhere. Below Kubernetes you are talking
to a specific provider's API — networks, firewalls, disks and addresses have
genuinely different models, and no amount of abstraction makes an Azure NSG and
an OpenStack security group the same object. The honest engineering answer is
to isolate that difference in one small, swappable layer rather than pretend it
does not exist.

---

## What stage 1 must produce

Any implementation is acceptable if it satisfies this contract. The three
supplied stacks all do; if you write a fourth for a different provider, match
these and everything above keeps working untouched.

### Resources

| # | Requirement | Why |
|---|---|---|
| 1 | A Linux VM, Ubuntu 22.04, **2 vCPU and 8 GiB** | The observability stack needs 2–3 GiB before the app starts. A 4 GiB VM evicts Pods. |
| 2 | A **stable** public IP that survives a stop/start | The hostname is published in a TLS certificate; a changed address invalidates it. |
| 3 | A **resolvable public hostname** | Hostname-based routing and certificate SANs need a real DNS name. |
| 4 | A firewall allowing **22** (from your address only), **80**, **443** | 443 serves the app, 80 only redirects. Nothing else is opened. |
| 5 | A **dedicated data disk**, separate from the OS disk | PersistentVolumes live here; storage is resized and reasoned about independently. |
| 6 | SSH **key** authentication, passwords disabled | Password auth on an internet-facing VM is brute-forced continuously. |
| 7 | A purpose-built network, not the provider's default | The network design is an assessable artefact. |

### Outputs

Every stage-1 stack **must** emit these four names. Stage 2 and the deploy
scripts consume them, and nothing above cares which cloud produced them.

```hcl
output "public_ip"   { }   # the stable address
output "shop_host"   { }   # the resolvable hostname
output "ssh_command" { }   # ready to paste
output "admin_user"  { }   # ubuntu, or azureuser on Azure
```

Check yours with:

```bash
terraform -chdir=terraform/infra-<cloud> output
```

### The bootstrap

All three pass the **same** `terraform/shared/cloud-init.yaml`, with two
variables:

```hcl
custom_data = templatefile("../shared/cloud-init.yaml", {
  admin_user = "ubuntu"      # or azureuser on Azure
  disk_hint  = "/dev/vdb"    # provider-specific first guess; may be ""
})
```

The script tries `disk_hint` first, then a candidate list, and accepts only a
device that is a real block device, is not the root disk, and has nothing
mounted from it. It therefore works even when the hint is wrong. It always
mounts at `/datadisk`, never `/mnt`.

---

## How each cloud satisfies the contract

| Contract item | AWS | Azure | Catalyst Cloud |
|---|---|---|---|
| Provider | `hashicorp/aws` | `hashicorp/azurerm` | `terraform-provider-openstack/openstack` |
| Credentials | Learner Lab env vars | `az login` | `source` the OpenStack RC file |
| Network | VPC + subnet + IGW + route table | VNet + subnet | Network + subnet + router |
| Firewall | Security group | Network security group | Security group + rules |
| Stable address | Elastic IP | Static Standard public IP | Floating IP from `public-net` |
| **Hostname** | `shop.<dashed-ip>.sslip.io` | `<label>.<region>.cloudapp.azure.com` | `shop.<dashed-ip>.sslip.io` |
| Data disk | EBS volume | Managed disk | Block storage volume |
| Disk appears at | `/dev/nvme1n1` or `/dev/xvdf` | `/dev/disk/azure/scsi1/lun0` | `/dev/vdb` |
| Login user | `ubuntu` | `azureuser` | `ubuntu` |
| Size used | `t3.large` | `Standard_B2ms` | `c1.c2r8` |

### A note on hostnames

Azure publishes a free DNS name for any public IP given a label. AWS and
Catalyst do not offer an equivalent without a registered domain, so both use
`sslip.io`, which resolves `<anything>.<dashed-ip>.sslip.io` straight back to
that IP.

**This choice does not affect your marks**, because the certificate is issued
by an in-cluster CA rather than a public one. If you were using Let's Encrypt
it would matter a great deal — both `sslip.io` and `cloudapp.azure.com` share a
single registered-domain rate limit that is regularly exhausted, which is
precisely why the assessed path does not depend on public issuance. See Task 5
in the brief.

---

## Choosing

All three are equally creditable. Choose on constraints, not preference.

**AWS Academy Learner Lab** — credentials expire every few hours, which
interrupts long Terraform runs; no Route 53. Choose it if your course already
has you in Learner Lab and you are comfortable refreshing credentials.

**Azure** — the school subscription is stable and does not expire mid-session,
and you get a real hostname for free. But student subscriptions carry a ~4 vCPU
cap, a restricted VM SKU list and a per-student *Allowed Locations* policy, so
run the pre-flight in `RUNBOOK.md` §0 before committing.

**Catalyst Cloud** — a New Zealand provider, so data stays onshore and latency
is low from here. It is plain OpenStack, which means the Terraform is the most
transferable of the three: the same provider works against any OpenStack cloud,
of which there are many in research and government. Check your project quota
first — `openstack quota show` — because OpenStack quotas are per-project and
easy to exhaust.

> **Marking is identical across the three.** Criterion 1 assesses whether your
> infrastructure is reproducible, well-designed and justified — not which
> provider's API you called.

---

## The portability question

Expect to be asked this in the code defense, and have a real answer:

> *You wrote Terraform for one cloud. How much of this would move to another,
> and what would not?*

A weak answer is "Terraform is cloud-agnostic". It is not — the *language* is
portable, the *providers* are not. `aws_instance`, `azurerm_linux_virtual_machine`
and `openstack_compute_instance_v2` share no schema.

A strong answer identifies the layers:

- **Moves untouched**: everything Kubernetes. Deployments, Services, Ingress,
  the certificate chain, the ServiceMonitors, the dashboard. Kubernetes is the
  portability layer, and that is most of the value it provides.
- **Moves with a rewrite**: stage 1. Same seven requirements, different resource
  types and different names for the same ideas.
- **Does not move at all**: the hostname strategy, because each provider's free
  DNS offering differs; and anything that depends on a provider-specific managed
  service.

Then make the sharper point: this deployment is portable **because it uses
almost nothing the cloud offers**. It is a VM with a disk. The moment you adopt
a managed database, a managed Kubernetes service or a provider-specific load
balancer, portability costs real money to preserve — and is often not worth
paying for. Portability is a trade against leverage, not a free good.
