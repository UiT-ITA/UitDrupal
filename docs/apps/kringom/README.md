# Kringom

## Overview

Kringom is a colabboration between Vestland Fylkeskommune and UiB.

## Architecture

Application base: `/base/uib-drupal-site`

Components:

| Component      | Description                                 |
| -------------- | ------------------------------------------- |
| Postgres 17    | PostgreSQL 17 cluster                       |
| Drupal11       | Uses `php-fpm` and `nginx` components       |
| Solr-cloud     | Single replica setup of Solr with Zookeeper |
| Varnish        | HTTP caching reverse proxy (Varnish)        |
| Valkey         | Cache store; test only (bgo1-test)          |

## Environments

- Service level: C
  ([https://ntk.app.uib.no/TJ0139/](https://ntk.app.uib.no/TJ0139/))

| Environment | Cluster   | base       | URL                           | Purpose             | Deployment method      |
| ----------- | --------- | ---------- | ----------------------------- | ------------------- | ---------------------- |
| Production  | bgo1-prod | production | <https://kringom.no>          | Live traffic        | On git tag             |
| Test        | bgo1-test | test       | <https://kringom.test.uib.no> | Pre-release testing | push to master branch  |


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
| osl1-prod | <https://opensearch.osl1.prod.rail.uhdc.no> | Search application logs in production |
| osl1-test | <https://opensearch.osl1.test.rail.uhdc.no> | Search application logs in test       |

## Database + Files

Database is backed up to S3 using the Barman cloud plugin for postgres with a
retention of 30 days. It creates a full backup every night at 1 am, and the
barman cloud plugin continuously uploads WAL data to allow for point in time
restore. 

File changes are continuously streamed to bgo1 S3 every 15 minutes.

The S3 bucket is copied to an on-premise volume for an extra set of backups.

### Restoring in case of disaster

Database restore: See information about restore here:
<https://rail.uib.no/docs/database.html#how-to-restore-a-cluster>.

TODO: / NB: Restore of database is currently un-tested and should be formalized

TODO: / NB: There are currently no ways to automatically restore files from a
dump to production.

## Setting up a new environment

A step by step list on how to create a new environment.

### Creating a basic Kringom test environment in RAIL

> Note: We want to formalize this process to create a template, but for now, this is
how to copy-paste:

1. Decide on cluster for the environment to live in. e.g bgo1-test
1. Create a new folder for your kringom instance, e.g bgo1-test/kringom-sandbox.
1. Copy manifests from another similar environment, e.g bgo1-test/kringom.
1. Inside patches/ingress.yaml, make sure to set up your required ingresses
1. Make sure to update all the secrets with sane values. Make sure to make new
   unique passwords and encrypt them with sops!
1. Update the images in kustomization.yaml and post-deploy kustomization.yaml,
   either remove the imageupdate automation and specify specific images or
   create custom image update automations.

### Setting up image update automation (Optional)

NB: Make sure you are generating tagged images for nginx and php-fpm in a format
that you can filter with regex.

1. In `bgo1-prod/RAIL/update-automations/kringom`, copy an existing image-policy for
   nginx and php-fpm and name them according to your environment.
1. Update the filterTags pattern to reflect your deployment policy.
1. Update the images section in kustomization.yaml and post-deploy
   kustomization.yaml to reference the image-policy name you created in step 2.
   (See how it is set up in e.g kringom)
   1. NB: Make sure that name has a suffix of :name and tag has a suffix of
      :tag.

### Setting up feide redirect (Optional)

> You can use `drush -l {ROOT_URL} uli` to generate a password reset for the
main admin user and bypass feide. However if other users should login, you must
set up the feide redirect.

New environments for Kringom requires a valid return url to be set up in Feide. An
administrator in Feide applications is required to set this up.

The url that should be should be `{ROOT_URL}/openid-connect/feide`

E.g `kringom-sandbox.bgo1.test.rail.uib.no/openid-connect/feide`.

### Restoring a database in test (Optional - test / sandbox overlay)

The test instance comes with an already existing db-restore cron job
that will automatically restore the database at night. You can manually trigger
this early if needed through e.g k9s.

NB: Production environments does not have any automatic way to do a database
restore and requires manual setup if necessary.

### Setting up a new production environment database from a backup/dump.

TODO: Describe step by step process.
