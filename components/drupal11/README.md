# Drupal 11 component

This component contains the setup for a basic Drupal 11 application.

This component combines the `nginx` and `php-fpm` components in order to set up
nginx to proxy calls to php-fpm automatically through fastcgi.Files are served
through the nginx instance.

## Requirements

### Required post-build variables

These are required to be set in the fluxCD Kustomization. Should be in
`/{cluster}/RAIL/{app_name}.yaml`.

```yaml
app_name: {{YOUR_APP_NAME}} # E.g profile
image_pull_secret_name: {{IMAGE_PULL_SECRET_NAME}} # Probably gitapp-adm-it-pub-systembruker
rail_env: {{CLUSTER_ENV}} # E.g prod
rail_region: {{CLUSTER_REGION}} # E.g bgo1
```

### Required image overrides

These must be set in the appropriate kustomization yaml, usually
`/{cluster}/{app_name}/kustomize.yaml`.

```yaml
images:
  - name: PATCH_NGINX_IMAGE
    newName: git.app.uib.no:4567/itpublic/dockerimages/nginx-alpine-unprivileged
    newTag: 1.29
  - name: PATCH_PHP_FPM_IMAGE
    newName: {{YOUR_IMAGE_REF}}
    newTag: {{YOUR_TAG}}
```

### Post deploy

In order to run drush deploy properly, we require you have two fluxcd
kustomizations, one that depends on the other. This way we will never run drush
deploy before the new application is fully up and running and should avoid
database corruption due to two versions of the application competing for
ownership.

In your post deploy kustomization, refer to the `post-deploy` directory in the
`drupal11` component.

So when defining your application in the `RAIL` directory, create one for the
main and then one for post deploy.

#### Below is an example from profile:

```yaml
apiVersion: hnc.x-k8s.io/v1alpha2
kind: SubnamespaceAnchor
metadata:
  name: adm-it-pub-profile
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: adm-it-pub-profile
spec:
  sourceRef:
    kind: GitRepository
    name: adm-it-pub
  path: ${rail_cluster}/profile
  targetNamespace: adm-it-pub-profile
  prune: true
  wait: true
  ...
---
# post deploy
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: adm-it-pub-profile-post-deploy
spec:
  dependsOn: # This makes fluxCD wait for the application deploy to finish
    - name: adm-it-pub-profile
  sourceRef:
    kind: GitRepository
    name: adm-it-pub
  path: ${rail_cluster}/profile/post-deploy
  targetNamespace: adm-it-pub-profile
  prune: true
  wait: true
  force: true # NB: We want to force redeploy this as it is an immutable job!
  ...

```

#### post-deploy/kustomization.yaml example from profile base:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../../components/drupal11/post-deploy
  - ../../../../base/git-pull-secrets
patches:
  - path: patches/patch-job-drush-deploy-env.yaml
```

### Database

You must set up and patch credentials for a database. You can in theory use any
database provider, but below is an example for postgres.

1. Set up the postgres component
2. Create three patches:

```yaml
# patch-php-fpm-deployment-env.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${app_name}-php-fpm
spec:
  template:
    metadata:
      labels:
        app: ${app_name}-php-fpm
    spec:
      containers:
        - name: ${app_name}-php-fpm
          env:
          # Database connection
          - name: DRUPAL_DATABASE_HOST
            value: ${app_name}-db-rw
          - name: DRUPAL_DATABASE_PREFIX
            value: ""
          - name: DRUPAL_DATABASE_NAME
            value: ${app_name}
          - name: DRUPAL_DATABASE_USERNAME
            valueFrom:
              secretKeyRef:
                name: ${app_name}-db-secret
                key: username
          - name: DRUPAL_DATABASE_PASSWORD
            valueFrom:
              secretKeyRef:
                name: ${app_name}-db-secret
                key: password
```

```yaml
# patch-php-fpm-drush-cron-env.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ${app_name}-drupal-run-cron
spec:
  jobTemplate:
    spec:
      template:
        metadata:
          labels:
            app: ${app_name}-drupal
        spec:
          containers:
          - name: ${app_name}-drupal
            env:
            # Database connection
            - name: DRUPAL_DATABASE_HOST
              value: ${app_name}-db-rw
            - name: DRUPAL_DATABASE_PREFIX
              value: ""
            - name: DRUPAL_DATABASE_NAME
              value: ${app_name}
            - name: DRUPAL_DATABASE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: ${app_name}-db-secret
                  key: username
            - name: DRUPAL_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${app_name}-db-secret
                  key: password
```


```yaml
# post-deploy/patch-php-fpm-drush-deploy-env.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: ${app_name}-drupal-deploy-job
spec:
  template:
    spec:
      containers:
        - name: ${app_name}-drupal-deploy-job
          env:
            # Database connection
            - name: DRUPAL_DATABASE_HOST
              value: ${app_name}-db-rw
            - name: DRUPAL_DATABASE_PREFIX
              value: ""
            - name: DRUPAL_DATABASE_NAME
              value: ${app_name}
            - name: DRUPAL_DATABASE_USERNAME
              valueFrom:
                secretKeyRef:
                  name: ${app_name}-db-secret
                  key: username
            - name: DRUPAL_DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: ${app_name}-db-secret
                  key: password

```