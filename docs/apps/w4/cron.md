# Cron jobs

Drupal / W4 has some required jobs that run at specific points of the day.

| Job Name                            | Environments             | Interval                                  | Description                                                                                     |
| ----------------------------------- | ------------------------ | ----------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Drupal Cron                         | All primary environments | Every 15 minutes except between 01-04 UTC | Triggers application-managed cron jobs specified through Drupal.                                |
| Deployment job                      | All primary environments | After deployment of new image             | Runs `drush deploy` to synchronize configuration changes and database updates in Drupal.        |
| Sync Courses                        | All primary environments | 03:05 on Sundays                          | Synchronizes courses.                                                                           |
| Sync Study Programs                 | All primary environments | 03:15 on Sundays                          | Synchronizes study programs.                                                                    |
| Clear Room Cache                    | All primary environments | 03:25 on Sundays                          | Clears room cache.                                                                              |
| Users Sync All                      | All primary environments | 21:02 on the 25th of December             | Synchronizes users.                                                                             |
| Sync files to S3                    | Production primary only  | Every 15 minutes, at a 5 minute offset    | Syncs new files from local volume to S3.                                                        |
| Sync assets to S3                   | Production primary only  | Every 15 minutes, at a 5 minute offset    | Syncs new assets from local volume to S3.                                                       |
| Replicate files between S3 regions  | Production replica only  | Every 15 minutes, at a 10 minute offset   | Syncs new files from one S3 instance to replica environment S3.                                 |
| Replicate assets between S3 regions | Production replica only  | Every 15 minutes, at a 10 minute offset   | Syncs new assets from one S3 instance to replica environment S3.                                |
| Backup developer database           | Production only          | 01:00 every night                         | Creates a .sql.gz dump of certain parts of the database and pushes it to S3 in w4-test project. |
| Database restore                    | Test / Sandbox only      | 02:35 every night                         | Restores the Postgres database from the latest developer database dump.                         |
