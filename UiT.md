## Rails and kubernetes

### What is rails

UiT have access to the RAIL Container Platform at UiB 

RAIL allows product teams at UiB to host container based applications on a shared infrastructure operated by the ITA Plattform Team.

RAIL provides shared Kubernetes clusters running on top of the NREC infrastructure. Each product team get access to and controls one or more namespaces that are present in all RAIL clusters.

[Documentation](https://docs.bgo1.prod.rail.uhdc.no/docs/index.html)

### Access

You cannot access the kubernetes cluster directly. Use ssh management host.

Example .ssh/config file

```
Host bgo1-test-login-04
  User espenr
  LocalForward localhost:22000 /home/espenr/.rail-socket  
  Hostname login-04.bgo1.test.rail.uhdc.no
  # Next line is only needed if you get hmac error message in windows ssh
  MACs hmac-sha2-512
```

You will need to have a user with access created by UiB ITA Plattform Team.
ssh keys to authenticate you must also be setup at the management server

### Working with the kubernetes cluster

Our kubernetes namespace for drupal test is uit-it-webadm-drupal-test

```pwsh
ssh bgo1-test-login-04

# Set default namespace. The kubernetes namespace you currently work on
# This allows you to not having to enter -n adm-it-xxx for every command
# First time you run a command you might get this error:
# Please visit the following URL in your browser manually: http://localhost:22000
# Open the url in a browser to login
kubectl config set-context --current --namespace=uit-it-webadm-drupal-test

# List pods
kubectl get pod
```

You can also use the tool k9s that is a console application with menus that makes things
a bit easier. Tip: To exit use :q like in vi

At the command line you can use flux command to get status from flux

```pwsh
flux -n uit-it-webadm get all
```

### Sops

SOPS is a tool used to encrypt, decrypt, and manage secrets—most commonly in DevOps and GitOps workflows.

[Github project link](https://github.com/getsops/sops)

To encrypt a file:

sops --encrypt --in-place secret-db.yaml

This is the mechanism used to encrypt secrets files  in the source tree. 

Alternatively azure KeyVault could have been used.

### GitOps 

Flux is connected to a git repository for automatic deployment

[Github project link](https://github.com/UiT-ITA/UitDrupal)

## Database

Use UiB system for auto generating a managed database

Example yaml for creating a database

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: ${app_name}-db
spec:
  instances: 1
  monitoring:
    enablePodMonitor: true
  bootstrap:
    initdb:
      database: ${app_name}
      owner: ${app_name}
      secret:
        name: ${app_name}-db-secret
  storage:
    size: 16Gi

  postgresql:
    parameters:
      shared_buffers: "256MB"

```

## Questions

Brukerprovisjonering i drupal. Fra RI? Hva hentes over? Opprettes brukere i drupal?
