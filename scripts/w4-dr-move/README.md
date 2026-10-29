# W4 data region move script

This script simplifies the process of switching primary region in both a controlled and forced manner.

The script will wait for every phase to finish and prompt for user input on the different steps.

TODO: Refer to documentation about how this handover happens

## Requirements

- `git`
- `kubectl`
- `flux`
- `rg`
- `yq`

Run from inside this repository.

We also require that both source and target cluster is available with kubectl locally from the pc. See [How to access cluster from local machine](../../docs/how-to/access-cluster-from-local-machine.md)

## Command

```bash
# Moving from bgo1 to osl1 in prod environment (without triggering reconciliation manually)
scripts/w4-dr-move/w4-dr-move.sh --no-reconcile move --from bgo1 --to osl1

# Moving from osl1 to bgo1 in prod environment (without triggering reconciliation manually)
scripts/w4-dr-move/w4-dr-move.sh --no-reconcile move --from osl1 --to bgo1
```

## Flags

Global flags (apply before `move`):

- `--dry-run`: Print what would run, do not execute commands.
- `--yes`: Skip interactive confirmations.
- `--no-git`: Do not `git add/commit/push` (still edits files unless `--dry-run`).
- `--no-reconcile`: Skip forced Flux reconcile/watch steps (kubectl checks/waits still run).
- `--namespace <name>`: Kubernetes namespace. Default: `adm-it-pub-w4`.
- `--kustomization <n>`: Flux kustomization name. Default: `w4`.
- `--context-scope <prod|test>`: Which kube contexts to use. Default: `prod`.
  - `prod` -> `bgo1-prod-wc`, `osl1-prod-wc`
  - `test` -> `bgo1-test-wc`, `osl1-test-wc`
- `--wait-token-timeout <seconds>`: Max seconds to wait for demotion token and health gates. Default: `600`.
- `--wait-token-interval <seconds>`: Poll interval in seconds. Default: `10`.
- `--no-wait-token`: Disable automatic waiting for demotion token (will prompt to paste token unless `--token` is provided).
- `-h`, `--help`: Show help.

`move` flags:

- `--from <bgo1|osl1>`: Current primary region (must match `primary_cluster` in both region `RAIL/w4.yaml` files).
- `--to <bgo1|osl1>`: Target region to become primary.
- `--token <demotion_token>`: Optional; if omitted or `--no-wait-token` is not set, the script waits for and extracts demotion token from the `from` cluster.

## What `move` does (step-by-step)

The `move` command performs this sequence:

1. **Prepare demotion in `--from`** by editing the `--from` region `RAIL/w4.yaml` (in `spec.postBuild.substitute`) and setting:
   - `promotion_token: ""`
   - `primary_cluster: w4-<to>-prod`
   - `source_cluster: w4-<to>-prod`
   - `is_replica: "true"`
   - `mq_listen_replicas: "0"`
   - `phpfpm_pvm_readonly: "true"`
2. **Commit + push** those changes (unless `--no-git`), then **optionally** runs `flux reconcile`/watch (skipped when `--no-reconcile`).
3. **Demotion token acquisition**:
   - If `--token` is provided, it is used.
   - Otherwise, the script waits for and extracts the demotion token from the `--from` cluster (unless `--no-wait-token`, in which case it prompts for manual paste).
4. **Flush local volumes to S3 in `--from`**: triggers Jobs from CronJobs `w4-sync-files-to-s3` and `w4-sync-assets-to-s3`, then waits for those Jobs to complete (treats Job `NotFound` as “already finished/cleaned up”).
5. **Replicate S3 to the new region (`--to`)**: triggers Jobs from CronJobs `w4-replicate-files-s3-between-regions` and `w4-replicate-assets-s3-between-regions` in the `--to` environment.
6. **Promote `--to`** by editing the `--to` region `RAIL/w4.yaml` (in `spec.postBuild.substitute`) and setting:
   - `promotion_token: "<DEMOTION_TOKEN>"`
   - `primary_cluster: w4-<to>-prod`
   - `source_cluster: w4-<to>-prod`
7. **Commit + push** promotion changes (unless `--no-git`), then **optionally** runs `flux reconcile`/watch (skipped when `--no-reconcile`).
8. **Gate before workload flip**: waits until the target cluster reports the promotion token applied and the cluster is healthy.
9. **Flip workload flags** so only `--to` is active by editing *both* region `RAIL/w4.yaml` files (in `spec.postBuild.substitute`) and setting:
   - In **`--to` (new primary)**:
     - `is_replica: "false"`
     - `mq_listen_replicas: "1"`
     - `suspend_replicate_files: "true"`
     - `suspend_sync_files: "false"`
     - `phpfpm_pvm_readonly: "false"`
   - In **`--from` (new replica)**:
     - `is_replica: "true"`
     - `mq_listen_replicas: "0"`
     - `suspend_replicate_files: "false"`
     - `suspend_sync_files: "true"`
     - `phpfpm_pvm_readonly: "true"`

   Then it commits/pushes and optionally reconciles.
