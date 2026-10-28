###############################################################################
# TO WRITE -- Task 2, Criterion 2.   Stage 2: the cluster platform.
#
# provider.tf, variables.tf and outputs.tf are supplied. variables.tf carries
# three chart versions that are known to work together; keep them unless you
# have a reason to move, and say so if you do.
#
# This stage runs ON THE VM, not on your laptop:
#
#   ssh -i k8s-key <admin_user>@<shop_host>
#   cd ~/assessment3/terraform/platform
#   terraform init
#   terraform apply -var="grafana_admin_password=..."
###############################################################################

# ---------------------------------------------------------------------------
# WHY THIS IS A SEPARATE ROOT MODULE -- the most important idea in Task 2
#
# The obvious design is one Terraform configuration that creates the VM and
# then installs everything on it. Try it and you get:
#
#   Error: Provider configuration is invalid
#   ... cannot be determined until apply
#
# Terraform evaluates provider configuration during PLAN. The kubernetes and
# helm providers need the cluster's address and credentials, which do not
# exist until stage 1 has been APPLIED. The configuration therefore depends
# on its own output, and no amount of depends_on fixes it -- depends_on
# orders resources within a phase; this is a dependency between phases.
#
# Two root modules with separate state removes the cycle entirely.
#
# You will be asked about this in the code defense, and "it is cleaner" is
# not the answer. The answer names plan-time evaluation.
#
# There is a second benefit, and it is worth a mark: because stage 2 runs on
# the node, its kubeconfig points at 127.0.0.1:16443 and the Kubernetes API
# never has to face the internet. That is why port 16443 is absent from the
# firewall you wrote in Task 1. The two decisions are connected -- say so.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# WHAT THIS FILE MUST INSTALL
#
# Three Helm releases, each pinned to the version in variables.tf, each in its
# own namespace created by the release:
#
#   1. cert-manager    issues and renews the certificate chain you build in
#                      manifests/06-tls.yaml. Its CRDs -- Certificate,
#                      ClusterIssuer -- must exist before any manifest that
#                      uses them, and installing CRDs is not the chart's
#                      default. Find the value that turns it on.
#
#   2. ingress-nginx   terminates TLS and routes by hostname.
#
#   3. kube-prometheus-stack
#                      Prometheus Operator, Prometheus, Alertmanager,
#                      Grafana, node-exporter and kube-state-metrics in one
#                      chart. This is what gives you five of the six
#                      monitoring layers for free; your own services supply
#                      the sixth.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# INGRESS-NGINX ON A SINGLE NODE -- it will not work out of the box
#
# The chart's default is a Service of type LoadBalancer. On a managed cloud
# cluster that provisions a real load balancer. MicroK8s has no cloud
# controller manager, so the Service sits at <pending> forever and nothing
# ever answers on port 443.
#
# The fix is to put the controller on the node's own network namespace so it
# binds the host's ports directly. Two or three chart values do it. Work out
# which, and explain in your report what you gave up by doing it -- there is
# a real cost, and naming it is a Distinction-level answer.
#
# Also enable the controller's own metrics and let Prometheus discover them.
# Without that you have no visibility at the edge, which is the one place
# that sees requests your application never received.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# THE GOTCHA THAT COSTS PEOPLE AN AFTERNOON
#
# By default, kube-prometheus-stack only discovers ServiceMonitor and
# PrometheusRule objects that carry its own Helm release label.
#
# Your objects in the shop namespace will be created successfully, reported
# as created, and then silently ignored. Nothing is logged. No target
# appears. No error exists anywhere to search for. You find out in Task 7
# when your application panels are empty and everything else works.
#
# There are chart values that switch this off -- look for the ones whose
# names end in SelectorNilUsesHelmValues. There is one per object kind, and
# you need more than one of them.
#
# The alternative is to label your ServiceMonitors with the release name
# instead. monitoring/servicemonitors.yaml already does. Both approaches are
# defensible; belt and braces is fine. What is not defensible is not knowing
# which of the two is making it work.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# OTHER DECISIONS TO MAKE AND DEFEND
#
#   Retention and storage   How long should Prometheus keep samples, and on
#                           what volume? Remember the dedicated data disk at
#                           /datadisk and how much of it you provisioned in
#                           Task 1. A week is a reasonable default; justify
#                           whatever you choose against the disk you have.
#
#   The Grafana password    variables.tf marks it sensitive. Pass it with
#                           -var or TF_VAR_grafana_admin_password and use
#                           set_sensitive rather than set, so it does not
#                           appear in the plan output or the state diff.
#                           Never commit a real value.
#
#   Control-plane scrapes   On MicroK8s, several of the stack's default
#                           control-plane targets -- scheduler, controller
#                           manager, proxy, etcd -- are not reachable as
#                           separate endpoints and will sit permanently down.
#                           A target list that is always partly red teaches
#                           people to ignore it. Decide what to do about
#                           that, do it, and explain the reasoning. This is a
#                           small change that says a lot about whether you
#                           understand what monitoring is for.
#
#   Ordering                Three releases, and at least one pair has a real
#                           ordering requirement between them. Work out which
#                           and express it. Within a single root module
#                           depends_on is the right tool -- the problem at
#                           the top of this file was about providers, not
#                           resources.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# HOW TO CHECK
#
#   terraform apply -var="grafana_admin_password=<choose>"
#   helm list -A                 # three releases, versions as pinned
#   kubectl get pods -A          # everything Running or Completed
#   kubectl get crd | grep -E 'cert-manager|monitoring.coreos'
#
# Allow five to ten minutes: this pulls a lot of images. A timeout on the
# kube-prometheus-stack release is normal on a slow link -- raise it rather
# than assuming the apply failed.
#
# Evidence for Task 2: the apply output, `helm list -A` showing the pinned
# versions, and every platform namespace healthy.
# ---------------------------------------------------------------------------
