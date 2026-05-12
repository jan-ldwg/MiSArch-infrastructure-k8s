## Bitnami August 2025 deprecation: the free `docker.io/bitnami/*` container
## images were moved to `docker.io/bitnamilegacy/*` and the original namespace
## became part of a paid Bitnami Secure Images subscription.
## See this post for more detailed information: https://github.com/bitnami/containers/issues/83267
##
## We just overwrite all the images to reference to the legacy repository

locals {
  bitnami_legacy_minio_image_overrides = <<-EOF
    global:
      security:
        allowInsecureImages: true
    image:
      registry: docker.io
      repository: bitnamilegacy/minio
    clientImage:
      registry: docker.io
      repository: bitnamilegacy/minio-client
    console:
      image:
        registry: docker.io
        repository: bitnamilegacy/minio-object-browser
    volumePermissions:
      image:
        registry: docker.io
        repository: bitnamilegacy/os-shell
    EOF

  bitnami_legacy_postgresql_image_overrides = <<-EOF
    global:
      security:
        allowInsecureImages: true
    image:
      registry: docker.io
      repository: bitnamilegacy/postgresql
    metrics:
      image:
        registry: docker.io
        repository: bitnamilegacy/postgres-exporter
    volumePermissions:
      # Enabled so a root init container chowns the freshly-provisioned PV
      # to the postgres uid (minikube hostpath does not propagate fsGroup).
      enabled: true
      image:
        registry: docker.io
        repository: bitnamilegacy/os-shell
    EOF

  bitnami_legacy_rabbitmq_image_overrides = <<-EOF
    global:
      security:
        allowInsecureImages: true
    image:
      registry: docker.io
      repository: bitnamilegacy/rabbitmq
    volumePermissions:
      image:
        registry: docker.io
        repository: bitnamilegacy/os-shell
    EOF

  bitnami_legacy_redis_image_overrides = <<-EOF
    global:
      security:
        allowInsecureImages: true
    image:
      registry: docker.io
      repository: bitnamilegacy/redis
    metrics:
      image:
        registry: docker.io
        repository: bitnamilegacy/redis-exporter
    volumePermissions:
      image:
        registry: docker.io
        repository: bitnamilegacy/os-shell
    EOF
}
