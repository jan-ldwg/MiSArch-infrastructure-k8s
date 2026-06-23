Note: This is the documentation that can be found in the experiment-executor-frontend

# ChaosToolkit Failure Configuration

The ChaosToolkit is a powerful, extensible tool for defining and executing chaos experiments in cloud-native systems.
It allows you to inject failures, observe system behavior, and validate resiliency through declarative experiments written.

⚠️ In this editor, only JSON and no YAML is supported.

This interface lets you configure chaos experiments using ChaosToolkit, with optional pauses, probes, and steady-state hypotheses.
For full details, refer to the ChaosToolkit documentation.

Interface Overview
You can build a sequence of chaos experiments that include:

- A Steady-State Hypothesis: Define what “normal” looks like upfront before the experiment.
- Probes: Validate system behavior before/after actions.
- Actions: Inject failure into the system.
- Pauses: Add delays before or after steps.

### Configuration Structure

For a full example and reference see the 📚 ChaosToolkit documentation.

A ChaosToolkit experiment consists of the following key elements:

🧪 Steady-State Hypothesis
Defines the normal operating conditions of your system.
The experiment will only proceed if these checks pass.
The steady-state hypothesis is optional (add or remove using the '+' or 'x' buttons).

🔍 Probes: Assertions about the system (e.g. HTTP status, metrics)
📌 Each probe uses:
Name: Logical name for readability
Tolerance: Expected result or threshold (this can be any sort of JSON value or object fitting to the function)
Provider Type: probe
Provider: The method of measurement (http, process, or python)
Secrets: Optional chaostoolkit secrets to use in the provider (e.g. API keys, tokens)
💡 Provider examples and explanations are provided below.

🔁 Method (Experiment Steps)
The method is a list of actions and optional pauses to inject chaos.
A method can either be an action (to apply a failure) or a probe (to observe system behavior):

⚙️ Actions: Define the failures to apply (e.g. stop service, introduce latency)
🔍 Probes: Run during the experiment to observe behavior
⏸️ Pauses: Insert delays between steps using (in seconds)
📌 Each probe or action uses:
Name: Logical name for readability
Tolerance (probe only): Expected result or threshold (this can be any sort of JSON value or object fitting to the function)
Provider Type: probe
Provider: The method of execution/measurement (http, process, or python)
Secrets: Optional chaostoolkit secrets to use in the provider (e.g. API keys, tokens)
💡 Provider examples and explanations are provided below.

🧰 Provider Examples
ChaosToolkit supports three provider types that define how actions and probes are executed: http, process, or python.
For a full list of available extensions, see the 📚 ChaosToolkit Extensions documentation.

🐍 Python Provider
The Python provider allows you to use Python functions of chaos-toolkit extensions.
For the Kubernetes provider, see the 📚 chaosk8s documentation.
These examples show how to kill the containers of the MiSArch gateway in Kubernetes:

```json
{
  "type": "python",
  "module": "chaosk8s.pod.actions",
  "func": "terminate_pods",
  "arguments": {
    "label_selector": "app=misarch-gateway",
    "ns": "misarch"
  }
}
```

module: Fully qualified Python module (must be an existing extension)
func: Function name to call
arguments: Dictionary of keyword arguments and values (depends on the specific function documentation)
🔬 Most chaos-toolkit extensions rely on specific Python functions.

🌐 HTTP Provider
The HTTP provider is used to perform HTTP requests for probing or triggering external services.

The example below shows how to perform a simple HTTP GET request to an example URL:

```json
{
  "type": "http",
  "arguments": {
    "example": "true"
  },
  "url": "https://example.com",
  "method": "GET",
  "headers": {
    "Content-Type": "application/json"
  },
  "expected_status": 200,
  "timeout": "10"
}
```

method: HTTP method (GET, POST, etc.)
url: Full URL to call
expected_status: (Optional) Expected HTTP status code
timeout: Timeout in seconds
arguments: (Optional) Additional query parameters (GET) or body data (POST)
⚠️ The HTTP provider is most often used for probes (health checks, response validation).

