###############################################################################
# Stage 2: cluster platform (cert-manager, ingress-nginx, kube-prometheus-stack)
# Runs ON the VM, with its own state. Providers are configured in provider.tf.
###############################################################################

# ---------------------------------------------------------------------------
# 1. cert-manager
# ---------------------------------------------------------------------------
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version

  # CRDs (Certificate, ClusterIssuer, ...) are not installed by default.
  # Manifests in 06-tls.yaml fail without them. In chart v1.14 this is
  # installCRDs; newer charts renamed it to crds.enabled.
  set {
    name  = "installCRDs"
    value = "true"
  }

  wait    = true
  timeout = 600
}

# ---------------------------------------------------------------------------
# 2. kube-prometheus-stack (release name "monitoring" matches outputs.tf)
# ---------------------------------------------------------------------------
resource "helm_release" "monitoring" {
  name             = "monitoring"
  namespace        = "monitoring"
  create_namespace = true

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        # Without these four, Prometheus only discovers objects carrying the
        # chart's own release label, and ServiceMonitors/rules in the shop
        # namespace are created and then silently ignored. One per object kind.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false

        # Keep a week of samples, capped by size so a busy week cannot fill
        # the volume. The size cap is the safety net; the time is the target.
        retention     = "7d"
        retentionSize = "8GB"

        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources   = { requests = { storage = "10Gi" } }
            }
          }
        }
      }
    }

    # MicroK8s runs scheduler, controller manager and proxy inside the single
    # kubelite process, and etcd is not exposed as a separate endpoint, so
    # these default targets would sit permanently DOWN. Disabled rather than
    # left red, so every remaining red target means something real.
    kubeScheduler         = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeProxy             = { enabled = false }
    kubeEtcd              = { enabled = false }
  })]

  # set_sensitive keeps the value out of plan output and diffs.
  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  wait    = true
  timeout = 900 # large chart, many images; a slow pull is not a failure
}

# ---------------------------------------------------------------------------
# 3. ingress-nginx
# ---------------------------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version

  values = [yamlencode({
    controller = {
      # MicroK8s has no cloud controller, so a LoadBalancer Service would sit
      # at <pending> forever. Instead the controller shares the node's network
      # namespace and binds 80/443 on the host directly.
      hostNetwork = true
      dnsPolicy   = "ClusterFirstWithHostNet" # keep cluster DNS working
      kind        = "DaemonSet"               # see note below
      service     = { type = "ClusterIP" }

      # Ingress objects without an explicit class still get served.
      ingressClassResource = { default = true }

      # Edge metrics, discovered by Prometheus.
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = { release = "monitoring" } # belt and braces
        }
      }
    }
  })]

  # The ServiceMonitor above needs the ServiceMonitor CRD, which the
  # monitoring release installs. Real ordering within a single phase, so
  # depends_on is the right tool here.
  depends_on = [helm_release.monitoring]

  wait    = true
  timeout = 600
}
