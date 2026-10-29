# Skeivtarkiv

- Status: Only test environment
- Clusters: bgo1-test
- App base: drupal
- Service level: C (Normal operation)
- Urls
  - bgo1-test
    - RAIL:
      [https://skeivtarkiv.bgo1.test.rail.uib.no/](https://skeivtarkiv.bgo1.test.rail.uib.no/)
    - MasterLB:
      [https://skeivtarkiv.test.uib.no/](https://skeivtarkiv.test.uib.no/)

## Considerations

- Skeivtarkiv is a Drupal 7 application running on MariaDB and is therefore
  quite outdated wrt. modern drupal apps.
- Custom database setup, see database section
- Outdated Drush makes certain scripts for this custom and exists in
  `base/skeivtarkiv`. This includes database backup + daily restore in test.
  Cron job runs.
- Due to no multi mount r/w volumes, are all drupal apps currently running with
  an affinity for a single node. This means that ALL applications needing files
  in Drupal requires to run on a single node. This is very limiting wrt.
  resources and should be updated asap.

## Database + Files

Because it is MariaDB, it is hosted as a StatefulSet in cluster and currently
only has one replica. This means a single point of failure in the database.
Database does not have autoscaling of pv and might fill up, causing a failure.
By default it has no built in backup mechanism or restore mechanism, which means
we need to do this manually. Database dumps are stored in S3 currently. Dumps
are created through a custom cron job running 2 am every night. Test
environments auto restores a production version every night at 3 am.

Files are stored in a similar fashion to database in S3. Backup happens at 2 am
and restored at 3 am.

> Backups are only retained one week currently before it overwrites. This will
> be changed before skeivtarkiv is moved to RAIL As Skeivtarkiv is still running
> in production on-prem, a script runs at 1 am every night to push a new backup
> to S3 to ensure that the test environment is always up to date.

### Restoring in case of disaster

TODO: No formalized way currently, must manually download from S3 and run drush
commands. Should be properly formalized before production

## Setting up a new environment

TODO: What is required to do in order to set up a new environment. E.g Feide
setup, potential other manual steps, database sync, etc.

TODO:
- Dashboards
- Logs
- Alerts