🖥️ Process Provider
The process provider allows running shell commands or scripts on the system running the experiment.

The example below shows how to terminate the nginx process using the killall command:

```json
{
  "type": "process",
  "name": "terminate nginx",
  "provider": {
    "type": "process",
    "path": "killall",
    "arguments": ["nginx"]
  }
}
```

path: The command to run (e.g., killall, bash)
arguments: Optional list of arguments
⚠️ Use this for OS-level fault injection or local health probes.

### Example

The following full examples demonstrates a steady-state hypothesis that checks if the catalog service is healthy, followed by a method that
introduces a failure by killing the gateway containers and then starting them again:

Kubernetes:

```json
{
  "title": "test-uuid:v1",
  "description": "test-uuid:v1",
  "steady-state-hypothesis": {
    "title": "Pod is running",
    "probes": [
      {
        "type": "probe",
        "name": "Pod is running",
        "provider": {
          "type": "python",
          "module": "chaosk8s.probes",
          "func": "deployment_available_and_healthy",
          "arguments": {
            "name": "misarch-gateway",
            "ns": "misarch"
          }
        },
        "tolerance": true
      }
    ]
  },
  "method": [
    {
      "type": "action",
      "name": "Kill Pods",
      "provider": {
        "type": "python",
        "module": "chaosk8s.pod.actions",
        "func": "terminate_pods",
        "arguments": {
          "label_selector": "app=misarch-gateway",
          "ns": "misarch"
        }
      },
      "pauses": {
        "before": 12,
        "after": 7
      }
    }
  ]
}
```

# Gatling Arriving Users Configuration

The MiSArch Experiment Tool uses Gatling to simulate user traffic for experiments.
For detailed documentation on Gatling, refer to the 📚 Gatling documentation.

The Gatling Arriving Users configuration allows you to define the user traffic for your experiments based on your work (scenarios).

⚙️ Configuration Structure
You can configure the user traffic for each scenario in your experiment:

📝 Scenario: Select the scenario that you want to modify the user traffic for.
⏱️ Duration: The duration of the user traffic in seconds for the selected scenario (e.g. 60).
⏳ From-/To-Second: The time range in seconds the user traffic should be applied for the selected scenario (e.g. 0 to 60).
👥 Arriving Users: The number of arriving users per second in the time range for the selected scenario (e.g. 10).
🔄 Reset: Resets the configuration for the selected scenario to the last saved values.
📝 Concepts
The following definitions are important to understand how Gatling simulates user traffic:

💪 Work: The actual domain-specific interaction of users with the system, such as browsing a catalog or placing an order (in Gatling this is called a 'scenario').
👥 Load: The number of users that are currently interacting with the system, based on the work.
🌊 Workload: The combination of work and load, i.e. the actual total requests sent by users to the system.
📭 Open Workload: Open Workload means that users are continuously arriving at the system, simulating a steady stream of traffic, all executing an entire scenario.
📫 Closed Workload: Means a limit of users is set, and the load is kept constant by replacing users that leave the system with new ones, simulating a pre-defined number of users executing a scenario.
💡 MiSArch Experiment Tool uses Open Workloads to simulate user traffic, meaning users continuously arrive at the system and execute a scenario, as they are more realistic.

# Warm-Up Configuration

The MiSArch Experiment Tool allows you to configure a warm-up phase for your experiments.
This is useful to ensure that the system is in a stable state before the actual experiment starts.

The warm-up phase uses a constant (closed) user load for all scenarios for a configured period.

💡 If you also configure a steady-state hypothesis, the warm-up phase will be executed before the steady-state hypothesis phase.

⚙️ Configuration Structure
☑️ Warm-Up Yes / No: Enable or disable the warm-up phase. If you do not want to use a warm-up phase use the 'x' button to remove the configuration.
👥 Static User Rate: The constant number of users that will be used for the warm-up phase for each scenario (e.g. 10).
⏳ Duration: The duration of the warm-up phase in seconds (e.g. 60).

