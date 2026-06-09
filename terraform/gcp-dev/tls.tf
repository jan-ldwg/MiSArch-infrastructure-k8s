resource "tls_private_key" "ingress" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ingress" {
  private_key_pem = tls_private_key.ingress.private_key_pem

  subject {
    common_name  = "misarch-dev"
    organization = "MiSArch Dev"
  }

  validity_period_hours = 8760

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]

  ip_addresses = [
    google_compute_address.ingress.address,
    "127.0.0.1",
  ]

  dns_names = [
    "localhost",
  ]
}

resource "kubernetes_secret" "default_tls" {
  metadata {
    name      = "misarch-default-tls"
    namespace = kubernetes_namespace.ingress_nginx.metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.ingress.cert_pem
    "tls.key" = tls_private_key.ingress.private_key_pem
  }

  depends_on = [kubernetes_namespace.ingress_nginx]
}
