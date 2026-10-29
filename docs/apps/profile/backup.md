## Profile backup policy (RAIL)

Profile production data lives in **bgo1-prod** with **osl1-prod** set up to take over on short notice. DR procedures: [disaster.md](./disaster.md).

### Database

- **Backups & retention**: Postgres keeps 30 days of backups with point-in-time recovery. Nightly base backup at 01:00.
- **Cross-region replication**: A cron copies the `postgres/` prefix from bgo S3 to osl S3 every 15 minutes.

### Files

- **Backup**: Drupal files on PVC `profile-files` are pushed to S3 every 15 minutes. Unlike the database, files do not have point-in-time rollback by default.
- **Cross-region replication**: A cron pulls from primary S3 and syncs to the other region on a 15 minute interval.

Files from primary should be on the replica within 15 minutes in the best case and 30 in the worst case.

### On-prem copy

The complete S3 bucket is also copied to an on-prem located at MCB called p2pubs3backup01. The bucket is synced every 15 minutes to the directory `/mnt/pub_rail_s3_backup_mcb/profile_backup/profile/`.

There are no automated way to restore back from the on-prem backup, as it is impossible to predict a disaster big enough to take down the entire NREC. It would require setup in either on-prem or in another cloud provider.

The disk has snapshot retention:

- Hourly diff snapshots for 48 hours
- Daily snapshots for 7 days
- Weekly snapshots for 2 weeks

This on-prem snapshot is our safety net if corruption/encryption replicates everywhere before we can stop it. With this setup, we expect to be able to recover the database and files from most disaster scenarios, as long as the triggering error is within roughly two weeks.

### Configuration location

- **DB backups (retention)**:
  - `base/profile/production/objectstore.yaml` -> `spec.retentionPolicy: "30d"`
- **DB base-backup schedule**:
  - `base/profile/production/scheduled-backup.yaml` -> `spec.schedule`
- **Files: local->S3 sync + S3<->S3 replication**:
  - Schedules in `base/profile/production/`:
    - `cronjob-sync-files-to-s3.yaml` -> `spec.schedule`
    - `cronjob-replicate-files-s3-between-regions.yaml` -> `spec.schedule`
- **Postgres S3<->S3 replication**:
  - `base/profile/production/cronjob-replicate-postgres-s3-between-regions.yaml` -> `spec.schedule`

### Validating backups

- **Grafana**: Postgres dashboard, Backups panels (CNPG + barman-cloud).
- TODO: More validations through grafana / alerting?

### Developer backups

Test/sandbox can restore from a “developer database” dump in S3 (`profile.uib.no-test`). Rolling overwrite by day-of-week.
Production creates a dump for test at 01:00