# MiSArch Experiment Failure Configuration

The MiSArch Experiment Failure feature allows users to simulate failures of specific MiSArch components.

It is called MiSArch Experiment Failure and is a custom solution, which is part of MiSArch.
For more information about the MiSArch Experiment Configuration, refer to the 📚 MiSArch documentation.

The MiSArch Experiment Failure operates using a sidecar container that proxies all network traffic and resides in the same pod as the MiSArch component.
This traffic can be intercepted and modified to emulate a range of network-based failure scenarios.

MiSArch leverages Dapr features such as PubSub and service-mesh, which can be selectively failed.
If you're not familiar with Dapr, refer to the 📚 Dapr documentation for more information.

In addition to network-related failures, the sidecar container can also simulate resource exhaustion (CPU, memory).

⚠️ Note: Container configuration is static, but the failure behavior can be non-deterministic using probability for failure.

🛠️ Interface Overview
You can configure a series of failure sets containing different failure configurations.
A failure configuration targets exactly one service.
In between two failure sets you can configure optional pauses.

⚠️ Note: Once applied, a failure configuration persists until it is cleared or overwritten.

🧹 Clear the config by creating a new failure set with a new failure configuration that has only null values for the target service (Delete all entries using the 'x'-button).
📝 Overwrite the config by creating a new failure set with a new failure configuration setting a new target value for the target
service.

⚙️ Configuration Structure
Each configuration includes the following components:

🔹 Failure Set
A Failure Set is a collection of one or more failures applied at the same time.

⏳ Pauses: configure pauses in seconds before and after setting the configuration of the failure set
⚠️ Avoid applying more than one failure to the same component within a single set.

🔸 Failure
A Failure targets a specific MiSArch component.

Service Name is required
All other fields are optional
Service Name
The simple (logical) name of the affected service (e.g. catalog, gateway).

PubSub Deterioration
Simulates degraded performance in Dapr PubSub by introducing:

⏱️ Delay (ms): Time added before forwarding a message (e.g. 1000)
🎲 Delay Probability: Likelihood of applying the delay (e.g. 0.57)
❌ Error Rate: Proportion of invocations that will fail (e.g. 0.57)
💡 This applies to all PubSub events for the specified service.

Service Invocation Deterioration
Simulates network errors/delays on HTTP requests to specific paths.

📍 HTTP Path to Fail: Target path (e.g. /)
⏱️ Delay (ms): Delay before response (e.g. 1000)
🎲 Delay Probability: Chance the delay will be applied (e.g. 0.57)
📉 HTTP Error Code: Response code to return (e.g. 500)
🎲 Error Probability: Chance the error code is returned (e.g. 0.57)
💡 You can configure multiple paths using the '+' button.

Artificial Memory Usage
Simulates high memory consumption by allocating memory in the sidecar.

💾 Memory Usage: Memory used in bytes (e.g. 1000000000 for 1 GiBi)
Artificial CPU Usage
Simulates high CPU load via a busy loop in the sidecar.

🌀 Usage Duration (ms): Time the CPU is busy (e.g. 1000)
⏸️ Pause Duration (ms): Time the loop pauses (e.g. 1000)
⚠️ If no pause is configured, the usage runs continuously and nothing will be processed anymore.

💡 Example
The following example demonstrates a failure set that applies a series of failures to the catalog service with a pause before and after the
set:

```json
{
  "failureSets": [
    {
      "failures": [
        {
          "serviceName": "catalog",
          "pubsubDeterioration": {
            "delayMs": 1000,
            "delayProbability": 0.57,
            "errorRate": 0.57
          },
          "serviceInvocationDeterioration": {
            "httpPathToFail": "/",
            "delayMs": 1000,
            "delayProbability": 0.57,
            "httpErrorCode": 500,
            "errorProbability": 0.57
          },
          "artificialMemoryUsage": {
            "memoryUsageBytes": 1000000000
          },
          "artificialCpuUsage": {
            "usageDurationMs": 1000,
            "pauseDurationMs": 1000
          }
        }
      ],
      "pauses": {
        "before": 12,
        "after": 34
      }
    }
  ]
}
```

