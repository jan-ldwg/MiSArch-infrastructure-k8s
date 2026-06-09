output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.primary.endpoint
  sensitive = true
}

output "state_bucket_name" {
  value = local.state_bucket_name
}

data "kubernetes_service" "ingress_nginx" {
  depends_on = [helm_release.ingress_nginx]

  metadata {
    name      = "ingress-nginx-controller"
    namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  }
}

output "ingress_external_ip" {
  value = coalesce(
    try(data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip, null),
    google_compute_address.ingress.address,
  )
}

output "kubeconfig_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.region} --project ${var.project_id}"
}

output "root_domain_url" {
  value = "https://${coalesce(
    try(data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip, null),
    google_compute_address.ingress.address,
  )}"
}
