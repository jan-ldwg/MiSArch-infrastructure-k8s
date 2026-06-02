## Set up MiSArch on GKE

Before getting started make sure you have Terraform, Helm and gcloud CLI installed

```sh
terraform version
```

```sh
gcloud version
```

```sh
helm version
```

You also need the gke-auth-plugin

```sh
  gcloud components install gke-gcloud-auth-plugin
```

Clone the git repository with the Terraform templates

```sh
git clone https://github.com/JulianLegler/MiSArch-infrastructure-k8s.git

```

Make sure gcloud CLI is connected to the right Google Cloud account and project. To change to a different project run

```sh
gcloud init
```

Initialize Terraform

```sh
terraform init
```

The provided Terraform scripts do not create a new Kubernetes cluster on GKE so this has to be set up beforehand.

In the Google Cloud web ui enable the Kubernetes Engine API.

Then create a small Kubernetes cluster. This will take a few minutes.

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

e2-standard-4 instance has 4 vCPUs (x86) and 16G memory.

Make sure that kubectl (and Terraform) are pointing at the just created cluster:

```sh
kubectl config current-context
```

Now you can begin with the installation of MiSArch

```sh
terraform plan
```

The generated plan is very long. To quickly check that Terraform can make changes to the cluster we will just create the namespace for now

```sh
terraform apply -target=kubernetes_namespace.misarch
```

We can check with kubectl that the namespace was correctly created

```sh
kubectl get namespaces
```

Now we can apply the rest of the Terraform plan. This will take a few minutes.

```sh
terraform apply
```

We also need an ingress for our cluster so we will install Ingress-Nginx Controller. Note that this project is depracated and a replacement should be investigated.

```sh
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

To get the public IP address you can run this command:

```sh
kubectl get service --namespace ingress-nginx ingress-nginx-controller --output wide --watch
```

EXTERNAL-IP is the address you need to test out the application in a web browser.

The products might take a few more minutes to appear in the frontend.

If you want to acces one of the dashboards (e.g. Grafana) you have to forward the port

## Grafana

```sh
kubectl port-forward svc/prometheus-stack-grafana -n misarch 3000:80
```

usernam: admin
password:

```sh
kubectl get secret -n misarch prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

## InfluxDB

```sh
kubectl port-forward svc/influxdb -n misarch 4000:80
```

Credentials unknown

## Keycloak

EXTERNAL_IP/keycloak

username: admin
password: admin

## Experiment

```sh
kubectl port-forward svc/misarch-experiment-config-frontend 8080:80 -n misarch
```

The experiment frontend is reachable at EXTERNAL-IP/frontend.

# Deleting the cluster

After you are done you can delete the cluster again

First delete all volumes

```sh
kubectl delete pvc --all -A
```

Check that there are no disks left running

```sh
gcloud compute disks list --filter="name~'pvc-' AND region:europe-west3"
```

Then delete the cluster

```sh
gcloud container clusters delete misarch-cluster \
   --region=europe-west3
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

## ToDos

- Image service is broken
- restocking items is broken //fixed by enabling replica set for mongodb and configuring auth
- Frontend for experiments not reachable //fixed the deployment, be careful with the path
- Credentials for InfluxDB missing
- Understand which metrics are already collected
- Make all dashboards reachable without port forwarding (configure ingress controller)
- Cant run experiments because of a hardcoded URL (gropius.dev) in the terraform scripts
- figure out why `kubernetes_persistent_volume_claim.misarch_experiment_executor_pvc` can not be created //fixed deployment
