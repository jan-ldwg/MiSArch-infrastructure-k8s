output "ingress_external_ip" {
  description = "External IP address of the ingress-nginx-controller LoadBalancer (if assigned)"
  value       = try(data.kubernetes_service.ingress_lb.status[0].load_balancer[0].ingress[0].ip, null)
}

output "global_domain" {
  description = "Public URL for the installation (falls back to localhost if LoadBalancer IP is not available)"
  value       = local.global_domain
}
