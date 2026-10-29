# Valkey component

Single-instance Valkey (Redis-compatible) for use as a cache or session store.
Authentication is required and is provided via a Secret; the component does not
include a Secret.

All resource names are prefixed with the app name, like the other components:
`${app_name}-valkey` (StatefulSet, Service, ConfigMap, NetworkPolicy) and
`${app_name}-valkey-secret` (Secret). Substitute `app_name` the same way you do
for e.g. the mariadb component (e.g. envsubst or your pipeline).

## Secret contract

The overlay (or base) that includes this component **must** create a Secret
named `${app_name}-valkey-secret` (e.g. `myapp-valkey-secret`) with at least:

| Key        | Description                          |
| ---------- | ------------------------------------ |
| `password` | Valkey `requirepass` (auth password) |

Example (SOPS-encrypted in repo, decrypted at apply time):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-valkey-secret   # or ${app_name}-valkey-secret after substitution
type: Opaque
stringData:
  password: "<your-password>"
```

## Usage

1. Add the component to your base or overlay kustomization:

   ```yaml
   resources:
     - ../../../components/valkey   # from e.g. base/myapp/base/
   ```

2. Provide the Secret in the same overlay (e.g. `secret-valkey.yaml` with name
   `myapp-valkey-secret` or SOPS-encrypted equivalent). Ensure `app_name` is
   substituted in the component manifests (same mechanism as for mariadb).

3. Connect from apps in the same namespace to host `${app_name}-valkey` or
   `valkey-0.${app_name}-valkey.<namespace>.svc.cluster.local`, port 6379, with
   the password from the Secret.

## Production (host-level)

On nodes running Valkey, consider:

- **Linux overcommit:** `vm.overcommit_memory = 1` (e.g. in `/etc/sysctl.conf`)
  to avoid background save failures.
- **Transparent huge pages:** Disable if needed for latency: `echo never >
  /sys/kernel/mm/transparent_hugepage/enabled`.
- **Memory:** Set `maxmemory` in the ConfigMap (or patch it) and ensure swap is
  enabled on the node so the kernel does not OOM-kill Valkey under load.
- **Persistence:** RDB/AOF can use up to ~2× memory during saves; size node
  memory accordingly.

See [Valkey Administration](https://valkey.io/topics/admin/).

## Customization

- **Image:** The component uses a placeholder image; override with `images` in
  your base or overlay kustomization and an image update automation policy:
  ```yaml
  images:
    - name: PATCH_VALKEY_IMAGE
      newName: git.app.uib.no:4567/itpublic/dockerimages/valkey-unpriviledged
      newTag: 9.0.0 # {"$imagepolicy": "adm-it-pub:valkey-9.0-image-policy:tag"}
  ```
- **Storage size / class:** Patch the StatefulSet `volumeClaimTemplates` (e.g.
  `storageClassName: rook-ceph-block`, different `storage` request).
- **Config:** The config is generated from `valkey.conf` via configMapGenerator
  (ConfigMap name `valkey`). Edit `valkey.conf` or patch the generated ConfigMap
  (e.g. `maxmemory`, `maxmemory-policy`).
