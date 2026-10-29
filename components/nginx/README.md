# Nginx service

A nginx reverse proxy with a pre-defined ingress, deployment, service and
network-policy.

Sets up an ingress with a ssl certificate for you automatically that you can
reach on `${app_name}.${rail_region}.${rail_env}.rail.uib.no`. E.g
`profile.bgo1.prod.rail.uib.no`. This is automatically locked down to the uib
network through a ip whitelist on
`nginx.ingress.kubernetes.io/whitelist-source-range:
129.177.0.0/16,2001:700:200::/48`. See the section `Adding a custom ingress /
Exposing the ingress outside UiB network` on how to disable the whitelist if you
want it to always be available.

## Requirements

To use this component, refer to it in the `resources` section in the
`kustomization.yaml`.

### Required post-build variables

These are required to be set in the fluxCD Kustomization. Should be in
`/{cluster}/RAIL/{app_name}.yaml`.

```yaml
app_name: {{YOUR_APP_NAME}} # E.g profile
image_pull_secret_name: {{IMAGE_PULL_SECRET_NAME}} # Probably gitapp-adm-it-pub-systembruker
rail_env: {{CLUSTER_ENV}} # E.g prod
rail_region: {{CLUSTER_REGION}} # E.g bgo1
```

### Required image override

These must be set in the appropriate kustomization yaml, usually
`/{cluster}/{app_name}/kustomize.yaml`.

```yaml
# Image below is just a plain unprivileged nginx image
images:
  - name: PATCH_NGINX_IMAGE
    newName: git.app.uib.no:4567/itpublic/dockerimages/nginx-alpine-unprivileged
    newTag: 1.29
```

### Required configmap

In order to reach your actual service, you need to set up the nginx.conf that
points to your application. Se below for a minimal example to get you started.

> TODO: Make it possible to run without configmap? E.g if nginx.conf is built
> into image.

```nginx
# ./nginx.conf
server {
  listen 8080;
  server_name localhost;
  root /var/www/html/web;

  index index.html;

  # Add the rest of your nginx config here
}
```

Then append the configmap to the kustomization.yaml

```yaml
configMapGenerator:
  - name: nginx-config
    files:
      - default.conf=nginx.conf
```

## Adding a custom ingress / Exposing the ingress outside UiB network

Production applications often have their own ingress that you reach them on. You
could set up a separate ingress, but if you want them to be managed by the same
ingress. Below is an example from profile:

```yaml
# Ingress patch
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${app_name}-nginx
  annotations:
    # Setting this to be empty exposes it to the outside world!
    nginx.ingress.kubernetes.io/whitelist-source-range:
spec:
  rules:
  - host: ${app_name}.${rail_region}.${rail_env}.rail.uib.no
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${app_name}-nginx
            port:
              number: 80
    # Add a new host rule for the ingress
  - host: profile.uib.no
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${app_name}-nginx
            port:
              number: 80
  tls:
  - hosts:
    - ${app_name}.${rail_region}.${rail_env}.rail.uib.no
    # Add ingress as a host
    - profile.uib.no
    secretName: ${app_name}.${rail_region}.${rail_env}.rail.uib.no-tls
```

Then add it to the kustomization like this:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
...
patches:
  - path: patches/ingress.yaml
```