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
if ! drush sql:drop -y; then
    echo "[cron] ERROR: Failed to drop database. Return code: $?" 1>&2
    exit 1
fi

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