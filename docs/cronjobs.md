# Running cronjobs in uit-web

## High frequency cronjobs

High frequency (everything under 1 hour) cronjobs should be run from within a
deciated cron pod.

[base/uit-web/drupal-cron-deployment.yaml](../base/uit-web/drupal-cron-deployment.yaml)
creates a deployment that utilizes [supercronic](https://github.com/aptible/supercronic)
to run cron as the www-data user.

It uses a single crontab file that can be found in [base/uit-web/drupal-crontab.yaml](../base/uit-web/drupal-crontab.yaml)
Add any high frequency jobs to this file.

## Medium- and low frequency cronjobs

Cronjobs that run hourly or less frequent can be configured as Kubernetes CronJobs.
Kubernetes will create a job for each occurence, which in turn will create a pod
and execute the specified command.

### Template cronjob

A template for all cronjobs can be found at [base/uit-web-cronjob/drupal-cronjob.yaml](../base/uit-web-cronjob/drupal-cronjob.yaml).

> ***Changing anything in this file will change it for all cronjobs in uit-web!***

### Adding an additional cronjob

Adding a cronjob needs these steps:

1. create a new directory at `base/uit-web/cron-XXX` with an appropriate `kustomization.yaml`
2. add the new directory to [base/uit-web/kustomization.yaml](../base/uit-web/kustomization.yaml)

The `kustomization.yaml` needs to include the template cronjob and patch at least the following:

- add a `nameSuffix` to ensure a unique name for the new cronjob
- replace the `schedule` field with an appropriate value
- replace the `command` table with the desired command

E.g. to add a daily cronjob, you could add a new directory `base/uit-web/cron-daily` with
the following `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../uit-web-cronjob
nameSuffix: -daily
patches:
- target:
    group: batch
    version: v1
    kind: CronJob
    name: drupal-cronjob
  patch: |-
    - op: replace
      path: /spec/schedule
      value: "1 0 * * *"

    - op: replace
      path: /spec/jobTemplate/spec/template/spec/containers/0/command
      value:
      - /usr/bin/daily.sh
      - cron
```

This would run the command `/usr/bin/daily.sh` with the parameter `cron`
each day at 1 minute past midnight.

> ***Do not forget to add the new job to the main directory!***

like this:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
labels:
  ...
resources:
  ...
  - ./cron-hourly
  - ./cron-daily
```
