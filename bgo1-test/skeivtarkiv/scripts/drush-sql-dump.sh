#!/bin/bash
#####################################################################
# This script makes a copy of the database, and dumps it into
# $targetDir. Assumes drush is set up properly.
#
# Parameters: $1 = Target directory, $2 = Name of database file outputted
#
#####################################################################

targetDir="$1"
outputFile="$2"

if ! test -d "$targetDir"; then
    echo "[cron] Skipping because target directory '$targetDir' does not exist"
    exit
fi
if [ -z "$outputFile" ]; then
    echo "[cron] Skipping because outputFile (parameter 2) is not set"
    exit
fi

export_errors=0
structure_tables_list='cache,cache_*,public.cache*,semaphore,sessions,search_index,watchdog'

echo "[cron] Starting DB-dump for use under development ($0)"

create_dump() {
    local outfile="$1"
    local extra_args="$2"
    local drush_outfile="$outfile"
    local drush_gzip_flag=""

    if [[ "$outfile" == *.gz ]]; then
        drush_gzip_flag="--gzip"
        drush_outfile="$${outfile%.gz}"
    fi

    # Export
    if ! drush sql:dump $extra_args $drush_gzip_flag --structure-tables-list="$structure_tables_list" --result-file="$drush_outfile"; then
        echo "[cron] ERROR: Failed to produce backup database #Return code: $?" 1>&2
        export_errors=$((export_errors + 1))
    fi

    # Verify file size on dump
    if [ ! -s "$outfile" ]; then
        echo "[cron] ERROR: Empty backup file produced: $outfile" 1>&2
        export_errors=$((export_errors + 1))
    fi
}

create_dump "$targetDir/$outputFile" "--create-db"

if [ $export_errors -gt 0 ]; then
    echo "[cron] ERROR: Backup script completed with $export_errors errors"
    exit 1
else
    echo "[cron] Finished DB-dump for use un development ($0) with $export_errors errors"
fi
