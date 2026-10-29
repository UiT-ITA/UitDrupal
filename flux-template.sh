#!/bin/bash

set -e

if [ $# -ne 2 ] && [ $# -ne 3 ] && [ $# -ne 5 ]; then
  echo "Usage: $0 <environment> <service> [index] [type] [value]"
  echo "  type: 'kind' or 'name'"
  echo "  value: the kind or name to filter for"
  echo ""
  echo "Examples:"
  echo "  $0 bgo1-test profile"
  echo "  $0 bgo1-test profile 1"
  echo "  $0 bgo1-test profile 0 kind Ingress"
  echo "  $0 bgo1-test profile 1 name corviz"
  exit 1
fi

ENVIRONMENT="$1"
SERVICE="$2"
INDEX="$3"
KUSTOM_FILE="./${ENVIRONMENT}/RAIL/${SERVICE}.yaml"

# Optional filtering parameters
FILTER_TYPE=""
FILTER_VALUE=""
if [ $# -eq 5 ]; then
  FILTER_TYPE="$4"
  FILTER_VALUE="$5"
fi

# Extract kustomization name (grep approach for multi-doc YAML)
KUSTOM_NAME=$(awk '/^kind: Kustomization$/,/^---$|^$/ { if(/^  name:/) print $2 }' "$KUSTOM_FILE" | head -$INDEX | tail -1)
if [ -z "$KUSTOM_NAME" ]; then
  echo "Could not find Kustomization name in $KUSTOM_FILE"
  exit 1
fi

# Extract path (default to . if not set)
KUSTOM_PATH=$(awk '/^kind: Kustomization$/,/^---$|^$/ { if(/^  path:/) print $2 }' "$KUSTOM_FILE" | head -$INDEX | tail -1)
if [ -z "$KUSTOM_PATH" ]; then
  KUSTOM_PATH="."
fi

# Substitute ${rail_cluster} with ENVIRONMENT
KUSTOM_PATH=$(echo "$KUSTOM_PATH" | sed "s/\${rail_cluster}/$ENVIRONMENT/g")

echo "Environment: $ENVIRONMENT"
echo "Service: $SERVICE"
echo "Kustomization file: $KUSTOM_FILE"
echo "Kustomization name: $KUSTOM_NAME"
echo "Kustomization path: $KUSTOM_PATH"
if [ -n "$FILTER_TYPE" ]; then
  echo "Filter: $FILTER_TYPE = $FILTER_VALUE"
fi
echo ""

# Build the flux command and optionally filter with yq
FLUX_OUTPUT=$(flux build kustomization "$KUSTOM_NAME" \
  --local-sources "GitRepository/flux-system/adm-it-pub=." \
  --path "$KUSTOM_PATH" \
  --kustomization-file "$KUSTOM_FILE" \
  --dry-run)

# Apply filtering if specified
if [ -n "$FILTER_TYPE" ]; then
  case "$FILTER_TYPE" in
    "kind")
      echo "$FLUX_OUTPUT" | yq eval 'select(.kind == "'"$FILTER_VALUE"'")' -
      ;;
    "name")
      echo "$FLUX_OUTPUT" | yq eval 'select(.metadata.name == "'"$FILTER_VALUE"'")' -
      ;;
    *)
      echo "Error: Invalid filter type '$FILTER_TYPE'. Must be 'kind' or 'name'."
      exit 1
      ;;
  esac
else
  echo "$FLUX_OUTPUT"
fi
