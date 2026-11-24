# Overview of the UitDrupal repository

The repository has the following file structure:

```
├── base
│   ├── uitcontainerregistry-pull-secret
│   ├── uit-storybook
│   ├── uit-web
│   │   ├── cron-hourly
│   │   └── scripts
│   └── uit-web-cronjob
├── bgo1-prod
│   ├── RAIL
│   └── uit-web-prod
├── bgo1-test
│   ├── RAIL
│   ├── uit-storybook-dev
│   ├── uit-web-dev
├── docs
│   └── dashboards
│       └── grafana
├── osl1-prod
│   └── RAIL
├── osl1-test
│   └── RAIL
└── tools

```

## base

The base directory holds the main application definitions. The manifests in these directories
define the Kubernetes resources that will be deployed to the cluster.

They need to be refrenced from a cluster specific configuration to actually take effect.

* `base/uitcontainerregistry-pull-secret` defines the secret needed to pull images from the Azure container registry. It is needed in all namespaces
* `base/uit-storybook` is the storybook application
* `base/uit-web` defines UiT's drupal web solution. This is the main application
* `base/uit-web-cronjob` defines a template for cronjobs used in `base/uit-web`. It is in a separate directory to allow reuse for different jobs. See the [Cronjob](Cronjobs.md) documentation for details.

## docs

The docs directory holds documentation, such as the file you're currently reading.

* `docs/grafana` holds the source of custom grafana dashboards defined for monitoring. These files need to be uploaded manually to Grafana.

## tools

As the name implies, tools for easing development. The `validate.sh` script is borrowed from [Flux](https://fluxcd.io/flux/)
and is used by the top directory `Makefile` to validate the manifests currently in the repo.

## Cluster directories (bgo1-prod, bgo1-test, osl1-prod, osl1-test)

These directories define which application instances are deployed to which cluster. See [Instance](Instance.md) for details.

The `{cluster_name}/RAIL` directory defines the instances (namespaces) avaiable in the cluster. Additionally each instance has a
corresponding directory in the "cluster root" that defines what exactly is deployed to that namespace.
