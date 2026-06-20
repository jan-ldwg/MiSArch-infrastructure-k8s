output "cluster_name" {
  value = google_container_cluster.misarch.name
}

output "cluster_endpoint" {
  value = google_container_cluster.misarch.endpoint
}

output "cluster_ca_certificate" {
  value = google_container_cluster.misarch.master_auth[0].cluster_ca_certificate
}

output "region" {
  value = var.region
}

output "project_id" {
  value = var.project_id
}
