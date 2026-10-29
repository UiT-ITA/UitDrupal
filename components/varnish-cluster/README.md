# Varnish Self-Routing Sharded Cluster

This component is based on the opensource
[Varnish helm chart](https://github.com/varnish/helm-varnish/blob/main/varnish-cache/README.md)
and
[this post in the Varnish-software blog](https://info.varnish-software.com/blog/creating-self-routing-varnish-cluster).

In short, in the the default configuration provided, it will craate a 3-node
highly available, self-routing sharded Varnish Cache cluster.

## Requirements

- a `Secret` with name `${app_name}-varnish-ban-token` in your namespace with a
  key `varnish_ban_token`. It is injected into Varnish as `VARNISH_BAN_TOKEN`
  (optional; without it only the purge ACL authorizes cache invalidation).
- a `ConfigMap` with name varnish-config to be created in your namespace. Check
  [https://git.app.uib.no/itpublic/dockerimages/varnish-unprivileged/-/tree/main/6.0/conf](https://git.app.uib.no/itpublic/dockerimages/varnish-unprivileged/-/tree/main/6.0/conf)
  for example configurations. This config should point Varnish to the backend
  you want it to accelerate, i.e nginx. It should authorize PURGE, BAN and
  URIBAN like `example-drupal-varnish-cluster.vcl`: allow the purge ACL only for
  unproxied requests (Varnish appends `client.ip` to `X-Forwarded-For`, so any
  other value means the request passed the ingress, whose pods are inside
  10.0.0.0/8), or any request with a valid `X-Ban-Token`:
  ```
  if (req.method == "PURGE" || req.method == "BAN" || req.method == "URIBAN") {
      if (!((client.ip ~ purge && req.http.X-Forwarded-For == "" + client.ip) ||
            (std.getenv("VARNISH_BAN_TOKEN") != "" &&
             req.http.X-Ban-Token == std.getenv("VARNISH_BAN_TOKEN")))) {
          return (synth(405, "Not allowed."));
      }
  }
  ```
- a `VARNISH_BAN_TOKEN` env variable added to containers that will try to send
  BAN requests.
- an ingress that point ingress-traffic to the Varnish service.
- an images field in your kustomization, either in your base or overlay, to
  specify the image to use and an image update automation policy:
    ```yaml
    images:
    - name: PATCH_VARNISH_IMAGE
        newName: git.app.uib.no:4567/itpublic/dockerimages/varnish-unprivileged
        newTag: 6.0.16 # {"$imagepolicy": "adm-it-pub:varnish-6.0-image-policy:tag"}
    ```

## Flux Postbuild Substitution Variables

The following variables can be set via [Flux postbuild substitution](https://fluxcd.io/flux/components/kustomize/kustomizations/#post-build-variable-substitution)
in your overlay's Kustomization. All have sensible defaults and are optional.

> **TL;DR — sizing `VARNISH_MEMORY`:** Only allocate **75% of the memory available to the pod** for malloc storage.
> The remaining 25% covers Varnish overhead (~5%) and worst-case jemalloc fragmentation (~20%).
> Example: a pod with 1GB memory limit → set `VARNISH_MEMORY` to `768m`.
> With careful jemalloc tuning the ceiling can be raised to ~90%, but 75% is safe without any extra tuning.
> See [Understanding Varnish Cache Memory Usage](https://info.varnish-software.com/blog/understanding-varnish-cache-memory-usage) for the full breakdown.

### Sizing summary for this component

Assumptions used in the calculations below:

- `server.maxThreads=1000`
- `thread_pools=2` (Varnish default)
- `thread_pool_stack=80k` (Varnish default)
- max thread stack budget: about `156Mi`

If `VARNISH_SERVER_MEMORY_LIMIT=768Mi`:

| Profile | Safety buffer beyond thread stacks | Recommended `VARNISH_MEMORY` |
|---|---:|---:|
| 1x steady | 64Mi | 574m |
| 2x burst | 128Mi | 507m |
| Heavy burst / safer default | 192Mi | 440m |

If `VARNISH_MEMORY=512m` is kept, the minimum `VARNISH_SERVER_MEMORY_LIMIT` should be:

| Profile | Minimum limit |
|---|---:|
| 1x steady | 709Mi |
| 2x burst | 773Mi |
| Heavy burst / safer default | 837Mi |

Practical note: the current default pair (`VARNISH_MEMORY=512m`, `VARNISH_SERVER_MEMORY_LIMIT=768Mi`) is close to the 2x burst profile but slightly below it.

| Variable | Default | Description |
|---|---|---|
| `VARNISH_SIZE` | `512m` | Varnish cache memory allocation (passed to `-s malloc`). Should be ~75% of the pod's memory limit. |
| `VARNISH_SERVER_CPU_LIMIT` | `1000m` | CPU limit for the Varnish server container |
| `VARNISH_SERVER_MEMORY_LIMIT` | `768Mi` | Memory limit for the Varnish server container |
| `VARNISH_SERVER_CPU_REQUEST` | `500m` | CPU request for the Varnish server container |
| `VARNISH_SERVER_MEMORY_REQUEST` | `640Mi` | Memory request for the Varnish server container |
| `VARNISH_NCSA_CPU_LIMIT` | `200m` | CPU limit for the varnishncsa sidecar container |
| `VARNISH_NCSA_MEMORY_LIMIT` | `128Mi` | Memory limit for the varnishncsa sidecar container |
| `VARNISH_NCSA_CPU_REQUEST` | `100m` | CPU request for the varnishncsa sidecar container |
| `VARNISH_NCSA_MEMORY_REQUEST` | `128Mi` | Memory request for the varnishncsa sidecar container |
| `VARNISH_EXPORTER_CPU_LIMIT` | `150m` | CPU limit for the prometheus-varnish-exporter sidecar |
| `VARNISH_EXPORTER_MEMORY_LIMIT` | `64Mi` | Memory limit for the prometheus-varnish-exporter sidecar |
| `VARNISH_EXPORTER_CPU_REQUEST` | `100m` | CPU request for the prometheus-varnish-exporter sidecar |
| `VARNISH_EXPORTER_MEMORY_REQUEST` | `32Mi` | Memory request for the prometheus-varnish-exporter sidecar |

Example overlay Kustomization:
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
postBuild:
  substitute:
    VARNISH_SIZE: "1g"
    VARNISH_SERVER_CPU_LIMIT: "2000m"
    VARNISH_SERVER_MEMORY_LIMIT: "1280Mi"
    VARNISH_SERVER_MEMORY_REQUEST: "1024Mi"
```

**Note:** After changing any of the aborve values, allow some time for the
HelmRelease resource to be reconciled and the varnish-cache statefulset to be
restarted. (Should be < 10 minutes)