# solr-cloud component

This component deploys SolrCloud with ZooKeeper and exposes Solr on hostname `solr`.

## Resources

- `configmap-solr-env.yaml`: Solr options
- `service-solr.yaml`: ClusterIP service for application traffic (`http://solr:8983/solr`)
- `service-solr-headless.yaml`: Headless service used by the Solr StatefulSet
- `statefulset-solr.yaml`: Solr node(s)
- `service-zookeeper.yaml` + `statefulset-zookeeper.yaml`: ZooKeeper
- `servicemonitor-solr-exporter.yaml`: Prometheus metrics for Solr exporter
- `servicemonitor-zookeeper.yaml`: Prometheus scrape target for ZooKeeper

The Solr exporter is configured against `http://127.0.0.1:8983/solr` in this
component.

## Required substitutions

Set these in your Flux `postBuild.substitute` map for each app:

- `app_name`
- `image_pull_secret_name`
- `solr_replicas` (example: `"1"`, `"3"`)
- `solr_auth_secret_name` (secret that contains key `password`)

## Required secret

Provide a namespaced secret referenced by `${solr_auth_secret_name}`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: <your-secret-name>
type: Opaque
stringData:
  password: <solr-zk-shared-password>
```

Username is fixed to `solr`.

## Images

Set image mappings in the consuming overlay:

- `PATCH_SOLR_IMAGE`
- `PATCH_ZOOKEEPER_IMAGE`

Note: the ZooKeeper authentication environment variables in this component
follow the common Bitnami ZooKeeper image conventions.
