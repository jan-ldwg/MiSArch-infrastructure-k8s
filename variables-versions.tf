variable "MONGODB_VERSION" {
  type    = string
  default = "7.0.15"
}

variable "POSTGRES_VERSION" {
  type    = string
  default = "16"
}

variable "KEYCLOAK_VERSION" {
  type    = string
  default = "23"
}

variable "KEYCLOAK_ADMIN_PASSWORD" {
  sensitive = true
  type      = string
  default   = "admin"
}

variable "MISARCH_KEYCLOAK_VERSION" {
  type    = string
  default = "main@sha256:25af90b2b6ff10ed6087257d4c21643b3be048898080de3f60aadce9d935d462"
}

variable "KEYCLOAK_USER_EVENTS_PLUGIN_VERSION" {
  type    = string
  default = "main"
}

variable "MINIO_VERSION" {
  type    = string
  default = "2024.5.10"
}

variable "RABBITMQ_VERSION" {
  type    = string
  default = "3.13.2"
}

variable "MISARCH_ADDRESS_VERSION" {
  type    = string
  default = "main@sha256:bc42dcd4d41ea7ee5285286617ceb9c66a2fa7689a339794e9d3c657806a84b8"
}

variable "MISARCH_CATALOG_VERSION" {
  type    = string
  default = "main@sha256:df9572d60c8049fe032d5868fe6028006e585a1ae8625b860a353898f0f82f69"
}

variable "MISARCH_DISCOUNT_VERSION" {
  type    = string
  default = "main@sha256:0186c5c1618c75432db560a71042d5e9a99f7d4697cff2619585222fc2b446b9"
}

variable "MISARCH_FRONTEND_VERSION" {
  type    = string
  default = "main@sha256:9513e4214892c79f32ca7ce32f609b5723cc529dc35c4888234dad8c7d7d8341"
}

variable "MISARCH_GATEWAY_VERSION" {
  type    = string
  default = "main@sha256:fc69a2754d99a5e621847a738decf3c4f0da8c06db567dce7f170535ff5f2b0c"
}

variable "MISARCH_INVENTORY_VERSION" {
  type    = string
  default = "main@sha256:e507706edcbff87583b1640a7376484159d5c15707e244f4617e5d6c782bf7e7"
}

variable "MISARCH_INVOICE_VERSION" {
  type    = string
  default = "ghcr.io/frankakn7/misarch-invoice:main"
}

variable "MISARCH_MEDIA_VERSION" {
  type    = string
  default = "main@sha256:69e77b4f655065907bf301c6cb6a1deea90daa7b91bb1e49257b85b0923381c8"
}

variable "MISARCH_NOTIFICATION_VERSION" {
  type    = string
  default = "main@sha256:da42e698b960fded60ce53d7ab7f5fb4aa5be7c4609e240abffa24de1cfca735"
}

variable "MISARCH_ORDER_VERSION" {
  type    = string
  default = "main@sha256:9029c69089a58f5fd0cf147bd3c44ec51082a47ed6af7a65ee482da79cad81ac"
}

variable "MISARCH_PAYMENT_VERSION" {
  type    = string
  default = "main@sha256:80456ce613c57561eac413673bafd0c5d666d49bec579d7afb317546bd6b8db0"
}

variable "MISARCH_RETURN_VERSION" {
  type    = string
  default = "main@sha256:6e981fc460a3f1029e71874f6694d4c74aa6543ed17414d6d0d3e5a41a705054"
}

variable "MISARCH_REVIEW_VERSION" {
  type    = string
  default = "main@sha256:5dd69546547d5ddedd4765c9c1d54403519ab10736aac6f373175fa8ba495b36"
}

variable "MISARCH_SHIPMENT_VERSION" {
  type    = string
  default = "main@sha256:5b9e80ea0d69bf614e03c408c96dcb1762a28603ecc6035efe0bfa2efe6c2b76"
}

variable "MISARCH_SHOPPINGCART_VERSION" {
  type    = string
  default = "main@sha256:5eec202ff351e6e0eb2cb183f82c76aeda19874de14054705d01035864793640"
}

variable "MISARCH_SIMULATION_VERSION" {
  type    = string
  default = "main@sha256:bd6ce3516dc0ea4fd4d8ab3e9717554d9fe679e82b2e93303e77b53020f33f11"
}

variable "MISARCH_TAX_VERSION" {
  type    = string
  default = "main@sha256:729f0e3742d3a0f06a991eb09f1e69de476de806e72c60b3db825116864042a4"
}

variable "MISARCH_USER_VERSION" {
  type    = string
  default = "main@sha256:a8c74c5bb88b7b70025d8f356cb0ed5221587dbe61235fe013134697e2530056"
}

variable "MISARCH_WISHLIST_VERSION" {
  type    = string
  default = "main@sha256:01ea887a1477f1bb87e93c7c8ca2bdb1878a72902cd39f15a2ee745cf557825a"
}

variable "MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION" {
  type    = string
  default = "main@sha256:874a7e6af421edc037bae45fbc2491284bc9c1fcba92ad06811f774aaf9ea1dd"
}

variable "OTEL_COLLECTOR_VERSION" {
  type    = string
  default = "0.128.0"
}

variable "JAEGER_VERSION" {
  type    = string
  default = "1.66.0"
}

variable "MISARCH_EXPERIMENT_CONFIG_VERSION" {
  type    = string
  default = "main@sha256:253fa0c54b9452e49a6a9ab53c1d57e62eb6aff2415ca06334aa584c28f3c6a4"
}

variable "MISARCH_EXPERIMENT_CONFIG_FRONTEND_VERSION" {
  type    = string
  default = "main@sha256:624f0a3bfe1a34a7793582f50b7398c543b90368564f53e15df5314bbc9459c2"
}

variable "MISARCH_EXPERIMENT_EXECUTOR_VERSION" {
  type    = string
  default = "main@sha256:634c8da49d3f4b287e5cfed349a723abda8443400aa7ef155440f9f8eb4bf169"
}

variable "MISARCH_EXPERIMENT_EXECUTOR_FRONTEND_VERSION" {
  type    = string
  default = "main@sha256:241f15b7fd673bc3bcb5637abba74ef9cd41ea92630236f8e0f917f7d0268498"
}

variable "MISARCH_GATLING_EXECUTOR_VERSION" {
  type    = string
  default = "main@sha256:cd7b008a38f3a9361f670bea1f8153c20a4ccd106e47597d4a5a653f43927a96"
}

variable "MISARCH_CHAOSTOOLKIT_EXECUTOR_VERSION" {
  type    = string
  default = "main@sha256:1dacd63b04b8a9580aba64da76800c8d76e7bb0d2196ccaf3344cde3071e5157"
}

variable "MISARCH_TESTDATA_VERSION" {
  type    = string
  default = "ghcr.io/jan-ldwg/testdata:latest"
}
