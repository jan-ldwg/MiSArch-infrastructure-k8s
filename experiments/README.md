# Running experiments with the runner

To ensure that experiments can be run in a repeatable way, the complete process is automated using a python script.

You can start the script by running from the root of the project. The only argument is the file with the experiment config you want to run.

```sh
python3 experiments/runner/main.py --config = "experiments.json"
```

## The experiment config file

The experiment config can contain one or more experiments you want to run. It is a simple JSON file with the following structure:

```JSON
[
  {
    "testName": "Basic test",           //
    "description": "Test with moderate load and no fault injections", //this is just to provide additional information, it is not used in the script
    "gatlingConfig": [
        {
            "fileName": "gatling/browseOnly.kt",
            "userSteps": "gatling/steadyLoad.csv"
        },
        {
            "fileName": "gatling/Buy.kt",
            "userSteps": "gatling/steadyLoad.csv"
        },
    ],
    "chaosConfig": "chaos/none.json",
    "misarchConfig": "misarch/none.json",
    "globalConfig": "gloabl/none.json"
  }
]
```

Most of the configuration is done in the individual config files for each part of the experiment. The documentation normally found in the experiment dashboard can be found in the file `MISARCH-DOCS.md`. Note that the traffic is entirely defined by the userSteps CSV-files. Therefore, the normal settings for this (duration, rate, loadType) are omitted.

For now the global experiment configuration is not implemented since it is only used to generate thresholds for the Grafana dashboard.
