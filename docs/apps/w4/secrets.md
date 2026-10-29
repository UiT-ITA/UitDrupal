# Secrets

For W4 we have many secrets like database password, api keys etc.
Some of these can be shared across multiple environments (i.e test, sandbox,
kurs) while others are per instance only.

## Secret storage

Currently we implement these secrets in our clusters by committing encrypted
Kubernetes Secret resources to our repository.
See [RAIL documentation on how to protect secrets with SOPS](https://docs.rail.uib.no/docs/gitops.html#protect-secrets-with-sops)

## Secrets rotation

Ideally, all secrets should be rotated at frequent intervals automatically.
However, we don't have mechanism to provide us with such a feature.

To accommodate rotation requirements, all secrets should be rotated on
a biannual basis.

In Gravitee, W4 and Profile share "application".

## W4 secrets to rotatate and their source

W4 consume secrets from multiple sources and this is the list of all 
secrets and where to generate/look up new values:

| Secret name                    | Source | URL | Comment |
| ------------------------------ | ------ | --- | ------- |
| gitapp-adm-it-pub-systembruker | Gitlab |  | TODO: Who has access? |
| w4-cristin-secret              | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=ee5d6419-a852-479d-9d64-19a852f79ddf#s | |
| w4-db-secret                   | This repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |
| w4-dfo-secret                  | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=34bb285a-3783-46b7-bb28-5a378366b7ec#s | |
| w4-disputation-secret          | API |  | Provided by UB |
| w4-feide-secret                | Feide |  | Are has access to Feide |
| w4-fs-api-secret               | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=3d821b60-6a18-4112-821b-606a1811125a#s | |
| w4-fs-fd-api-secret            | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=a4823a2a-b228-43fa-823a-2ab22883fac3#s | |
| w4-fs-graphql-secret           | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=56d73d4a-c701-4edc-973d-4ac7019edc0c#s | |
| w4-fs-ws-api-secret            | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=4285b5d9-4be8-4c4a-85b5-d94be89c4af5#s | |
| w4-greg-secret                 | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=d7213fbe-f739-498c-a13f-bef739c98cc7#s | |
| w4-info-secret                 | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=3963bbd8-98fd-4c2e-a3bb-d898fd7c2e78#s | |
| w4-nva-secret                  | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=c73dce2e-1447-45fe-bdce-2e144795fedc#s | |
| w4-orgreg-secret               | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=108d3bcb-a9a2-4695-8d3b-cba9a2d69528#s | |
| w4-prod-s3-secret              | NREC |  | Keys created using openstack cli - see https://docs.nrec.no/object.html#id6 |
| w4-profile-api-secret          | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=c647778f-aad1-41d2-8777-8faad171d2cc#s | |
| w4-rabbitmq-secret             | BROM | https://brom-uib.intark.uh-it.no/subscription/system-production-person-profile__system-production-uib-w4 | |
| w4-scim-secret                 | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=bbc95674-73ec-461f-8956-7473ec261f73#s | |
| w4-test-s3-secret              | NREC |  | See w4-prod-secret above |
| w4-tp-ws-api-secret            | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=21e60a64-5a72-4ae7-a60a-645a72cae7e3#s | |
| w4-valkey-secret               | This Repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |
| w4-varnish-ban-token           | This Repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |
| w4-varnish-secret              | This Repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |

W4 also has additional secrets controlled by i.e the Postgres operator, ingress controller or
Helm - these will not be touched by us.

**Secrets we should leave as is:**
- sh.helm.release.v1.valkey.v1 (handled by Helm)
- sh.helm.release.v1.valkey.v2 (handled by Helm)
- sh.helm.release.v1.varnish-cache.v1 (handled by Helm)
- sh.helm.release.v1.varnish-cache.v2 (handled by Helm)
- sh.helm.release.v1.varnish-cache.v3 (handled by Helm)
- w4.bgo1.prod.rail.uib.no-tls (Handled by the ingress controller)
- w4-db-ca (Handled by the cloudnative_pg operator)
- w4-db-replication (Handled by the cloudnative_pg operator)
- w4-db-server (Handled by the cloudnative_pg operator)

