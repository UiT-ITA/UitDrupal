#!/bin/bash

# Downloads a file to disk from S3 only if it was modified today.

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <s3_path> <output_path>"
    exit 1
fi

S3_PATH="$1"
OUTPUT_PATH="$2"

# Check required env vars
required_vars=("AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "S3_BUCKET" "AWS_ENDPOINT_URL")
for var in "$${required_vars[@]}"; do
    if [ -z "$${!var}" ]; then
        echo "Error: Required environment variable $var is not set"
        exit 1
    fi
done

AWS_REGION="$${AWS_REGION:-None}"
AWS_ENDPOINT_URL="$${AWS_ENDPOINT_URL}"
SKIP_DATE_VALIDATION="$${SKIP_DATE_VALIDATION:-false}"

AWS_ARGS=(--region "$AWS_REGION")
AWS_ARGS+=(--endpoint-url "$AWS_ENDPOINT_URL")

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

TODAY=$(date -u +"%Y-%m-%d")

echo "Checking last file change s3://$S3_BUCKET/$FILENAME"
LAST_CHANGE=$(aws s3api head-object --bucket "$S3_BUCKET" --key "$FILENAME" --if-modified-since "$TODAY" --query LastModified --output text 2> /dev/null) || true

if [ -z "$LAST_CHANGE" ] && [ "$SKIP_DATE_VALIDATION" != "true" ]; then
    echo "No newer version found today (Not Modified); skipping to avoid restoring old files."
    exit 1
fi

echo "Downloading $FILENAME to $OUTPUT_PATH"
aws s3 cp "s3://$S3_BUCKET/$FILENAME" "$OUTPUT_PATH" "$${AWS_ARGS[@]}"

if [ $? -ne 0 ]; then
    echo "Error: Download failed"
    exit 1
fi

if [ ! -f "$OUTPUT_PATH" ]; then
    echo "Error: Output file $OUTPUT_PATH not found after download"
    exit 1
fi

echo "Download completed: $OUTPUT_PATH"
