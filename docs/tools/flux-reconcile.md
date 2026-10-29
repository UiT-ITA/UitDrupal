# flux-reconcile.sh

A utility script that triggers an immediate Flux reconcile for a service
kustomization in a specific cluster.

## Usage

> `Usage: ./flux-reconcile.sh <cluster> <service>`

Examples:

- `./flux-reconcile.sh bgo1-test skeivtarkiv`
- `./flux-reconcile.sh bgo1-prod w4`
- `./flux-reconcile.sh osl1-test profile`

