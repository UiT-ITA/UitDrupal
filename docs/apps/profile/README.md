# Profile

## Overview

Profile handles user information in UiB's systems. It contains information about
employees and distributes information to systems that require this information,
like the external web where an employee profile can be shown.

## Architecture

Application base: `/base/profile`

Components:

- Postgres 7 cluster
- Drupal11 - Which uses `php-fpm` and `nginx` components

Base structure:
```
profile
├─ base       - Common base for all overlays, this should be part of all environments
├─ production - Inherits from base, production environment specific configuration
├─ test       - Inherits from base, test environment specific configuration
└─ sandbox    - Inherits from test, sandbox environment specific configuration
```

## Environments

- Service level: B (https://ntk.app.uib.no/TJ0951/)

| Environment | Cluster   | base       | URL                                                | Purpose                         | Deployment method      |
| ----------- | --------- | ---------- | -------------------------------------------------- | ------------------------------- | ---------------------- |
| Production  | bgo1-prod | production | <https://profile.uib.no>                           | Live traffic                    | On git tag             |
| Test        | bgo1-test | test       | <https://profile.test.uib.no>                      | Pre-release testing             | push to master branch  |
| Sandbox     | bgo1-test | sandbox    | <https://profile-sandbox.test.uib.no>              | Debugging / environment testing | push to sandbox branch |
| Sandbox-s3  | bgo1-test | sandbox    | <https://profile-sandbox-s3.bgo1.test.rail.uib.no> | Testing s3 with profile         |                        |

### Monitoring

#### Grafana dashboards

NB: To watch metrics for adm-it-pub, you need to select "Publisering" in the
dropdown in the top left corner.

| Cluster   | dashboard | URL                                                                                     |
| --------- | --------- | --------------------------------------------------------------------------------------- |
| bgo1-prod | php-fpm   | <https://grafana.bgo1.prod.rail.uhdc.no/d/bexjae90uton4b/php-fpm-dashboard?orgId=3>     |
| bgo1-prod | postgres  | <https://grafana.bgo1.prod.rail.uhdc.no/d/cloudnative-pg/postgres-db-dashboard?orgId=3> |
| bgo1-test | php-fpm   | <https://grafana.bgo1.test.rail.uhdc.no/d/bexjae90uton4b/php-fpm-dashboard?orgId=1>     |
| bgo1-test | postgres  | <https://grafana.bgo1.test.rail.uhdc.no/d/cloudnative-pg/postgres-db-dashboard?orgId=1> |

#### OpenSearch dashboards

TODO: Links directly search / dashboards

| Cluster   | URL                                         | Purpose                               |
| --------- | ------------------------------------------- | ------------------------------------- |
| bgo1-prod | <https://opensearch.bgo1.prod.rail.uhdc.no> | Search application logs in production |
| bgo1-test | <https://opensearch.bgo1.test.rail.uhdc.no> | Search application logs in test       |

## Data storage & backup

See [backup.md](./backup.md) for where data lives (Postgres, files PVC, S3 paths, cross-region sync, retention).

Disaster recovery: [disaster.md](./disaster.md).

## Setting up a new environment

A step by step list on how to create a new environment.

### Creating the environment in RAIL

NB: We have made an assumption that read credentials can be shared within the
environment overlays, this means multiple test environments might use the same
feide / scim / orgreg / etc credentials. If this is not possible in your case,
you might need to create a new base.

1. Decide on cluster for the environment to live in. e.g bgo1-test
2. Create a new folder for your profile instance, e.g bgo1-test/sandbox-2
3. Copy manifests from another similar environment, e.g bgo1-test/sandbox
4. Inside patches/ingress.yaml, make sure to set up your required ingresses
5. Make sure to update the database secret to a new one. (Username should
   usually be the same as the application_name)
6. Make sure to update the rabbitmq secret. It should usually push to a separate
   queue setup in brom.
7. Update the images in kustomization.yaml and post-deploy kustomization.yaml,
   either remove the imageupdate automation and specify specific images or
   create custom image update automations.

### Setting up image update automation (Optional)

NB: Make sure you are generating tagged images for nginx and php-fpm in a format
that you can filter with regex.

1. In `bgo1-prod/RAIL/update-automations/profile`, copy an existing image-policy
   for nginx and php-fpm and name them according to your environment.
2. Update the filterTags pattern to reflect your deployment policy.
3. Update the images section in kustomization.yaml and post-deploy
   kustomization.yaml to reference the image-policy name you created in step 2.
   (See how it is set up in e.g sandbox)
   1. NB: Make sure that name has a suffix of :name and tag has a suffix of
      :tag.

### Setting up feide redirect (Optional)

NB: You can use `drush -l {ROOT_URL} uli` to generate a password reset for the
main admin user and bypass feide. However if other users should login, you must
set up the feide redirect.

New environments for Profile requires a url to be set up in Feide. An
administrator in Feide applications are required to set this up.

The url that should be should be `{ROOT_URL}/openid-connect/feide`

E.g `profile-sandbox.bgo1.test.rail.uib.no/openid-connect/feide`.

### Restoring a database in test (Optional - test / sandbox overlay)

The test and sandbox overlay comes with an already existing db-restore cron job
that will automatically restore the database at night. You can manually trigger
this early if needed.

NB: Production environments does not have any automatic way to do a database
restore and requires manual setup if necessary.
