# Ingress and cert-manager — a primer

Task 5 uses two things the labs did not cover. This explains both from first
principles. Read it before you write `manifests/06-tls.yaml`.

There is a working example to go with it: `docs/examples/EXAMPLE-ingress.yaml`.
Apply it, break it, delete it. Reading YAML is not the same as watching it
route a request.

---

## Part 1 — Why a Service is not enough

You already know Services. A Service gives a stable name and IP for a set of
Pods. So why can it not publish your site?

**`ClusterIP`** is reachable only from inside the cluster. Correct for
catalog, orders and redis. Useless for the public.

**`NodePort`** opens a high-numbered port (30000–32767) on every node. Your
users would have to visit `http://203.0.113.10:31847`. No hostname, no port
443, no TLS, and your firewall in Task 1 does not open that range.

**`LoadBalancer`** asks the cloud for a real load balancer. On a managed
cluster that works. On MicroK8s there is no cloud controller manager to answer
the request, so the Service sits at `<pending>` forever. You can watch this
happen if you want to; it is instructive and costs you two minutes.

All three share a deeper limitation: a Service routes by **port**, and knows
nothing about HTTP. It cannot read a `Host:` header, cannot route `/api` and
`/` to different places, and cannot terminate TLS.

### What an Ingress adds

An **Ingress** is an HTTP-aware routing rule. It says, in effect:

> requests arriving for host `shop.example.com`, path `/`, should go to the
> Service named `frontend` on its port named `http` — and here is the
> certificate to serve them over TLS.

An Ingress is only a *rule*. Something has to enforce it: an **ingress
controller**, which is a real Pod listening on ports 80 and 443. Your stage-2
Terraform installs `ingress-nginx` for exactly this. The controller watches
the API for Ingress objects and rewrites its own nginx configuration to match.

```
   internet
      │  :443
      ▼
 ┌──────────────────────┐   watches Ingress objects,
 │ ingress-nginx (Pod)  │   terminates TLS, routes by Host and path
 └──────────────────────┘
      │  plain HTTP, inside the cluster
      ▼
 ┌──────────────┐    ┌─────────┐    ┌────────┐
 │ frontend Svc │───▶│ catalog │    │ orders │   all ClusterIP
 └──────────────┘    └─────────┘    └────────┘
```

Note what this buys you: **one** way in. Everything else stays `ClusterIP`,
and your firewall opens two ports instead of a range. That is the security
argument, and it is worth making in your report.

### The parts of an Ingress

```yaml
spec:
  ingressClassName:        which controller should act on this rule.
                           More than one can be installed; naming it
                           explicitly is reproducible, relying on the
                           default is not.
  tls:
    - hosts: [...]         which hostnames are served over TLS
      secretName:          a Secret of type kubernetes.io/tls holding
                           tls.crt and tls.key. The Ingress READS this
                           Secret -- it does not create it.
  rules:
    - host:                match on the Host: header
      http:
        paths:
          - path: /
            pathType:      Prefix | Exact | ImplementationSpecific
            backend:
              service:
                name:      a Service name, in the SAME namespace
                port:      by number, or by the port's name
```

Three things that catch people:

- **The Ingress and the Service must be in the same namespace.** An Ingress
  cannot route to a Service in another namespace.
- **`secretName` is a Secret the Ingress consumes.** Something else must
  produce it. That something is cert-manager, below.
- **Annotations carry controller-specific behaviour.** Redirects, body size
  limits, timeouts and rewrites are not in the Ingress spec itself; they are
  `nginx.ingress.kubernetes.io/...` annotations. The ingress-nginx
  documentation lists them, and you will need at least one.

---

## Part 2 — cert-manager

cert-manager is a controller that obtains and renews X.509 certificates and
puts them in Secrets, so that an Ingress can use them. You describe the
certificate you want; cert-manager makes it exist and keeps it valid.

Three object kinds matter.

