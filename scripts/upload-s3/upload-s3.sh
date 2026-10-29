#!/bin/bash

# Usage:
#
#   ./upload-s3.sh <s3_path> <local_file_path>
#
# Example:
#
#   ./upload-s3.sh "backups/{YEAR}/{MONTH}/mybackup-{TIMESTAMP}.sql.gz" /tmp/mybackup.sql.gz
#
# This script uploads a local file to an S3 bucket. The <s3_path> argument may contain
# placeholders, which will be replaced at runtime:
#   {DAY_OF_WEEK}   - Day of the week (1..7)
#   {DAY_OF_MONTH}  - Day of the month (01..31)
#   {YEAR}          - Year (e.g., 2024)
#   {MONTH}         - Month (01..12)
#   {TIMESTAMP}     - Timestamp (YYYYMMDD_HHMMSS)
#
# Required environment variables:
#   AWS_ACCESS_KEY_ID        - Your AWS access key ID
#   AWS_SECRET_ACCESS_KEY    - Your AWS secret access key
#   S3_BUCKET                - Target S3 bucket (without s3:// prefix)
#   AWS_ENDPOINT_URL         - S3 endpoint URL
#   [Optional] AWS_REGION    - AWS region (default: None)
#
# Output:
#   Uploads the file to s3://$S3_BUCKET/$FILENAME, where $FILENAME is determined from <s3_path> after placeholder substitution.

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <s3_path> <output_path>"
    exit 1
fi

S3_PATH="$1"
COMPRESSED_FILE="$2"

required_vars=("S3_BUCKET" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_ENDPOINT_URL" "AWS_REGION")
for var in "$${required_vars[@]}"; do
    if [ -z "$${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

# Validate input file exists
if [ ! -f "$COMPRESSED_FILE" ]; then
    echo "Error: File $COMPRESSED_FILE does not exist"
    exit 1
fi

DAY_OF_WEEK=$(date +%u)
DAY_OF_MONTH=$(date +%d)
YEAR=$(date +%Y)
MONTH=$(date +%m)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# We could do S3_FILE_NAME=$(eval echo "$S3_FILE_NAME"), but i do not want the security risk implications of evaluating
# an environment variable. This is probably enough to solve 90% of usecases. -RG
FILENAME=$(echo "$S3_PATH" | sed -e "s/{DAY_OF_WEEK}/$DAY_OF_WEEK/g" \
                                          -e "s/{DAY_OF_MONTH}/$DAY_OF_MONTH/g" \
                                          -e "s/{YEAR}/$YEAR/g" \
                                          -e "s/{MONTH}/$MONTH/g" \
                                          -e "s/{TIMESTAMP}/$TIMESTAMP/g")

S3_PATH="s3://$${S3_BUCKET}/$${FILENAME}"

echo "Uploading to S3..."
aws s3 cp "$COMPRESSED_FILE" "$S3_PATH" --region "$AWS_REGION" --endpoint-url "$AWS_ENDPOINT_URL"

if [ $? -ne 0 ]; then
    echo "Error: S3 upload failed"
    exit 1
fi

echo "Upload to S3 completed successfully"
echo "Backup available at: $S3_PATH"
