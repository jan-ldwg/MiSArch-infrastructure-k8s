## William Knöpp

- initial analysis of the project code
- refinement and formatting of baseline presentation
- vibe coded proof of concept of the automation of the experiment pipeline

## Jan Ludwig

- initial fixes to deploy on google cloud
  - fixed issue with experiment executor pvc
  - fixed issue with inventory-db not supporting transactions
  - fixed issue with grafana password
- wrote guide for deployment to google cloud
- operational refinements of system for baseline testing
  - added dashboards to the ingress config
  - terraform setup to deploy GKE cluster
  - pinning all images to latest release version
  - updated testdata image to seed database with more than one product
- initial draft of baseline presentation
- python script to automate experiment execution
  - initial gatling and chaos configs copied from William`s proof of concept
  - updated gatling script to create new user for every simulated user journey
  - integrated csv export from Maxim
  - querying of inventoryCount from graphql before and after the experiment to check for data consistency with placed orders from gatling
- set up overleaf project

## Maryam

- python script to visualize test results