# Experiment Goals Configuration

The Goal Configuration allows you to define measurable goals in terms of user metrics such as latency for your experiments.
The configuration can be either done manually or automatically using an automated steady-state-hypothesis.

You can switch between the two modes using the Auto / Manual button in the top right corner of the configuration dialog.

⚙️ Manual Configuration
The manual configuration allows you to define the goal in terms of a metric and a threshold.
It also lets you define a color for the goal, which will be used in the resulting Grafana dashboard to visualize the goal.
The dashboard will only highlight the goal if the metric is above the threshold.

📈 Metric
A metric is a measurable value that can be used to evaluate the performance of your experiment.
Each metric can be assigned a maximum threshold value:

⏳ For time-based metrics assign the maximum allowed response time in milliseconds (e.g. 800)
📊 For percentage-based metrics assign the maximum allowed percentage (e.g. 95)
Metrics are collected by Gatling and parsed by the MiSArch Experiment Tool, to be evaluated and displayed in Grafana.
The following metrics are available:

| Metric                                               | Description                                                                                               |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| percentage reqs with resp. time t < 800 ms           | Maximum percentage of requests with a response time below 800ms from all requests (e.g. 90).              |
| percentage reqs with resp. time 800 ms < t < 1200 ms | Maximum percentage of requests with a response time between 800ms and 1200ms from all requests (e.g. 20). |
| percentage reqs with resp. time t > 1200 ms          | Maximum percentage of requests with a response time above 1200ms from all requests (e.g. 20).             |
| percentage failed requests                           | Maximum percentage of failed requests from all requests (e.g. 5).                                         |
| percentage mean requests/sec ok                      | Maximum percentage of successful requests per second from all requests per second (e.g. 80).              |
| percentage mean requests/sec ko                      | Maximum percentage of failed requests per second from all requests per second (e.g. 20).                  |
| min response time                                    | Highest allowed minimum response time of all requests in milliseconds (e.g. 800).                         |
| mean response time                                   | Highest allowed average response time of all requests in milliseconds (e.g. 800).                         |
| max response time                                    | Highest allowed maximum response time of all requests in milliseconds (e.g. 800).                         |
| min response time ok                                 | Highest allowed minimum response time of successful requests in milliseconds (e.g. 800).                  |
| mean response time ok                                | Highest allowed average response time of successful requests in milliseconds (e.g. 800).                  |
| max response time ok                                 | Highest allowed maximum response time of successful requests in milliseconds (e.g. 800).                  |
| min response time ko                                 | Highest allowed minimum response time of failed requests in milliseconds (e.g. 800).                      |
| mean response time ko                                | Highest allowed average response time of failed requests in milliseconds (e.g. 800).                      |
| max response time ko                                 | Highest allowed maximum response time of failed requests in milliseconds (e.g. 800).                      |
| 50th percentile response time                        | Highest allowed response time for the 50th percentile of all requests in milliseconds (e.g. 800).         |
| 75th percentile response time                        | Highest allowed response time for the 75th percentile of all requests in milliseconds (e.g. 800).         |
| 95th percentile response time                        | Highest allowed response time for the 95th percentile of all requests in milliseconds (e.g. 800).         |
| 99th percentile response time                        | Highest allowed response time for the 99th percentile of all requests in milliseconds (e.g. 800).         |
| 50th percentile response time ok                     | Highest allowed response time for the 50th percentile of successful requests in milliseconds (e.g. 800).  |
| 75th percentile response time ok                     | Highest allowed response time for the 75th percentile of successful requests in milliseconds (e.g. 800).  |
| 95th percentile response time ok                     | Highest allowed response time for the 95th percentile of successful requests in milliseconds (e.g. 800).  |
| 99th percentile response time ok                     | Highest allowed response time for the 99th percentile of successful requests in milliseconds (e.g. 800).  |
| 50th percentile response time ko                     | Highest allowed response time for the 50th percentile of failed requests in milliseconds (e.g. 800).      |
| 75th percentile response time ko                     | Highest allowed response time for the 75th percentile of failed requests in milliseconds (e.g. 800).      |
| 95th percentile response time ko                     | Highest allowed response time for the 95th percentile of failed requests in milliseconds (e.g. 800).      |
| 99th percentile response time ko                     | Highest allowed response time for the 99th percentile of failed requests in milliseconds (e.g. 800).      |

