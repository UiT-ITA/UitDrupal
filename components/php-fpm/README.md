# Php-fpm service

Configuration for a php-fpm service. It is automatically set up to collect
metrics from `/status` if it is exposed.

## Requirements

You are required to build an image containing the php files. You are also
required to set up and configure a reverse proxy like nginx to talk with the
php-fpm service. This setup is just to create the deployment for the php-fpm
service.

We recommend you use [this
image](https://git.app.uib.no/itpublic/dockerimages/php-fpm-base-unprivileged)
as a base to build your own.

> TODO: Default php-fpm configuration?

### Required post-build variables

```yaml
app_name: {{YOUR_APP_NAME}} # E.g profile
image_pull_secret_name: {{IMAGE_PULL_SECRET_NAME}} # Probably gitapp-adm-it-pub-systembruker
```

### Required image override

```yaml
# Image below is just a plain unprivileged nginx image
images:
  - name: PATCH_PHP_FPM_IMAGE
    newName: {{YOUR_IMAGE_REF}}
    newTag: {{YOUR_TAG}}
```
