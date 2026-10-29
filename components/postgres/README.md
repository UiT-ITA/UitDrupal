# Postgres database component

This is a simple plug-and-play postgres database component that uses the
cloudnative pg operator supplied by RAIL.

## Requirements

It requires the following secret to exist in the namespace.

Manifest should look like this:

NB: Remember SOPS encryption

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ${app_name}-db-secret
type: Opaque
stringData:
  username: [ADD USERNAME] # NB: Make it the same as ${app_name}, otherwise you must also patch the owner field of the cluster
  password: [ADD PASSWORD]
```

## Consideration

1. The base database size is just 16GB and contains only 1 instance. The default
   setup assumes a test environment and you must make sure that it is suitable
   for your deployed environments.

## Backups in S3

It is recommended to set up backups in production environments. This component
takes no responsibility for backups so you are required to set that up manually.
[See RAIL documentation for more
information](https://rail.uib.no/docs/database.html#backup)