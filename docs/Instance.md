# Creating an instance

## Overview

When creating a new application instance the following needs to be defined beforehand:

* A suitable **name** for the instance (e.g. `prod` or `dev`); we will use `playground` in the following examples
* The **RAIL cluster** to deploy to: for `prod` choose the cluster `bgo1-prod`, for everything else `bgo1-test`

Armed with this information, creating the instance follows two steps:

1. Create a file in `{cluster_name}/RAIL` defining the namespace and parameters for the instance. The filename should follow the pattern `{app_name}-{app_env}` (e.g. `bgo1-test/RAIL/uit-web-playground.yaml`)
2. Create a directory in `{cluster_name}` for further "kustomizing" the intance. The directory name should follow the same pattern as the above file (e.g. `bgo1-test/uit-web-playground`)

## Defining the instance namespace and parameters

The file defining the namespace needs to hold two resource objects: a `SubnamespaceAnchor` defining the namespace and a
`Kustomization` for connecting the new instance to this git repository.

> Both namespace and Kustomization should follow the naming pattern `uit-it-webadm-{app_name}-{app_env}`, e.g. `uit-it-webadm-uit-web-playground`

The file should look like this, adjust only the marked values:

```yaml
apiVersion: hnc.x-k8s.io/v1alpha2
kind: SubnamespaceAnchor
metadata:
  name: uit-it-webadm-uit-web-playground            # use the name defined above
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: uit-it-webadm-uit-web-playground            # use the name defined above
spec:
  sourceRef:
    kind: GitRepository
    name: uit-it-webadm
  path: bgo1-test/uit-web-playground                # define the path to the directory we will create in the next step
  targetNamespace: uit-it-webadm-uit-web-playground # the name of the SubnamespaceAnchor above
  prune: true
  wait: true
  interval: 30m0s
  retryInterval: 2m0s
  timeout: 10m0s
  decryption:
    provider: sops
    secretRef:
      name: sops-gpg
  postBuild:
    substitute:
      # define the app instance you are deploying
      # (normally only app_env needs to change)
      app_name: uit-web
      app_env: playground

      # define the cluster you are deploying into
      # (should look exactly like this for all non-prod instances)
      rail_cluster: bgo1-test
      rail_env: test
      rail_region: bgo1

      # define the S3 environment available
      # (should be the same across all instances, both prod and all others)
      s3_endpoint: s3.eu-central-003.backblazeb2.com
      s3_region: eu-central-003
      s3_bucket_test: UiT-NREC-webportal-backup-test-00
      s3_bucket_prod: UiT-NREC-webportal-backup-prod-00

      # define how the database is backed up
      # (adjust at least the schedule to prevent all backups from running at the same time)
      # (adjust db_backup_bucket for prod instance)
      db_backup_bucket: UiT-NREC-webportal-backup-test-00
      db_backup_schedule: '0 0 20 * * *'

      # define how the database is initialized
      db_generation: 1                                      # increase whenever you want to re-initialize the database
      db_source_bucket: UiT-NREC-webportal-backup-test-00   # define where to look for the source
      db_source_instance: drupal-db                         # define the name of the instance to use as source
      db_recovery_target: '{}'                              # define empty target for "latest" or timestamp for point-in-time
      # db_recovery_target: '{"targetTime": "2026-11-24 06:02:40.058972+00"  }'



      # define how files are backed up
      # (adjust at least the schedule to prevent all backups from running at the same time)
      files_backup_bucket: UiT-NREC-webportal-backup-test-00
      files_backup_schedule: '7 * * * *'
      files_suspend_backup: "false"

      # define access to the container registry
      # (should not change normally)
      image_pull_secret_name: uitcontainerregistry
```

### Objectstore settings

We use two separate objectstore (S3) buckets at [Backblaze] for backups and file transfers:

* **UiT-NREC-webportal-backup-prod-00** is used to backup `prod`
* **UiT-NREC-webportal-backup-test-00** is used to backup all other instances

Both buckets need to be available to all instances in case we want to initialize with data from any other instance.
So the settings in the `s3_` section should normally not change.

### Backups

#### Database backups