**Issuer / ClusterIssuer** — *who signs*. An `Issuer` is namespaced; a
`ClusterIssuer` is cluster-wide. Several types exist; two are relevant here:

| Type | What it does |
|---|---|
| `selfSigned` | Signs each certificate with its own fresh key. Every certificate becomes its own root. |
| `ca` | Signs using a CA key and certificate held in an existing Secret. This is what produces a real chain. |

**Certificate** — *what you want*. A request: this hostname, this lifetime,
this key algorithm, signed by that issuer, written to this Secret name.

**The Secret** — *the result*. cert-manager creates it. You never write it by
hand, and you never commit it.

```
   Certificate  ──asks──▶  Issuer  ──signs──▶  Secret (tls.crt + tls.key)
        │                                            │
        │                                            └──▶ read by the Ingress
        └── cert-manager renews it automatically before expiry
```

### The chicken and egg

Task 5 asks for a real chain: a root CA of your own, which signs your site's
certificate. But a `ca` issuer needs a CA key that already exists in a Secret
— and you have no CA yet.

Work out how to resolve that using the two issuer types above and the fact
that a `Certificate` can itself be marked as a certificate authority. The
answer is three objects and it is the standard cert-manager bootstrap pattern;
it has a name, and cert-manager's own documentation describes it:

- <https://cert-manager.io/docs/configuration/selfsigned/>
- <https://cert-manager.io/docs/configuration/ca/>

### The trap, stated plainly because it has no error message

A `ClusterIssuer` of type `ca` reads its signing key from the **cluster
resource namespace** — a single namespace, the one cert-manager itself runs
in. Not your application's namespace.

Put your CA Certificate in the wrong namespace and everything applies
cleanly, no event is raised, and your leaf certificate simply never becomes
`Ready`. The only evidence is in the cert-manager controller logs.

### How to debug a certificate that will not issue

Work down the chain, in this order. The failure is almost always one level
above where you are looking.

```bash
kubectl get clusterissuer                     # Ready=True?
kubectl -n <ns> describe certificate <name>   # read the Events at the bottom
kubectl -n <ns> get certificaterequest        # cert-manager creates one per attempt
kubectl -n <ns> describe certificaterequest <name>
kubectl -n cert-manager logs -l app.kubernetes.io/name=cert-manager --tail=50
```

A leaf that is stuck is usually a CA that is not Ready, which is usually an
issuer that cannot find its Secret.

---

## Part 3 — Checking your work from outside

Do not stop at "the browser loaded it". The browser will warn, and clicking
through proves nothing.

```bash
# what is actually being served?
echo | openssl s_client -connect <host>:443 -servername <host> 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

Read three things in that output:

1. **Subject and issuer must differ.** If they are the same you built one
   self-signed certificate, not a chain. Task 5 caps at a bare pass.
2. **The Subject Alternative Name must contain your hostname.** Browsers
   ignore `commonName` entirely and validate against the SAN. A certificate
   with only a commonName looks right in `openssl` and is rejected by Chrome.
3. **The dates.** Then ask yourself what happens at expiry, and whether you
   have evidence that renewal works.

Then prove the chain validates:

```bash
# export your CA from the Secret cert-manager wrote it to, then:
curl --cacert ca.crt https://<host>/ -o /dev/null -w '%{http_code}\n'
```

A `200` **without** `-k` is the evidence Task 5 is asking for. It says the
chain is cryptographically sound and the only thing missing is that your CA
is not in the browser's trust store. That is a precise statement, and it is
the one to make in your report. "The certificate is invalid" is wrong.

And check the redirect:

```bash
curl -s -o /dev/null -w '%{http_code} -> %{redirect_url}\n' http://<host>/
```

---

## What you still have to work out

This primer gives you the concepts and the object model. It does not give you:

- the three objects in the chain, or which signs which;
- the namespace each belongs in;
- the lifetimes, key algorithm or key size, and your reasons for them;
- which annotations produce the HTTP redirect;
- the three places your hostname has to appear.

Those are Task 5.
