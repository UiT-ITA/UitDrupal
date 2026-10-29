# flux-template.sh

A small utility batch script that makes it easier to template kustomize
kustomizations locally. This does not guarantee that they work fine in the
cluster, but might help figure out potential invalid configurations before
pushing.

You can template everything for an environment, or limit it to specific manifest
kinds or manifest names.

## Usage

> `Usage: ./template-flux.sh <environment> <service> [index] [type] [value]`

Examples:

- `./template-flux.sh bgo1-test skeivtarkiv` - Renders the entire kustomize tree
  for skeivtarkiv in bgo1-test
- `./template-flux.sh bgo1-test skeivtarkiv 2` - If there are multiple
  kustomizations in a single file, you can choose which index to render. E.g
  post-deploy job.
- `./template-flux.sh bgo1-test skeivtarkiv 1 kind Ingress` - Only renders
  manifests of Ingress kind
- `./template-flux.sh bgo1-test skeivtarkiv 1 name skeivtarkiv-drupal` - Only
  renders manifests with metadata.name skeivtarkiv-drupal

## Substitutions

If you want to template the substitutions, you can pipe it through `flux
envsubst --strict`, but it requires that you have the substitutions set in the
environment. (--strict makes it complain if it is missing)

e.g

```sh
export rail_region=bgo1
export rail_env=test
./template-flux.sh bgo1-test skeivtarkiv kind Ingress | flux envsubst --strict
```

Output:

```yaml
Environment: bgo1-test
Service: skeivtarkiv
Kustomization file: ./bgo1-test/RAIL/skeivtarkiv.yaml
Kustomization name: adm-it-pub-skeivtarkiv
Kustomization path: bgo1-test/skeivtarkiv
Filter: kind = Ingress

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: harica
    cert-manager.io/private-key-algorithm: ECDSA
    cert-manager.io/private-key-rotation-policy: Always
    cert-manager.io/usages: digital signature
    nginx.ingress.kubernetes.io/whitelist-source-range: 129.177.0.0/16,2001:700:200::/48
  labels:
    kustomize.toolkit.fluxcd.io/name: adm-it-pub-skeivtarkiv
    kustomize.toolkit.fluxcd.io/namespace: ""
  name: skeivtarkiv-nginx
  namespace: adm-it-pub-skeivtarkiv
spec:
  ingressClassName: nginx
  rules:
    - host: skeivtarkiv.bgo1.test.rail.uib.no
      http:
        paths:
          - backend:
              service:
                name: skeivtarkiv-nginx
                port:
                  number: 80
            path: /
            pathType: Prefix
  tls:
    - hosts:
        - skeivtarkiv.bgo1.test.rail.uib.no
      secretName: skeivtarkiv.bgo1.test.rail.uib.no-tls
```