For database backups point `db_backup_bucket` to the prod bucket for `prod` and to test for all other instances.
The database will stream its Write Ahead Log (WAL) to this bucket, enabling point-in-time recovery by replaying the
log up to a certain timestamp.

Additionally, a base backup (constistend copy of all database files) needs to run periodically to have a base to
apply the WAL to in case of recovery. Normally running a base backup once a day should be enough. Just take care
to adjust the exact value, so that all backups do not start at the same time and cause unnecessary load spikes.

> Note that the `db_backup_schedule` follows normal crontab syntax, but has an extra seconds field in the front!

See also the [RAIL documentation](https://docs.rail.uib.no/docs/database.html#schedule-base-backups) on
database backups.

#### Filesystem backups

Contrary to database backups, there is no constant streaming of filesystem changes. 
Instead, we do a full sync every 15 minutes for `prod` and hourly for all other instances.

For these parameter the same applies as for the database:

* Point `files_backup_bucket` to the prod bucket for `prod` and the test bucket for all other instances.
* Adjust `files_backup_schedule` so not all backups run at the same time.

If you want to stop / pause filesystem backups for an instance completely set `files_suspend_backup` to "true".
You can always resume backups by setting it back to "false".

### Initialize an instance from an existing database

To initialize an instance with data from another follow these steps:

* Increase `db_generation` (or set it to 1 for a new instance): this will destroy the all database and start the initialization process.
* Use `db_source_bucket` and `db_source_instance` to define which instance to use as the source
* Set the `db_recovery_target` to `'{}'` (an empty json object in a string) to recover to the newest possible state. See [Recovery](Recovery.md) for more options.

## Further Kustomizing the instance

The directory created in step 2 above (e.g. `bgo1-test/uit-web-playground`) can be used to patch all Kubernetes
resources created by `base/uit-web`. See the official [Kustomize reference](https://kubectl.docs.kubernetes.io/references/kustomize/)
for details.

Normally you only need to create to instance-specific files and else add a pointer to `base`.

### Minimum configuration

Create the following files:

#### settings.php

Create a plain instance specific settings file for your installation. The file will be automatically converted into a Kubernetes resource on deployment.

Make sure to add the following line for including the salt below:

```php
$settings['hash_salt'] = file_get_contents('/var/local/salt.txt');
```

#### drupal-hash-salt.yaml

Create a Secret with a random salt specific to this instance. The secret should look like this:

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: drupal-hash-salt
    labels:
        app.kubernetes.io/part-of: uit-web
type: Opaque
stringData:
    salt.txt: <lots of random characters>
```

Don't forget to encrypt the file with

```
sops encrypt -i bgo1-test/uit-web-playground/drupal-hash-salt.yaml
```

#### kustomize.yaml

Finally, add a `kustomize` file to point at the base directory. If you do not need any further
refinements, the file should look like this:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base/uitcontainerregistry-pull-secret
  - ../../base/uit-web
  - drupal-hash-salt.yaml
configMapGenerator:
  - name: settings-php
    files:
      - settings.php=settings.php
# Deploy artifacts built by www.uit.no (branch master, see .github/deploy-targets.yml).
# Set both tags to the tag from the workflow summary to deploy a new build.
images:
  - name: uitcontainerregistry.azurecr.io/uit/www-uit-no
    newTag: uit-web-dev-2026-11-23T13-33-31Z # {"$imagepolicy": "uit-it-webadm-uit-web-dev:drupal:tag"}
  - name: uitcontainerregistry.azurecr.io/uit/www-uit-no-nginx
    newTag: uit-web-dev-2026-11-23T13-33-31Z # {"$imagepolicy": "uit-it-webadm-uit-web-dev:nginx:tag"}
  - name: uitcontainerregistry.azurecr.io/uit/rsyslog-drupal
    newTag: 8.26-0004 # {"$imagepolicy": "uit-it-webadm-uit-web-dev:rsyslog:tag"}
  - name: uitcontainerregistry.azurecr.io/uit/aws-cli
    newTag: 2.42-0004 # {"$imagepolicy": "uit-it-webadm-uit-web-dev:aws-cli:tag"}
```
