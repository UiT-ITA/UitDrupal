# W4 disaster recovery (bgo1 / osl1)

Runbook for moving/failing over W4 between the two RAIL regions **bgo1** and **osl1**.

Relevant docs:
- Multi-region DR for persistent data: [multi-region-disaster-recovery-of-persistent-data.md](../../how-to/multi-region-disaster-recovery-of-persistent-data.md)
- CNPG docs: [https://cloudnative-pg.io/documentation/](https://cloudnative-pg.io/documentation/)
- Continuity testing: `docs/apps/w4/continuity-test.md`

## Testing the revovery scenarios
When testing the various solutions below, it is adivsed to do that in dedicated environments created for
the specific purpose of testing.

And, as full backups are only created nightly, ensure you create a manual full backup in the "source" environment(s)
before commencing with testing.

This can be done by calling the cnpg kubectl plugin or creating a cnpg `Backup` resource.
```shell
# If you don't have the cnpg plugin locally, run on the specific cluster's login host
kubectl cnpg backup w4-db --method plugin --plugin-name barman-cloud.cloudnative-pg.io -n adm-it-pub-w4
```
or
```yaml
# apply with kubectl -f
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: backup-example-with-unique-name
spec:
  cluster:
    name: w4-db
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
```
## Move between regions

### Scripted failover

`scripts/w4-dr-move/w4-dr-move.sh`.

The script handles doing a controlled move between two regions. See the [script documentation](../../../scripts/w4-dr-move/README.md). It automates the manual failover below.

Runbook:

- Current primary (`<from>`):
- Target primary (`<to>`):

```bash
# Example of how to call it
scripts/w4-dr-move/w4-dr-move.sh --no-reconcile move --from bgo1 --to osl1
```

Manual steps are below.

### Manual failover (checklist)

Edits are in `spec.postBuild.substitute` in `bgo1-prod/RAIL/w4.yaml` and `osl1-prod/RAIL/w4.yaml`.

Runbook:

- Current primary (`<from>`):
- Target primary (`<to>`):

- [ ] **Pick direction**: `<from>` (current primary) → `<to>` (new primary).
- [ ] **Confirm current primary**: `primary_cluster` should match in both regions’ `RAIL/w4.yaml`.
- [ ] In **`<from>`** `RAIL/w4.yaml` (make it safe to demote):
  - [ ] Set `promotion_token: ""` – disables any in-flight promotion, ensuring the old primary cannot become active primary again until a new token is set.
  - [ ] Set `primary_cluster: w4-<to>-prod` – new primary cluster
  - [ ] Set `source_cluster: w4-<to>-prod` – replicate data from the new primary region
  - [ ] Set `is_replica: "true"` - disables cluster primary status, prevents cron jobs from running
  - [ ] Set `mq_listen_replicas: "0"` - disables listening to rabbitmq and invalid processing of messages
  - [ ] Set `phpfpm_pvm_readonly: "true"` - puts volumes in read-only mode
- [ ] Commit and reconcile, then get the **demotion token** from the `<from>` CNPG cluster:

```bash
# This script should get you it
kubectl --context <from>-prod-wc -n adm-it-pub-w4 get cluster w4-db -o yaml | rg -n 'demotion|token'
```

- [ ] **Flush local data to S3 in `<from>`** (trigger Jobs from CronJobs and wait):
  - [ ] `w4-sync-files-to-s3`
  - [ ] `w4-sync-assets-to-s3`
- [ ] **Replicate S3 → S3 into `<to>`** (trigger Jobs in `<to>` and wait):
  - [ ] `w4-replicate-files-s3-between-regions`
  - [ ] `w4-replicate-assets-s3-between-regions`
- [ ] In **`<to>`** `RAIL/w4.yaml`:
  - [ ] Set `promotion_token: "<DEMOTION_TOKEN>"`
  - [ ] Set `primary_cluster: w4-<to>-prod`
  - [ ] Set `source_cluster: w4-<to>-prod`
- [ ] Commit and reconcile; wait until Cluster in `<to>` is healthy.
- [ ] Flip workload flags so only `<to>` writes:
  - [ ] In **`<to>`** (`RAIL/w4.yaml` new primary):
      - [ ] `is_replica: "false"`
      - [ ] `mq_listen_replicas: "1"`
      - [ ] `phpfpm_pvm_readonly: "false"`
      - [ ] `suspend_replicate_files: "true"`
      - [ ] `suspend_sync_files: "false"`
  - [ ] In **`<from>`** (`RAIL/w4.yaml` previous primary, now replica):
      - [ ] `is_replica: "true"`
      - [ ] `mq_listen_replicas: "0"`
      - [ ] `phpfpm_pvm_readonly: "true"`
      - [ ] `suspend_replicate_files: "false"`
      - [ ] `suspend_sync_files: "true"`

## Scenario 2: primary region down / corrupted (unplanned failover + rebuild)

Assume bgo1 was primary and is gone or corrupted. Promote osl1, then rebuild bgo1 as replica from backup/WAL.

Time is usually key here here as data flows between regions.

Runbook:

- Current primary (`<from>`):
- Surviving replica (`<survivor>`):

- [ ] If the dead region is partly alive, force it into replica-safe/read-only as soon as possible to avoid MQ loss. Go to `<from>-prod/RAIL/w4.md`
  - [ ] Set `is_replica: true`
  - [ ] Set `mq_listen_replicas: "0"`
  - [ ] Set `phpfpm_pvm_readonly: "true"`
  - [ ] Commit, push and reconcile
- [ ] Detach `<survivor>`. Go to `<survivor>-prod/RAIL/w4.md`
  - [ ] Set `primary_cluster: w4-<survivor>-prod`
  - [ ] Set `source_cluster: w4-<survivor>-prod`
  - [ ] Set `suspend_replicate_files: true`
  - [ ] Commit, push and reconcile
- [ ] Depending on situation, manually trigger replicate files cron job once to reduce data loss.
  - E.g Run if disaster only is relevant for database
  - E.g Do not run if files are corrupted

Validate which scenario below fits the current disaster. They are ordered in most to least optimal.

**Optimal scenario**: `<survivor>` now works perfectly:
- [ ] Flip workload flags so only `<survivor>` writes:
  - [ ] In **`<survivor>`** (`RAIL/w4.yaml` new primary):
      - [ ] `is_replica: "false"`
      - [ ] `mq_listen_replicas: "1"`
      - [ ] `phpfpm_pvm_readonly: "false"`
      - [ ] `suspend_replicate_files: "true"`
      - [ ] `suspend_sync_files: "false"`
  - [ ] In **`<from>`** (`RAIL/w4.yaml` previous primary, now replica):
      - [ ] `is_replica: "true"`
      - [ ] `mq_listen_replicas: "0"`
      - [ ] `phpfpm_pvm_readonly: "true"`
      - [ ] `suspend_replicate_files: "false"`
      - [ ] `suspend_sync_files: "true"`
- [ ] In this case, osl1 should be working fine and we should just need a DNS switchover.
- [ ] Rebuild old primary

**Database corruption scenario**: `<survivor>` database is still corrupted and we need to restore from backup

In the case osl1 is not working properly, we can do a point in time database restore in the old primary.

- [ ] Update `<from>-prod/w4/patches/cluster-db-pg.yaml`
  - [ ] Uncomment `recoveryTarget.targetTime`
  - [ ] Set `targetTime` to specific restore point in time
  - [ ] Set `primary_cluster: w4-<from>-prod`
  - [ ] Set `source_cluster: w4-<survivor>-prod`
  - [ ] Ensure the S3 backup destination won’t collide:
    - Either **remove/rename** existing content in the destination path, or temporarily change `backup_name` in `bgo1-prod/RAIL/w4.yaml` (used in the `ObjectStore` destination path via `${backup_name}`).
- [ ] Commit, push
- [ ] Delete database cluster in `<from>-prod/w4`
- [ ] Reconcile
- [ ] Hopefully the primary should be back, if so, switch workload
  - [ ] In **`<from>`** `RAIL/w4.yaml`:
      - [ ] `is_replica: "false"`
      - [ ] `mq_listen_replicas: "1"`
      - [ ] `phpfpm_pvm_readonly: "false"`
      - [ ] `suspend_replicate_files: "true"`
      - [ ] `suspend_sync_files: "false"`
  - [ ] In **`<survivor>`** `RAIL/w4.yaml`
      - [ ] `is_replica: "true"`
      - [ ] `mq_listen_replicas: "0"`
      - [ ] `phpfpm_pvm_readonly: "true"`
      - [ ] `suspend_replicate_files: "false"`
      - [ ] `suspend_sync_files: "true"`
- [ ] Rebuild replica to source from primary

**Full disaster scenario**: Both files and/or database are corrupted in all regions and we need a restore from off-site backup.

## Reconstructing a region

### Database reconstruction

1. Configure the region as replica in `RAIL/w4.yaml`:
   - [ ] `primary_cluster: w4-<primary>-prod`
   - [ ] `source_cluster: w4-<primary>-prod`
   - [ ] `is_replica: "true"`
   - [ ] `mq_listen_replicas: "0"`
   - [ ] `phpfpm_pvm_readonly: "true"`
   - [ ] `suspend_replicate_files: "false"`
   - [ ] `suspend_sync_files: "true"`
2. [ ] Enable restore/bootstrap in `<region>-prod/w4/patches/cluster-db-pg.yaml`:
   - Uncomment the `spec.bootstrap.*.recovery` block so the cluster can be created by restoring from the configured external cluster/object store.
3. [ ] Ensure the S3 backup destination won’t collide:
   - Either **remove/rename** existing content in the destination path, or temporarily change `backup_name` in `bgo1-prod/RAIL/w4.yaml` (used in the `ObjectStore` destination path via `${backup_name}`).

Commit and wait for reconciliation and the CNPG cluster to be healthy and replicating from primary.

### File reconstruction

Files would have to be copied over from the on-prem backup in the case that it is entirely unavailable in NREC.