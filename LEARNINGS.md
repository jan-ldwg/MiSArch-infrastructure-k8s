## Requirements

Before getting started make sure you have Terraform and gcloud CLI installed

```sh
terraform version
```

```sh
gcloud version
```

You also need the gke-auth-plugin

```sh
  gcloud components install gke-gcloud-auth-plugin
```

Clone the git repository with the Terraform templates

```sh
git clone https://github.com/jan-ldwg/MiSArch-infrastructure-k8s.git

```

Make sure gcloud CLI is connected to the right Google Cloud account and project. To change to a different project run

```sh
gcloud init
```

You will need a GCS bucket for the Terraform state. You can create it using:

```sh
gcloud storage buckets create gs://misarch-terraform-state --location=europe-west3
```

Initialize Terraform

```sh
terraform init
```

## Spin up the cluster

According to [best practices](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#stacking-with-managed-kubernetes-cluster-resources) the GKE cluster is provisioned with a separate Terraform stack.

Navigate to the cluster folder

```sh
cd ./cluster
```

Initialize Terraform in this folder

```sh
terraform init
```

And spin up the cluster

```sh
terraform apply
```

Terraform will need a few minutes to spin up the cluster.

e2-standard-4 instance has 4 vCPUs (x86) and 16G memory.

If you want kubectl access to the cluster for diagnostics or port forwarding run

```sh
gcloud container clusters get-credentials misarch-cluster \
  --zone europe-west3-a
```

## Installing MiSArch

After the cluster is up and running open a second terminal in the root of the project.

Install all MiSArch components using

```sh
terraform apply
```

Now we can apply the rest of the Terraform plan. This will take a few minutes.

```sh
terraform apply
```

The public IP-address is automatically output when everything is installed, but you can also always get it by running

```sh
terraform output global_domain
```

The products might take a few more minutes to appear in the frontend.

## Free all resources

In the root directory of the project run

```sh
terraform destroy
```

Then switch to the cluster directory and run

```sh
terraform destroy
```

## Accessing dashboards

If you want to acces one of the dashboards (e.g. Grafana) you have to forward the port

## Grafana

```sh
kubectl port-forward svc/prometheus-stack-grafana -n misarch 3000:80
```

usernam: admin
password:

```sh
terraform output grafana_admin_password
```

To access an experiment dashboard, go to the forwarded URL (
`localhost:3000/d/<EXPERIMENT_ID>`)

## Jaeger

```sh
kubectl port-forward svc/jaeger-collector -n misarch 16686:16686
```

Then open http://localhost:16686

## InfluxDB

```sh
kubectl port-forward svc/influxdb -n misarch 4000:80
```

username: admin
password: admin123

## Keycloak

EXTERNAL_IP/keycloak

username: admin
password: admin

## Experiment Config

```sh
kubectl port-forward svc/misarch-experiment-config-frontend 8080:80 -n misarch
```

## Experiment Executor

The experiment frontend is reachable at EXTERNAL-IP/frontend.

## Useful commands

Spin up cluster using gcloud CLI

```sh
gcloud container clusters create misarch-cluster \
  --region=europe-west3 \
  --num-nodes=2 \
  --machine-type=e2-standard-4 \
  --disk-size=30 \
  --disk-type=pd-standard \
  --enable-autoscaling \
  --min-nodes=2 \
  --max-nodes=6
```

```sh
gcloud container clusters delete misarch-cluster \
   --region=europe-west3
```

Get cluster kubectl is pointing at

```sh
kubectl config current-context
```

Make extra sure that there are no orphan disks! They will cause issues with future deployments!

```sh
gcloud compute disks list \
  --filter="name~'pvc-' AND zone~'europe-west3' AND -users:*" \
  --format="table(name,sizeGb,zone,status)"
```

If there are any left, run this to delete them:

```sh
gcloud compute disks list \
  --filter="name~'pvc-' AND zone~'europe-west3' AND -users:*" \
  --format="value(name,zone)" | \
while read name zone; do
  gcloud compute disks delete "$name" --zone="$zone" --quiet
done
```

Check Terraform can create resources in the cluster

```sh
terraform apply -target=kubernetes_namespace.misarch
```

Then check with

```sh
kubectl get namespaces
```

Get logs from a pod:

```sh
kubectl logs <POD_NAME> -n misarch
```

Restart a deployment to pull the latest image:

```sh
kubectl rollout restart deployment/misarch-<service> -n misarch
```

## ToDos

- Image service is broken
- restocking items is broken //fixed by enabling replica set for mongodb and configuring auth
- Frontend for experiments not reachable //fixed the deployment, be careful with the path
- Credentials for InfluxDB missing
- Understand which metrics are already collected
- Make all dashboards reachable without port forwarding (configure ingress controller)
- Cant run experiments because of a hardcoded URL (gropius.dev) in the terraform scripts
- figure out why `kubernetes_persistent_volume_claim.misarch_experiment_executor_pvc` can not be created //fixed deployment
