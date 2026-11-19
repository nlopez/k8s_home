output "cluster_id" {
  value = digitalocean_kubernetes_cluster.this.id
}

output "kubeconfig" {
  description = "Raw kubeconfig. Prefer `doctl kubernetes cluster kubeconfig save` or the tailnet API proxy."
  value       = digitalocean_kubernetes_cluster.this.kube_config[0].raw_config
  sensitive   = true
}
