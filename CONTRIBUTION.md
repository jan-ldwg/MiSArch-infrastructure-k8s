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
  - warm up configuration
- set up overleaf project
- extended visualization script to include all endpoints
- debugged jaeger deployment
- added tracing to order service
- run initial experiments with different work scripts and load levels

## Maryam

- python script to visualize test results

## Maxim Strzebkowski

- General Work:
  - Static code analysis
  - Static project architecture analysis
  - Local deployability of services for testing
  - Designed experiment plans and infrastructure improvements
  - Initial setup, structure and design of final presentation
- Experiments:
  - Run baseline experiments with different loads to test infrastructure limits
  - Ran Dapr resilience experiments:
    - Circuit breaker experiment (determined unnecessary)
    - Retry with backoff (3 retries) which eliminated short-term failures
  - Ran startup, readiness, liveness probe experiments
  - Ran HPA experiments
  - Ran redundancy replica experiments
  - Ran final triple combined experiment
- Dapr improvements:
  - Fix Dapr error message storm during failure
- Infrastructure:
  - Added Probes:
    - startup
    - readiness
    - liveness
  - Replaced mongosh probes with TCP probes
  - Added readiness and liveness probes to Redis master
  - Fixed redis master OOM kill
  - Added Jaeger collector and UI connected to OpenTelemetry, excluding heartbeat traces
  - Fixed missing payment, shipment & simulation services
- Experiment runner improvements:
  - Added InfluxDB export Python script
  - Added Git status to experiment result export
  - Added runtime information to experiment runner
  - Improved visualization of experiment results using stacked bar charts
- Invoice service improvements:
  - Improved observability with configurable, per-step error logging
  - Fixed serialization bugs (field names, enum casing, camelCase conversion, Dapr route alignment)
  - Persisted full vendor address on upsert
- Catalog service improvements:
  - Improved observability with optional debug logging
  - Added R2DBC connection pooling
  - Added database indexes via migrations
- Discount service improvements:
  - Improved observability with optional debug logging
  - Added R2DBC connection pooling and fixed N+1 queries
  - Added database indexes on foreign keys and date filters
  - Ran load test after improvements, reducing mean query time from multiple seconds to sub one second
- Order service improvements:
  - Improved tracing instrumentation and logging
  - Fixed dependency version mismatch
  - Switched to a single reusable HTTP client
- Testdata seeding improvements:
  - Added vendor address seeding needed for invoice service