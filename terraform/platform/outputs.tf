output "grafana_port_forward" {
  description = "Grafana is not exposed publicly. Tunnel to it over SSH instead."
  value       = "kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80"
}

output "prometheus_port_forward" {
  value = "kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090"
}

output "alertmanager_port_forward" {
  value = "kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093"
}

output "next_steps" {
  value = <<-EOT
    Platform ready. Now:
      1. ./scripts/render.sh <shop_host>     # substitute your hostname
      2. ./scripts/build-images.sh v1        # build and push the three images
      3. kubectl apply -f manifests/
      4. kubectl apply -f monitoring/
  EOT
}
