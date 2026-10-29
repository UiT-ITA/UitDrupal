# Secrets

For Profile we have many secrets like database password, api keys etc.
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

## Profile secrets to rotatate and their source

Profile consume secrets from multiple sources and this is the list of all secrets and where to generate/look up new values:

| Secret name                    | Source | URL | Comment |
| ------------------------------ | ------ | --- | ------- |
| gitapp-adm-it-pub-systembruker | Gitlab |  | TODO: Who has access? |
| profile-cristin-secret              | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=ee5d6419-a852-479d-9d64-19a852f79ddf#s | |
| profile-db-secret                   | This repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |
| profile-dfo-secret                  | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=34bb285a-3783-46b7-bb28-5a378366b7ec#s | |
| profile-feide-secret                | Feide |  | Are has access to Feide |
| profile-fs-api-secret               | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=3d821b60-6a18-4112-821b-606a1811125a#s | |
| profile-fs-fd-api-secret            | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=a4823a2a-b228-43fa-823a-2ab22883fac3#s | |
| profile-fs-graphql-secret           | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=56d73d4a-c701-4edc-973d-4ac7019edc0c#s | |
| profile-fs-ws-api-secret            | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=4285b5d9-4be8-4c4a-85b5-d94be89c4af5#s | |
| profile-greg-secret                 | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=d7213fbe-f739-498c-a13f-bef739c98cc7#s | |
| profile-info-secret                 | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=3963bbd8-98fd-4c2e-a3bb-d898fd7c2e78#s | |
| profile-nva-secret                  | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=c73dce2e-1447-45fe-bdce-2e144795fedc#s | |
| profile-orgreg-secret               | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=108d3bcb-a9a2-4695-8d3b-cba9a2d69528#s | |
| profile-prod-s3-secret              | NREC |  | Keys created using openstack cli - see https://docs.nrec.no/object.html#id6 |
| profile-profile-api-secret          | Gravitee | | NOTE: Should not be rotated without updating Gravitee |
| profile-rabbitmq-secret             | BROM | https://brom-uib.intark.uh-it.no/subscription/system-production-person-profile__system-production-uib-profile | |
| profile-scim-secret                 | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=bbc95674-73ec-461f-8956-7473ec261f73#s | |
| profile-test-s3-secret              | NREC |  | See profile-prod-secret above |
| profile-tp-ws-api-secret            | Gravitee | https://api-uib.intark.uh-it.no/applications/a544854d-a1f6-46a9-8485-4da1f6a6a966/subscriptions?subscription=21e60a64-5a72-4ae7-a60a-645a72cae7e3#s | |
| profile-valkey-secret               | This Repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |
| profile-varnish-ban-token           | This Repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |
| profile-varnish-secret              | This Repo |  | Regenerate with i.e `apg -a 1 -n 10 -m 20` or `uuidgen` |

Profile also has additional secrets controlled by i.e the Postgres operator, ingress controller or
Helm - these will not be touched by us.

**Secrets we should leave as is:**
- sh.helm.release.v1.valkey.v1 (handled by Helm)
- sh.helm.release.v1.valkey.v2 (handled by Helm)
- sh.helm.release.v1.varnish-cache.v1 (handled by Helm)
- sh.helm.release.v1.varnish-cache.v2 (handled by Helm)
- sh.helm.release.v1.varnish-cache.v3 (handled by Helm)
- profile.bgo1.prod.rail.uib.no-tls (Handled by the ingress controller)
- profile-db-ca (Handled by the cloudnative_pg operator)
- profile-db-replication (Handled by the cloudnative_pg operator)
- profile-db-server (Handled by the cloudnative_pg operator)

