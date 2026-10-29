# W4 continuity test (bgo1 / osl1)

Runbook for some different scenarios, relevant for continuity testing.
We recommend creating a separate work file where you copy scenario and runbooks to while doing continuity tests.

Related:
- `docs/apps/w4/disaster.md` (manual DR steps + rebuild)
- `docs/apps/w4/backup.md` (backup/replication details + where schedules live)
- `scripts/w4-dr-move/w4-dr-move.sh` (controlled move) + `scripts/w4-dr-move/README.md`

## Prerequisites

- You can operate both clusters (`bgo1-prod-wc`, `osl1-prod-wc`)
- Both regions agree on current `primary_cluster` in `bgo1-prod/RAIL/w4.yaml` and `osl1-prod/RAIL/w4.yaml`
- Have a reasonable overview of the flags in `spec.postBuild.substitute`:
  - DB: `primary_cluster`, `source_cluster`, `promotion_token`
  - Workload: `is_replica`, `mq_listen_replicas`, `phpfpm_pvm_readonly`
  - Files jobs: `suspend_sync_files`, `suspend_replicate_files`

## Scenario 1: controlled move (bgo1 <-> osl1)

This is the most optimal scenario. We know e.g maintenance or downtime will happen in current primary region, so we can move it ahead of time to the other region in a controlled manner.

Follow Scenario 1 in [`docs/apps/w4/disaster.md`](docs/apps/w4/disaster.md)

## Scenario 2: primary region loss (fail over + rebuild)

This scenario emulates that the entire primary region would be down and we need to do a "messy" switchover to a replica region.

Follow `docs/apps/w4/disaster.md` - Scenario 2

## Scenario 3: DB corruption

This scenario emulates a rogue migration or database takeover causing the primary database to break.

Follow `docs/apps/w4/disaster.md` - Scenario 2

## Scenario 4: files corruption

This scenario

Files don’t have PITR by default. If corruption replicates, you need to **stop replication fast** and restore “last good”.

- [ ] Make a small controlled file break (known path / known files).
- [ ] Stop replication immediately:
  - [ ] set `suspend_sync_files: "true"` (stop PVC → S3)
  - [ ] set `suspend_replicate_files: "true"` (stop S3 → S3)
  - [ ] keep replicas `phpfpm_pvm_readonly: "true"`
- [ ] Restore from whatever “last good” source you have (see `backup.md`, incl on-prem snapshots).
- [ ] Only re-enable sync/replication after verifying files look right.

## Afterwards

- [ ] Make sure only one region is writing/consuming, and the other is replica-safe.
- [ ] If anything was weird, write it down and fix the docs/script while it’s fresh.
- [ ] Smoke test:
  - [ ] Request lands in new primary
  - [ ] One write works
  - [ ] One file upload works

**yaml checklist:**

- [ ] `primary_cluster` is `w4-<to>-prod` in **both** regions’ `RAIL/w4.yaml`
- [ ] In the new primary `<to>`:
  - [ ] `is_replica: "false"`
  - [ ] `mq_listen_replicas: "1"`
  - [ ] `phpfpm_pvm_readonly: "false"`
  - [ ] `suspend_sync_files: "false"`
  - [ ] `suspend_replicate_files: "true"`
- [ ] In the new replica `<from>`:
  - [ ] `is_replica: "true"`
  - [ ] `mq_listen_replicas: "0"`
  - [ ] `phpfpm_pvm_readonly: "true"`
  - [ ] `suspend_sync_files: "true"`
  - [ ] `suspend_replicate_files: "false"`