🪄 Auto Configuration
The MiSArch Experiment Tool provides an automatic configuration for the goals of your experiment.
It configures every metric you find above in the Manual Configuration section, based on the results of a steady-state hypothesis execution.

🎯 The automatic configuration allows the system to automatically define goals in terms of a steady-state hypothesis.
📈 Before running the experiment, your scenarios will be executed with a constant user rate for a configured duration.
🛑 After this execution the collected metrics will be used as the thresholds for the goals.
🧮 For time-based metrics you can define a factor to multiply the collected values with, to define a more relaxed goal.
🔺 All thresholds exceeded in the actual run will be displayed in the resulting Grafana dashboard in red color.
⚙️ Configurations:
Rate: The constant user rate for the steady-state hypothesis execution in users per second (e.g. 10).
Duration: The duration of the steady-state hypothesis execution in seconds (e.g. 60).
Factor: The factor to multiply the collected values with for time-based metrics (e.g. 1.2).
💡 If you also configure a warm-up phase, the warm-up phase will be executed before the steady-state hypothesis phase.

# Work Configuration

The MiSArch Experiment Tool uses Gatling to simulate user traffic for experiments.
For detailed documentation on Gatling, refer to the 📚 Gatling documentation.

The work configuration in the MiSArch Experiment Tool allows you to define the work in the form of Gatling scenarios for your experiments.

💡 Concepts
Gatling is written in Scala and uses a domain-specific language (DSL) to define scenarios.
The DSL is a set of methods that can be used to define the behavior of users in the system.
It is available in Scala, Java and Kotlin.

⚠️ The MiSArch Experiment Tool only supports the Kotlin DSL for defining scenarios.

Gatling scenarios are simulating user sessions, which are sequences of requests that a user would perform in a real-world scenario.
You can store session data in the session object, which is passed between requests.

How is a scenario structured?

📦 Package and Imports: All scenarios must be in the org.misarch package and import the necessary Gatling classes.

📝 Scenario Definition: Each scenario is defined as a Kotlin function that starts with a unique name:

val abortedBuyProcessScenario = scenario("abortedBuyProcessScenario")
🔄 Scenario Steps: The scenario consists of a series of steps that define the behavior of users in the system, which are chained together using Kotlin's . operator:

1️⃣ exec {...}: Executes a block of code, which can be used to perform actions such as storing session data.
.exec { session ->
// Store and retrieve session data
session.getString("my-key", "my-value")
session.set("my-other-key", "my-other-value")
}
2️⃣ exec (http()): Executes the HTTP request based on the http() chain. The response of a request can be stored in the session object using the check() method and retrieved in following .exec{...} blocks.
.exec(
http("Get Example")
.get("http://example.org")
.formParam("example", "example")
.check(jsonPath("$.example").saveAs("my-key"))

)
3️⃣ .pause(Duration.ofMillis(X), Duration.ofMillis(X)): Pauses the scenario for a specified duration, which is in between the range of the first duration and the second duration. This can be used to simulate user think time or delays between requests.
.pause(Duration.ofMillis(1000), Duration.ofMillis(2000))
⚠️ Note: The steps must always be defined like this: exec {...} then exec(http()...) then .pause(Duration.ofMillis(X), Duration.ofMillis(X)), each in a new line in order for the MiSArch Experiment Tool to correctly parse the scenario and calculate the approximate requests.

💡 Tip: If you want to create complex custom scenarios, leveraging all features of the Gatling DSL, you should use a proper Kotlin IDE to write the scenario.

