#!/bin/bash

# Usage:
#
#   ./sync-s3.sh <source> <destination>
#
# Examples:
#   From S3 to local
#   ./sync-s3.sh "s3://profile.no/backups/drupal-files/" /var/backups/files
#
#   From local to S3
#   ./sync-s3.sh /var/backups/files "s3://profile.no/backups/drupal-files/"
#
# This script syncs a local directory to an S3 prefix.
#
# Required environment variables:
#   AWS_ACCESS_KEY_ID        - Your AWS access key ID
#   AWS_SECRET_ACCESS_KEY    - Your AWS secret access key
#   AWS_ENDPOINT_URL         - S3 endpoint URL
#   [Optional] AWS_REGION    - AWS region (default: None)
#
# Optional environment variables:
#   DRY_RUN - when true, run aws with --dryrun (default: false)
#   DELETE  - when true, run aws with --delete (default: true)

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <source> <destination>"
    exit 1
fi

SOURCE="$1"
DESTINATION="$2"

# Check required env vars
required_vars=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_ENDPOINT_URL")
for var in "$${required_vars[@]}"; do
    if [ -z "$${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

AWS_REGION="$${AWS_REGION:-None}"
AWS_ENDPOINT_URL="$${AWS_ENDPOINT_URL}"

DRY_RUN="$${DRY_RUN:-false}"
DELETE="$${DELETE:-true}"

AWS_ARGS=(--region "$AWS_REGION")
AWS_ARGS+=(--endpoint-url "$AWS_ENDPOINT_URL")

DRYRUN_FLAG=""
if [ "$DRY_RUN" = "true" ]; then
    DRYRUN_FLAG="--dryrun"
fi

DELETE_FLAG=""
if [ "$DELETE" = "true" ]; then
    DELETE_FLAG="--delete"
fi

echo "Syncing $SOURCE -> $DESTINATION"
aws s3 sync "$SOURCE" "$DESTINATION" "$${AWS_ARGS[@]}" $DELETE_FLAG --no-follow-symlinks --no-guess-mime-type $DRYRUN_FLAG --only-show-errors

echo "Sync completed successfully"
