# flux-drift.sh

A utility script that checks for drift between what is currently deployed in the
cluster and what is defined in the Git repository. This helps identify if any
manual changes have been made to resources or if there are configuration
differences.

## Usage

> `Usage: ./flux-drift.sh <path> <service>`

Examples:

- `./flux-drift.sh bgo1-test/skeivtarkiv skeivtarkiv` - Checks for drift in the
  skeivtarkiv service in bgo1-test environment
- `./flux-drift.sh bgo1-prod/turspor turspor` - Checks for drift in the turspor
  service in bgo1-prod environment
- `./flux-drift.sh osl1-test/profile profile` - Checks for drift in the profile
  service in osl1-test environment

## Output

The script uses `flux diff` to compare the deployed kustomization with the Git
repository. If there are no differences, the command will exit successfully with
no output. If drift is detected, it will show the differences in unified diff
format.

Example output when drift is detected:

```diff
--- cluster
+++ git
@@ -1,5 +1,5 @@
 apiVersion: apps/v1
 kind: Deployment
 metadata:
-  replicas: 2
+  replicas: 3
   name: skeivtarkiv-drupal
```

## Notes

- The script requires access to the Kubernetes cluster where the resources are
  deployed
- It compares recursively through the entire kustomization tree
- The kustomization name is automatically constructed as `adm-it-pub-<service>`
- The path should match the directory structure in the repository (e.g.,
  `bgo1-test/skeivtarkiv`)

