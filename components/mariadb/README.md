# MariaDB database component

This is a simple mariaDB database run as a statefulset and stored to a pvc.

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
  database: [ADD DATABASE NAME]
  username: [ADD USERNAME]
  password: [ADD PASSWORD]
  root-password: [ADD PASSWORD]
```

## Considerations

This is a very ad-hoc hosted database type and does not have any external setup.
This means that there are no built in backup solution like in the postgres
database. You should optimally choose Postgres where possible.

Due to the database running on a regular persistence volume, is it not possible
to run multiple replicas of the database as persistence volumes are read once by
default. It might be possible to have read-replicas, but it is not set up by
default.

## Backup

> TODO: Document if this becomes a more standardized component. Backup must be
> done manually currently with a dump and restore.