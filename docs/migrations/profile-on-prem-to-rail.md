# Migration of Profile from on-prem to RAIL

Information needed for the migration to RAIL.

## Migration was performed: 15.01.2026

## Step-by-step Migration plan:

Days before migration:

- [x] Create a task/change in UIBHjelp to modify routing (If we route through
  masterlb)
- [x] Ask platform team to prepare required configuration in MasterLB
- [x] Verify that correct ingress is created in RAIL (masterlb forwards to
  profile.bgo1.prod.rail.uib.no)

Migration:

- [x] Verify requirements for running migration script
  - [x] Tunnel created to bgo1-prod from local machine
  - [x] Connected to VPN
  - [x] Using a machine that is case sensitive (preferably linux, NOT macos)
- [x] Validate that migration script is configured correctly (Not accidentally
  still pointing to test)
- [x] Set on-prem instance of profile to maintenance mode - This is to avoid
  database changes during migration
- [x] Update RabbitMQ secret in RAIL environment to push events to correct event
  stream (If we take over existing queue)
- [x] Restart profile instance to update environment
- [x] Run migration script and let it completely finish
- [x] Update MasterLB to point to RAIL
- [x] Disable maintenance mode for RAIL environment
- [x] Purge varnish cache in masterLB (if necessary, profile is not cached, w4
  might cache maintenance mode pages)

At this point, the migration should be complete! (Hopefully 🥳)

### Post migration

- [x] Enable and ensure database backups are enabled and works properly
- [ ] Enable and ensure test database dumps are produced properly
- [ ] Update profile test environments to source database dumps from RAIL

### Migration script

We have created an automated script that takes care of creating a database dump
and migrating the file directory from the on-prem server, through a proxy
machine and upload it to the RAIL server.

The script exists in this repo in `scripts/profile-migration`.

The README contains relevant information for how to run it. It is recommended to
test it towards a test environment before running on production.


## Disaster recovery plan

### Rollback - Same day disaster

- [ ] Roll back masterLB changes
- [ ] Disable maintenance mode on on-prem server

### Backsync - Multi day, db recovery + files recovery

TODO: Should we make a script or just steps? It is kinda impossible to predict
what specifically would go wrong and whether we should roll back or fix the
problem.