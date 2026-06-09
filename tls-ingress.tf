resource "tls_private_key" "misarch_ingress" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "misarch_ingress" {
  private_key_pem = tls_private_key.misarch_ingress.private_key_pem

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
    local.ingress_ip,
    "127.0.0.1",
  ]

  dns_names = [
    "localhost",
  ]
}

resource "kubernetes_secret" "misarch_ingress_tls" {
  metadata {
    name      = "misarch-ingress-tls"
    namespace = local.namespace
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.misarch_ingress.cert_pem
    "tls.key" = tls_private_key.misarch_ingress.private_key_pem
  }
}
