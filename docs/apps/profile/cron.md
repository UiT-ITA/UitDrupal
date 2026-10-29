# Cron jobs

Drupal / Profile has some required jobs that run at specific points of the day.

| Job Name                  | Environments        | Interval                   | Description                                                                                              |
| ------------------------- | ------------------- | -------------------------- | -------------------------------------------------------------------------------------------------------- |
| Drupal Cron               | All environments    | Every 15 minutes           | Triggers application-managed cron jobs specified through Drupal.                                         |
| Deployment job            | All environments    | On deployment of new image | Runs `drush deploy` to synchronize configuration changes and database updates in Drupal.                 |
| Backup files              | Production only     | 01:00 every night          | Creates a tar file of all files in profile and pushes it to S3 in the profile-production project.        |
| Backup developer database | Production only     | 01:00 every night          | Creates a .sql.gz dump of certain parts of the database and pushes it to S3 in the profile-test project. |
| Database restore          | Test / Sandbox only | 02:35 every night          | Restores the Postgres database from the latest developer database dump.                                  |
