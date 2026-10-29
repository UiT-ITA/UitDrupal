#!/usr/bin/env bash
set -euo pipefail

cluster="${1:-}"
service="${2:-}"

if [[ -z "${cluster}" || -z "${service}" ]]; then
  echo "Usage: $0 <cluster> <service>"
  echo "Example: $0 bgo1-prod w4"
  exit 2
fi

case "${cluster}" in
  bgo1-prod|bgo1-test|osl1-prod|osl1-test) ;;
  *)
    echo "Invalid cluster: ${cluster}"
    exit 2
    ;;
esac

kustomization="adm-it-pub-${service}"
kubecontext="${cluster}-wc"

exec flux --context "${kubecontext}" -n adm-it-pub reconcile kustomization "${kustomization}" --with-source