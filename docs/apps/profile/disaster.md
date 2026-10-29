# Profile disaster recovery (bgo1 / osl1)

Runbook for restoring Profile or failing over between **bgo1-prod** and **osl1-prod**.

Profile runs in one production region at a time.

Relevant docs:
- Backups (database + files): [backup.md](./backup.md)
- CNPG: [https://cloudnative-pg.io/documentation/](https://cloudnative-pg.io/documentation/)
- NREC object storage: [profile.uib.no container](https://dashboard.nrec.no/dashboard/project/containers/container/profile.uib.no)

## Switch production bgo1-prod → osl1-prod

### Failover

- [ ] In `bgo1-prod/RAIL/profile.yaml`, set suspend on both sync files and replicate files.
- [ ] Commit and push.
- [ ] Set restore times in `osl1-prod/profile/restore-db/patches/db-restore.yaml` and `osl1-prod/profile/restore-files/restore-files.yaml`.
- [ ] Uncomment `osl1-prod/RAIL/profile.yaml`.
- [ ] In `osl1-prod/profile/kustomization.yaml`, uncomment `./restore-db`, `./restore-files`, and `restore-db/patches/db-restore.yaml`.
- [ ] Commit and push.
- [ ] When post-deploy is done and environment is up, set MasterLB ingress to `profile.osl1.prod.rail.uib.no`.

### Decommission old region

Once the new Profile is producing backups as expected, you can either move back or decommission.
Currently you need to manually update so the data replication switches from bgo -> osl to osl -> bgo.

- [ ] Comment out `bgo1-prod/RAIL/profile.yaml`.
- [ ] In `bgo1-prod/profile/kustomization.yaml`, comment `./restore-db`, `./restore-files`, and `restore-db/patches/db-restore.yaml`.
- [ ] Commit and push.
- [ ] Wait until `bgo1-prod` is fully down.
- [ ] Delete `bgo1-prod/<backup_name>` in [nrec objectstorage](https://dashboard.nrec.no/dashboard/project/containers/container/profile.uib.no).
