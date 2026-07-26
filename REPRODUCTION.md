# CNAE Group 4 MiSArch Resilience Refactoring

This document describes the complete process to deploy our refactored system to Google Kubernetes Engine, run an experiment using our script and visualize the results.

This repository contains numerous branches with the baseline, various refactorings and the final system. The three most important steps (vanilla, new baseline and final refactored system) are also marked via releases in the GitHub Repo.

| Branch                       | Description                                                                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `vanilla`                    | as provided by MiSArch + Terraform for cluster + minimum necessary fixes for deployment + experiment scripts |
| `the_new_baseline`           | various performance and stability improvements                                                               |
| `main`                       | final refactored system with circuit breakers, retries, replicas and probes                                  |
|                              |                                                                                                              |
| `circuit_breaker`            | tests with circuit breaker                                                                                   |
| `discount_probes_experiment` | tests with probes on discount service                                                                        |
| `maxim_dapr_v3`              | tests with retries                                                                                           |
| `replicas`                   | tests replicas for crucial services                                                                          |
|                              |                                                                                                              |
|                              | **Test branches not merged into final system**                                                               |
|                              |                                                                                                              |
| `order-test-jan`             | various tried refactorings to improve stability and observability of order service                           |
| `jan-hpa`                    | tests with HPA for the services                                                                              |
| `keycloak-probes2`           | tests improved probes for Keycloak                                                                           |

To allow for better comparison, we kept the original multi-repo structure. Below is a list of all repos which we forked.

| Repo     | Fork                                          | Changes                                                   |
| -------- | --------------------------------------------- | --------------------------------------------------------- |
| catalog  | https://github.com/frankakn7/misarch-catalog  | Improves logging and performance                          |
| invoice  | https://github.com/frankakn7/misarch-invoice  | Bug fixes                                                 |
| order    | https://github.com/frankakn7/misarch-order    | Adds tracing and improves performance                     |
| discount | https://github.com/frankakn7/misarch-discount | Improves logging and performance                          |
| testdata | https://github.com/frankakn7/misarch-testdata | Adds short wait to script and adds vendor address seeding |
| keycloak | https://github.com/jan-ldwg/keycloak          | Enables health endpoint and startup without rebuild       |

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

Make sure gcloud CLI is connected to the right Google Cloud account and project. To change to a different project run

```sh
gcloud init
```

# Deploying the GKE cluster

Clone the git repository with the Terraform templates

```sh
git clone https://github.com/jan-ldwg/MiSArch-infrastructure-k8s.git

```

You will need a GCS bucket for the Terraform state. You can create it using:

```sh
gcloud storage buckets create gs://<YOUR UNIQUE BUCKET NAME> --location=europe-west3
```

Go to `cluster/main.tf` and change the bucket name in line 3 to your bucket name.

Add a `terraform.tfvars` file to the `cluster` directory according to the `terraform.tfvars.example`. It will have to include the id of your GCP project.

Then open a terminal, navigate to the cluster directory and apply the Terraform configuration:

```sh
cd cluster
terraform init
terraform apply
```

Wait for a few more minutes after the cluster was created to make sure the Kubernetes control plane is running nominally.

# Deploying MiSArch onto the cluster

Add a `terraform.tfvars` file in the project root. It should follow the `terraform.tfvars.example`. You will have to adjust the name of the GCS bucket to the one you set as the state backend for the cluster terraform.

Open a terminal in the project root and apply the main Terraform configuration.

```sh
terraform init
terraform apply
```

Wait until the Terraform configuration has been applied. Then wait for a few more minutes for the `misarch-testdata` job to finish. You can use a tool like k9s to see the status of the job.

When this is done, you can now access the store web page under the IP-address output as `global_domain`.

# Running an experiment

Open a new terminal in the project root. Run the python script. The only argument needed is the filename of the experiment configuration you want to use. For more details see `experiments/README.md`.

```sh
python3 experiments/runner/main.py --file="04realisticBaselineLow.json"
```

# Analyzing an experiment

After the experiment has finished the result will have been saved to a folder with the experiment UUID in `experiments/results`. To generate plots of the experiment run the analysis script. The plots can then be found in the `plots` folder of the experiment folder. For more details see `experiments/analysis/README.md`.

```sh
python3 ./experiments/analysis/plot_results.py --files ./experiments/results/<EXPERIMENT ID>/results.csv --output-dir ./experiments/results/<EXPERIMENT ID>/plots --all
```

# Teardown system

Open a terminal in the root of the project. Then do

```sh
terraform destroy
cd cluster
terraform destroy
```