⚙️ Configuration Structure
You can configure the work for your experiment in the following way:

📝 You can configure a work file for each scenario in your experiment based on the examples and explanations above and the Gatling Kotlin DSL.
➕ You can add or remove scenarios using the '+' and 'x' buttons.
⚠️️ When creating a new scenario you also must configure new load for it using the Load Configuration.

💡 Example
Here is an example of a scenario that simulates a user first fetching an access token from Keycloak then browsing a catalog and putting an item into the shopping cart.
Note, that MiSArch uses GraphQL for the API, so the scenario uses GraphQL queries and mutations to interact with the system.
A list of queries and mutations can be found in the 📚 MiSArch documentation.

```kotlin
package org.misarch

import io.gatling.javaapi.core.CoreDsl.\*
import io.gatling.javaapi.http.HttpDsl.http
import java.time.Duration

val abortedBuyProcessScenario = scenario("abortedBuyProcessScenario")
.exec { session ->
session.set("targetUrl", "http://gateway:8080/graphql")
}
.exec(
http("Get Access Token")
.post("http://keycloak:80/keycloak/realms/Misarch/protocol/openid-connect/token")
.formParam("client_id", "frontend")
.formParam("grant_type", "password")
.formParam("username", "gatling")
.formParam("password", "123")
.check(jsonPath("$.access_token").saveAs("accessToken"))
    )
    .pause(Duration.ofMillis(0), Duration.ofMillis(0))
    .exec { session ->
        session.set(
            "productsQuery",
            "{ \"query\": \"query { products(filter: { isPubliclyVisible: true }, first: 10, orderBy: { direction: ASC, field: ID }, skip: 0) { hasNextPage nodes { id internalName isPubliclyVisible } totalCount } }\" }"
        )
    }
    .exec(
        http("products").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{productsQuery}"))
            .check(jsonPath("$.data.products.nodes[0].id").saveAs("productId"))
)
.pause(Duration.ofMillis(4000), Duration.ofMillis(10000))
.exec { session ->
val productId = session.getString("productId")
session.set(
"productQuery",
"{ \"query\": \"query { product(id: \\\"$productId\\\") { categories { hasNextPage  totalCount } defaultVariant { id isPubliclyVisible averageRating } id internalName isPubliclyVisible variants { hasNextPage  totalCount } } }\" }"
        )
    }
    .exec(
        http("product").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{productQuery}"))
            .check(jsonPath("$.data.product.defaultVariant.id").saveAs("productVariantId"))
)
.pause(Duration.ofMillis(50), Duration.ofMillis(150))
.exec { session ->
session.set(
"usersQuery",
"{ \"query\": \"query { users(first: 10, orderBy: { direction: ASC, field: ID }, skip: 0) { hasNextPage nodes { id birthday dateJoined gender username addresses { nodes { id } } } } }\" }"
)
}
.exec(
http("users").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{usersQuery}"))
.check(jsonPath("$.data.users.nodes[0].addresses.nodes[0].id").saveAs("addressId"))
            .check(jsonPath("$.data.users.nodes[0].id").saveAs("userId"))
)
.pause(Duration.ofMillis(50), Duration.ofMillis(150))
.exec { session ->
val userId = session.getString("userId")
val productVariantId = session.getString("productVariantId")
session.set(
"createShoppingcartItemMutation",
"{ \"query\": \"mutation { createShoppingcartItem( input: { id: \\\"$userId\\\" shoppingCartItem: { count: 1 productVariantId: \\\"$productVariantId\\\" } } ) { id } }\" }"
)
}
.exec(
http("createShoppingcartItemMutation").post("#{targetUrl}").header("Content-Type", "application/json").header("Authorization", "Bearer #{accessToken}").body(StringBody("#{createShoppingcartItemMutation}"))
.check(jsonPath("$.data.createShoppingcartItem.id").saveAs("createShoppingcartItemId"))
)
.pause(Duration.ofMillis(0), Duration.ofMillis(0))
```
