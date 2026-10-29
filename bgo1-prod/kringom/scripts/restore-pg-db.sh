#!/bin/bash
#####################################################################
# This script drops the database and restores it from a .sql file. (Can be .sql.gz)
#
# Parameters: $1 = Target sql file to run
#
#####################################################################

targetFile="$1"

if ! test -f "$targetFile"; then
    echo "[cron] Skipping because target file '$targetFile' does not exist"
    exit
fi

echo "[cron] Dropping existing database"
if ! PGPASSWORD="$DRUPAL_DATABASE_PASSWORD" psql -U "$DRUPAL_DATABASE_USERNAME" -h "$DRUPAL_DATABASE_HOST" -d "$DRUPAL_DATABASE_NAME" --single-transaction -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"; then
    echo "[cron] ERROR: Failed to drop and recreate public schema. Return code: $?" 1>&2
    exit 1
fi

# The database seems to return before being fully cleared out, causing index errors when re-creating further down for some reason
# We tried --single-transaction, but it seemingly didn't fix the problem
# We therefore sleep to allow the database to finish the entire transaction before continuing
echo "[cron] Sleeping for 10 seconds"
sleep 10

echo "[cron] Running sql file ($targetFile)"

if ! pg_restore -j 8 --clean --if-exists --no-owner --no-privileges --username="$DRUPAL_DATABASE_USERNAME" --host="$DRUPAL_DATABASE_HOST" --dbname="$DRUPAL_DATABASE_NAME" "$targetFile"; then
    echo "[cron] ERROR: Failed to run sql file. Database is most likely in a broken state! Return code: $?" 1>&2
    exit 1
fi

if ! drush deploy; then
    echo "[cron] ERROR: Failed to run drush deploy. Database is most likely in a broken state! Return code: $?" 1>&2
    exit 1
fi

echo "[cron] Finished running sql file ($targetFile)"