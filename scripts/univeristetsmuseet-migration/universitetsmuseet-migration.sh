#!/bin/bash

set -e

echo "MIGRATION HAS ALREADY BEEN PERFORMED ON 10.08.2026. This script is no longer needed, but keeping it here for reference."
exit 1

ONPREM_HOST="p1pubdocker01"

RAIL_CONTEXT="bgo1-prod-wc"
RAIL_NAMESPACE="adm-it-pub-universitetsmuseet"
RAIL_SVC_NAME="universitetsmuseet-php-fpm"

# Validate that the rail cluster is accessible.
echo "Validating that the rail cluster is accessible..."
if ! kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE exec svc/$RAIL_SVC_NAME -- echo 'Connected to rail cluster' > /dev/null 2>&1; then
    echo "Could not connect to rail cluster in namespace $RAIL_NAMESPACE. Ensure your .kubeconfig is set up correctly."
    exit 1
fi

echo "Starting dump..."

# Connects to the on-prem container, sources the environment variables, and dumps the database to the tmp directory.
echo "Dumping the database from on-prem..."
ssh -t $ONPREM_HOST 'sudo docker exec --user root:root umdrupal sh -c "source /.env && PGPASSWORD=\$DRUPAL_DATABASE_PASSWORD pg_dump -O -x -w -Fp -h \$DRUPAL_DATABASE_HOST -U \$DRUPAL_DATABASE_USERNAME \$DRUPAL_DATABASE_NAME" | gzip > /tmp/rail-dump.sql.gz'
# rsync the database dump from the on-prem container to the local machine. The dump is stored in the tmp directory.
mkdir -p ./tmp/files
rsync -ahzu --progress -t $ONPREM_HOST:/tmp/rail-dump.sql.gz ./tmp/rail-dump.sql.gz

# Rsync all files from the on-prem container to the local machine. The files are stored in the storage directory.
echo "Rsyncing files from on-prem to local machine..."
rsync -ahzu --progress -t $ONPREM_HOST:/local/docker/umdrupal/storage/ ./tmp/files

# Delete all files in the rail cluster and dump the database.
echo "Deleting all files in the rail cluster and dumping the database..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE exec svc/$RAIL_SVC_NAME -- sh -c "rm -rf /var/www/html/web/sites/default/files/*"
echo "Dropping the database..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE exec svc/$RAIL_SVC_NAME -- sh -c "drush sql:drop -y"

RAIL_POD_NAME=`kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE get pods -l app=$RAIL_SVC_NAME -o jsonpath='{.items[0].metadata.name}'`
# Restore the files from the local machine.
echo "Restoring files from local machine to rail cluster..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE cp ./tmp/files $RAIL_POD_NAME:/var/www/html/web/sites/default

# Copy the database dump from the local machine into the tmp directory in the container.
echo "Copying database from local machine to rail cluster tmp directory..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE cp ./tmp/rail-dump.sql.gz $RAIL_POD_NAME:/tmp/rail-dump.sql.gz

# Restore the database from the local machine.
echo "Restoring database from tmp directory..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE exec $RAIL_POD_NAME -- sh -c "drush sql:query --file=/tmp/rail-dump.sql.gz"

echo "Running drush deploy..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE exec $RAIL_POD_NAME -- sh -c "drush deploy"

echo "Disabling maintenance mode..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE exec svc/$RAIL_SVC_NAME -- sh -c "drush state:set system.maintenance_mode 0 && drush cr"

echo "Restarting Varnish..."
kubectl --context $RAIL_CONTEXT -n $RAIL_NAMESPACE rollout restart statefulset/varnish-cache

echo "Migration complete!"
