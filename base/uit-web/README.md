# UiT-Web

This directory holds all the files needed to deploy an instance of UiT-Web.

## Requirements

### Flux substitution variables

The following variables need to be defined in the `postBuild.substitute` block
of the Flux `Kustomization` defined per instance

- `app_name`: Name of the application, should be set to `uit-web`
- `app_env`: Name of the instance environment (e.g. `test`, `stage`, `prod`)
- `rail_cluster`: Name of the cluster, normall `[rail_region]-[rail_env]`
- `rail_env`: Destination environment for the instance, either `test` or `prod`
- `rail_region`: Destination region for the instance, either `bgo1` or `osl1`
- `ip_whitelist`: Optional CIDR list of ip addresses allowed to access the instance. If not set, defaults public.
- `image_pull_secret_name`: Secret for pulling container images, should be set to `uitcontainerregistry`

### Resources

The following additional resources need to be defined per environment in the
directory referencing this installation:

- Secret `db-drupal-user`: database user and password
- Secret `drupal-hash-salt`: Random value used for `$settings['hash_salt']` in Drupal
- ConfigMap `settings.php`: Instance specific Drupal settings

#### Secret `db-drupal-user`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-drupal-user
  labels:
    app.kubernetes.io/part-of: uit-web
type: Opaque
stringData:
  username: drupal
  password: [ADD PASSWORD]
```

#### Secret `drupal-hash-salt`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: drupal-hash-salt
  labels:
    app.kubernetes.io/part-of: uit-web
type: Opaque
stringData:
  salt.txt: |-
  [UNIQUE RANDOM STRING]
```

#### ConfigMap `settings.php`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: settings.php
  labels:
    app.kubernetes.io/part-of: uit-web
data:
  settings.php: |
    <? php

    // phpcs:ignoreFile

    /**
     * @file
     * Drupal site-specific configuration file.
    [...]
```

## Deployed Components

### Database

Adhering to Drupal conventions, a single database called `drupal` is deployed, along
with a single user also named `drupal`. The password for this user needs to be set per
instance in the `db-drupal-user` Secret.

The number of database replicas is also instance specific. If not set it defaults to
two, but should be patched to three for production instances.

### Persistent website files

PVC `uit-web-files` for files uploaded to Drupal.

### Nginx

Frontend nginx webserver deployment, service and ingress.

### Drupal

Drupal application deployment and service.

### Rsyslog

Rsyslog deployment and service for logging.

## Open Question

- is it actually useful to manage `settings.php` from here?
