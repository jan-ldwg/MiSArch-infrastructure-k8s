resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "app.kubernetes.io/name" = "ingress-nginx"
    }
  }

  depends_on = [google_container_node_pool.primary]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_chart_version
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name

  values = [
    yamlencode({
      controller = {
        service = {
          type            = "LoadBalancer"
          loadBalancerIP  = google_compute_address.ingress.address
          annotations = {
            "cloud.google.com/load-balancer-ip" = google_compute_address.ingress.address
          }
        }
        extraArgs = {
          "default-ssl-certificate" = "ingress-nginx/misarch-default-tls"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.ingress_nginx,
    kubernetes_secret.default_tls,
  ]
}
