# GCP Dev Platform (GKE)

Terraform stack that provisions the MiSArch dev platform on Google Cloud:

- Custom VPC and subnet
- Regional GKE Standard cluster with autoscaling node pool
- Ingress-Nginx controller with a reserved external IP
- Self-signed TLS certificate for HTTPS

The GCS remote state bucket is created by `scripts/deploy-dev.sh bootstrap` via `gcloud` (not managed by this stack, to avoid bootstrap/import cycles).

## Prerequisites

- `gcloud` authenticated to your GCP project
- `terraform` >= 1.0.11
- `gke-gcloud-auth-plugin` (`gcloud components install gke-gcloud-auth-plugin`)
- Application Default Credentials: `gcloud auth application-default login`

## Bootstrap (first run only)

```sh
./scripts/deploy-dev.sh bootstrap
./scripts/deploy-dev.sh apply
```

Manual bootstrap:

```sh
PROJECT_ID=$(gcloud config get-value project)
BUCKET="${PROJECT_ID}-terraform-state"
gcloud storage buckets create "gs://${BUCKET}" --location=europe-west3 --uniform-bucket-level-access
gcloud storage buckets update "gs://${BUCKET}" --versioning
cd terraform/gcp-dev
cp backend.gcs.hcl.example backend.gcs.hcl   # set bucket name
terraform init -backend-config=backend.gcs.hcl
terraform apply -var="project_id=${PROJECT_ID}"
```

## Variables

See [dev.tfvars.example](dev.tfvars.example). The deploy script sets `TF_VAR_project_id` from `gcloud` automatically.

## Outputs

After apply:

```sh
terraform output ingress_external_ip
terraform output root_domain_url
```

Use `./scripts/deploy-dev.sh apply` to deploy the full MiSArch stack on top of this platform.
