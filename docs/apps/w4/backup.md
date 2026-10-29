## W4 backup policy (RAIL)

W4 data is spread across three locations: bgo1 (PVC + S3/HiB), osl1 (PVC + S3), and on-prem disk (MCB).

### Database

- **Backups & retention**: CNPG keeps 30 days of backups with point-in-time recovery (PITR) using WAL.
- **Cross-region replication**: Replication is done via WAL shipping to S3. New WAL chunks are pushed continuously (about every 5 minutes, depending on load)

### Files

- **Backup**: Files are continuously pushed from the primary replicas' PVC to S3 (every 15 minutes). Unlike the database, files do not have point-in-time rollback by default.
- **Cross-region replication**: A cron job pulls from the primary S3 and syncs to the other regions on a 15 minute interval.

The intervals are spread out in a way that files from primary should be on the replicas within 15 minutes in the best case and 30 in the worst case.

### On-prem copy

The complete S3 bucket is also copied to an on-prem located at MCB called p2pubs3backup01. The bucket is synced every 15 minutes to the directory `/mnt/pub_rail_s3_backup_mcb/w4_backup/w4/`.

There are no automated way to restore back from the on-prem backup, as it is impossible to predict a disaster big enough to take down the entire NREC. It would require setup in either on-prem or in another cloud provider.

The disk has snapshot retention:

- Hourly diff snapshots for 48 hours
- Daily snapshots for 7 days
- Weekly snapshots for 2 weeks

This on-prem snapshot is our safety net if corruption/encryption replicates everywhere before we can stop it. With this setup, we expect to be able to recover the database and files from most disaster scenarios, as long as the triggering error is within roughly two weeks.

### Configuration location

- **DB backups (retention)**:
  - `base/w4/production/objectstore-bgo-prod.yaml` -> `spec.retentionPolicy: "30d"`
  - `base/w4/production/objectstore-osl-prod.yaml` -> `spec.retentionPolicy: "30d"`
- **DB base-backup schedule**:
  - `base/w4/production/scheduled-backup.yaml` -> `spec.schedule`
- **Files: local->S3 sync + S3<->S3 replication**:
  - Schedules live in `base/w4/production/`:
    - `cronjob-sync-files-to-s3.yaml` -> `spec.schedule: "5-59/15 * * * *"` + `spec.suspend: ${suspend_sync_files:=true}`
    - `cronjob-replicate-files-s3-between-regions.yaml` -> `spec.schedule: "10-59/15 * * * *"` + `spec.suspend: ${suspend_replicate_files:=true}`
    - (same pattern for assets)
  - Region-specific endpoints/prefixes + enable/disable flags are injected from:
    - `bgo1-prod/RAIL/w4.yaml` / `osl1-prod/RAIL/w4.yaml` -> `self_*_s3`, `source_*_s3`, `suspend_sync_files`, `suspend_replicate_files`, `is_replica`
- **S3 -> on-prem copy job (bgo1)**:
  - `bgo1-prod/w4/cronjob-sync-on-prem-production-files.yaml` -> `spec.schedule: "2-59/15 * * * *"`

### Validating backups

- **Grafana**: use the Postgres dashboard and the Backups panels (CNPG + barman-cloud metrics)
- TODO: More validations through grafana / alerting?

### Developer backups

W4 test/sandbox can restore from a “developer database” dump stored in S3. This is mostly used for developers and test environments to set up a local copy and has removed a lot of session tables and such.
The developer dumps are also stored in S3 and is kept as a rolling overwriting backup every week.

- **Where restore is configured**:
  - `base/w4/production/db-restore-cron.yaml` and `base/w4/test/db-restore-cron.yaml` -> `bgo1-prod/w4/developer-database/developer-database-{DAY_OF_WEEK}.dump`.

