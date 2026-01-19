# Postgres database component

This is a simple plug-and-play postgres database component that uses the cloudnative pg operator supplied by RAIL.

## Requirements

It requires the following secret to exist in the namespace.

Manifest should look like this, NB Remember SOPS encryption

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ${app_name}-db-secret
type: Opaque
stringData:
  username: ${app_name}
  password: [ADD PASSWORD]
```

## Consideration

The base database size is just 16GB and contains only 2 instances. The default setup assumes a test environment and you must make sure that it is suitable for your deployed environments.

TODO: Backups - no setup for this, barman cloud plugin -> S3?