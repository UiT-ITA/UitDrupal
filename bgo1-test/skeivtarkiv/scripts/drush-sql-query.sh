#!/bin/bash
#####################################################################
# This script runs a SQL file against the Drupal database using Drush.
#
# Parameters: $1 = Target sql file to run
#
#####################################################################

targetFile="$1"

if ! test -f "$targetFile"; then
    echo "[cron] Skipping because target file '$targetFile' does not exist"
    exit
fi

export_errors=0

echo "[cron] Running sql file ($targetFile)"

if ! drush sql:query --file="$targetFile"; then
    echo "[cron] ERROR: Failed to run sql file. Database is most likely in a broken state! Return code: $?" 1>&2
    exit 1
fi

echo "[cron] Finished running sql file ($targetFile)"