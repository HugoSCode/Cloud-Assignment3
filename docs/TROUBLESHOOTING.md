# Troubleshooting

Ordered roughly by how often each one happens.

---

## Terraform / Azure

**`SkuNotAvailable` or `NotAvailableForSubscription`**
Your subscription cannot use that VM size in that region.
```bash
az vm list-skus --location <region> --size Standard_B2 \
  --query "[].{name:name, restrictions:restrictions[0].reasonCode}" -o table
```
Pick anything with 2 vCPU and 8 GiB and pass `-var="vm_size=..."`.

**`QuotaExceeded` / "Total Regional Core quota exceeded"**
You are at your vCPU cap, usually 4. Check what is already running:
```bash
az vm list-usage --location <region> -o table | grep -i "Total Regional"
az vm list -d --query "[].{name:name,size:hardwareProfile.vmSize,state:powerState}" -o table
```
Delete leftovers from earlier labs.

**`RequestDisallowedByPolicy` on the region**
The *Allowed Locations* policy blocks it. `az account list-locations -o table`
shows what exists, not what you may use — try another region and see.

**`AuthorizationFailed` creating the resource group**
You were issued one and cannot create more. Use it:
```bash
terraform apply -var="create_resource_group=false" -var="resource_group_name=<the-one-you-were-given>" ...
```

**`MissingSubscriptionRegistration`**
```bash
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Network
```
Takes a few minutes. If you lack permission, ask your lecturer.

**`DnsRecordInUse`**
Your `dns_label` is taken — it must be globally unique *within the region*.
Add something distinctive.

**Apply fails on `templatefile`, unknown variable**
Something in `cloud-init.yaml` looks like a Terraform interpolation. Only
`admin_user` should:
```bash
grep -oE '\$\{[^}]*\}' terraform/infra/cloud-init.yaml | sort -u
```
Shell variables in that file must be written `$VAR`, never braced.

---

## The VM and cluster

**SSH times out**
The NSG allows SSH only from `ssh_source_address`. If your address changed:
```bash
terraform apply -var="ssh_source_address=$(curl -s ifconfig.me)/32" ...
```

**`microk8s` not found, or the cluster is not up**
cloud-init is still running. Watch it:
```bash
sudo tail -f /var/log/cloud-init-output.log
ls -l /var/lib/cloud/bootstrap-complete     # exists only when finished
```

**`/datadisk` is missing or empty**
```bash
lsblk
ls -l /dev/disk/azure/scsi1/lun0
mount | grep datadisk
```
If the symlink is absent the disk did not attach — check
`azurerm_virtual_machine_data_disk_attachment` applied.

**Data vanished after stopping the VM**
Almost certainly on `/mnt`, which is Azure's *temporary* disk and is wiped on
deallocation. Persistent data belongs on `/datadisk`. Check where the storage
class points:
```bash
kubectl -n shop get pv -o custom-columns=NAME:.metadata.name,PATH:.spec.hostPath.path
```

**Pods `Evicted` or randomly `CrashLoopBackOff`**
The node is out of memory — a 4 GiB VM cannot hold the observability stack plus
the app.
```bash
kubectl describe node | grep -A5 "Allocated resources"
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -20
```

---

## Images

**`ImagePullBackOff`**
```bash
curl -s http://localhost:32000/v2/_catalog
kubectl -n shop describe pod <pod> | tail -20
```
The image is not in the registry, or the tag in the manifest does not match.
The reference is `localhost:32000/<name>:v1` exactly.

**`docker push` connection refused**
```bash
microk8s enable registry
microk8s status | grep registry
```

---

## TLS

**Certificate stuck not Ready**
```bash
kubectl -n shop describe certificate shop-tls
kubectl -n shop get certificaterequest,order,challenge
kubectl -n cert-manager logs -l app=cert-manager --tail=50
```
The usual cause is the root CA not being ready first. Check where you created
it: a `ClusterIssuer` of type `CA` reads its signing key from the *cluster
resource namespace*, which defaults to the namespace cert-manager itself runs
in — not the namespace your application lives in. A root CA Certificate
created in `shop` produces a Secret that the ClusterIssuer will never find,
and the error you get back says only that the secret is missing.

**Browser shows the ingress default certificate ("Kubernetes Ingress Controller Fake Certificate")**
The Ingress is not finding its TLS secret. Check `tls.secretName` matches the
Certificate's `secretName`, and that both are in the `shop` namespace.

**Subject equals issuer on the served certificate**
You built one self-signed certificate instead of the bootstrap → CA → leaf
chain. Re-apply `manifests/06-tls.yaml` and check all three objects exist.

**`curl --cacert ca.crt` still fails**
Export the CA certificate, not the key:
```bash
kubectl -n cert-manager get secret <your-ca-secret-name> \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > ca.crt
openssl x509 -in ca.crt -noout -subject -issuer
```
A root CA's subject and issuer *are* the same — that is expected for a root.
It is the **leaf** where they must differ.

---

## Monitoring

**Application metrics missing, no error anywhere**
The single most common monitoring fault. The Helm chart only discovers
ServiceMonitors carrying its release label.
```bash
kubectl -n shop get servicemonitor shop-services -o jsonpath='{.metadata.labels}'
```
Must include `release: monitoring`. The platform values also set
`serviceMonitorSelectorNilUsesHelmValues: false` as a second defence. Nothing
is logged when this is wrong.

**Target present but `DOWN`**
Prometheus sees the Service but cannot reach the port. The ServiceMonitor names
a port by **name**, and that name must exist on the Service:
```bash
kubectl -n shop get svc -o custom-columns=NAME:.metadata.name,PORTS:.spec.ports[*].name
```

**`kubectl get endpoints` is empty**
The Service selector matches no *ready* Pods. Either the labels disagree or the
Pods are failing readiness — this one command distinguishes "my labels are
wrong" from "my app is broken", which look identical from outside.

**Alert never fires**
Run its `expr` by hand in the Graph tab. If it returns nothing the alert cannot
fire. Then check `for` has actually elapsed — it stays `Pending` until then.

**Grafana panel empty but the query works in Prometheus**
Wrong data source on the panel, or the dashboard time range predates the data.

---

## Fast triage

```bash
kubectl -n shop get pods,endpoints
kubectl -n shop describe pod <failing-pod> | tail -30
kubectl -n shop logs <pod> --previous
kubectl get events -A --sort-by=.metadata.creationTimestamp | tail -20
./scripts/verify.sh <host>
```
