#!/bin/bash

# See cmd_move for context on what is executed

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
DRY_RUN=false
ASSUME_YES=false
NO_GIT=false
NO_RECONCILE=false
NAMESPACE="adm-it-pub-w4"
KUSTOMIZATION_NAME="w4"
CONTEXT_SCOPE="prod"
RUN_TOKEN=""
WAIT_TOKEN_TIMEOUT=600
WAIT_TOKEN_INTERVAL=10
AUTO_WAIT_TOKEN=true
DEMOTION_TOKEN_RESULT=""
SYNC_TO_S3_JOB_NAMES=()

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "Error: must run inside a git repository."
  exit 1
fi

W4_BGO_FILE="$REPO_ROOT/bgo1-prod/RAIL/w4.yaml"
W4_OSL_FILE="$REPO_ROOT/osl1-prod/RAIL/w4.yaml"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [global_flags] <command> [command_flags]

Commands:
  move --from <bgo1|osl1> --to <bgo1|osl1> [--token <demotion_token>]

Global flags:
  --dry-run            Print commands without executing.
  --yes                Skip interactive confirmations.
  --no-git             Skip git add/commit/push.
  --no-reconcile       Skip forced Flux reconcile/watch.
  --namespace <name>   Kubernetes namespace. Default: adm-it-pub-w4
  --kustomization <n>  Flux kustomization name. Default: w4
  --context-scope <s>  Context scope: prod or test. Default: prod
  --wait-token-timeout <seconds>  Max wait for demotion token. Default: 600
  --wait-token-interval <seconds> Poll interval for demotion token. Default: 10
  --no-wait-token      Do not auto-wait for demotion token in move.
  -h, --help           Show this help.
EOF
}

log() {
  echo "[$SCRIPT_NAME] $*" >&2
}

die() {
  echo "Error: $*" >&2
  exit 1
}

run_cmd() {
  if [ "$DRY_RUN" = "true" ]; then
    log "$*"
    return 0
  fi
  "$@"
}

require_tools() {
  local tools=("git" "kubectl" "flux" "rg" "yq")
  local missing=()
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "Missing required tools: ${missing[*]}"
  fi
}

require_files() {
  [ -f "$W4_BGO_FILE" ] || die "Missing file: $W4_BGO_FILE"
  [ -f "$W4_OSL_FILE" ] || die "Missing file: $W4_OSL_FILE"
}

validate_region() {
  case "$1" in
    bgo1|osl1) ;;
    *) die "Invalid region '$1'. Expected bgo1 or osl1." ;;
  esac
}

other_region() {
  if [ "$1" = "bgo1" ]; then
    echo "osl1"
  else
    echo "bgo1"
  fi
}

region_file() {
  if [ "$1" = "bgo1" ]; then
    echo "$W4_BGO_FILE"
  else
    echo "$W4_OSL_FILE"
  fi
}

cluster_name() {
  echo "w4-$1-prod"
}

context_for_region() {
  local region="$1"
  validate_region "$region"
  case "$CONTEXT_SCOPE" in
    prod|test) ;;
    *) die "Invalid --context-scope '$CONTEXT_SCOPE'. Expected: prod or test." ;;
  esac
  echo "${region}-${CONTEXT_SCOPE}-wc"
}

ctx_args() {
  if [ -n "$1" ]; then
    echo "--context $1"
  fi
}

confirm() {
  local force=false
  local prompt="$1"
  local answer=""

  if [ "${2:-}" = "--force" ]; then
    force=true
  fi

  if [ "$ASSUME_YES" = "true" ] && [ "$force" = "false" ]; then
    return 0
  fi

  while true; do
    read -r -p "$prompt [y/n] " answer
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) die "Cancelled by user." ;;
      *) echo "Please answer y or n." >&2 ;;
    esac
  done
}

yq_set_substitute_key() {
  local file="$1"
  local key="$2"
  local value="$3"

  VALUE="$value" run_cmd yq eval -i \
    "(select(.kind == \"Kustomization\" and .spec.postBuild.substitute != null).spec.postBuild.substitute.${key}) = strenv(VALUE)" \
    "$file"
}

yq_get_substitute_key() {
  local file="$1"
  local key="$2"
  yq eval "select(.kind == \"Kustomization\" and .metadata.name == \"adm-it-pub-w4\").spec.postBuild.substitute.${key}" "$file"
}

git_commit_files() {
  local message="$1"
  shift
  local files=("$@")

  if [ "$NO_GIT" = "true" ]; then
    log "Skipping git add/commit/push (--no-git)."
    return 0
  fi

  if git diff --quiet -- "${files[@]}"; then
    log "No file changes detected for git commit."
    return 0
  fi

  run_cmd git add "${files[@]}"
  run_cmd git commit -m "$message"
  run_cmd git pull --rebase
  run_cmd git push
}

run_flux_reconcile() {
  local context="$1"
  local ctx
  ctx="$(ctx_args "$context")"

  if [ "$NO_RECONCILE" = "true" ]; then
    log "Skipping Flux reconcile/watch (--no-reconcile)."
    return 0
  fi

  if [ -n "$ctx" ]; then
    run_cmd flux --context "$context" reconcile source git flux-system -n flux-system
    run_cmd flux --context "$context" reconcile kustomization "$KUSTOMIZATION_NAME" -n flux-system --with-source
    run_cmd flux --context "$context" get kustomization "$KUSTOMIZATION_NAME" -n flux-system --watch
  else
    run_cmd flux reconcile source git flux-system -n flux-system
    run_cmd flux reconcile kustomization "$KUSTOMIZATION_NAME" -n flux-system --with-source
    run_cmd flux get kustomization "$KUSTOMIZATION_NAME" -n flux-system --watch
  fi
}

trigger_sync_to_s3_jobs() {
  local context="$1"
  local cronjobs cronjob_name job_name ts
  local required=(
    "w4-sync-assets-to-s3"
    "w4-sync-files-to-s3"
  )

  SYNC_TO_S3_JOB_NAMES=()

  if [ -n "$context" ]; then
    cronjobs="$(kubectl --context "$context" -n "$NAMESPACE" get cronjobs -o name 2>/dev/null || true)"
  else
    cronjobs="$(kubectl -n "$NAMESPACE" get cronjobs -o name 2>/dev/null || true)"
  fi

  for cronjob_name in "${required[@]}"; do
    printf '%s\n' "$cronjobs" | rg -q "^cronjob.batch/${cronjob_name}$" || die "Required CronJob missing in $NAMESPACE: $cronjob_name"
    ts="$(date +%s)"
    job_name="${cronjob_name:0:52}-${ts}"
    log "Triggering sync CronJob: $cronjob_name (job: $job_name)"
    if [ -n "$context" ]; then
      run_cmd kubectl --context "$context" -n "$NAMESPACE" create job --from="cronjob/${cronjob_name}" "$job_name"
    else
      run_cmd kubectl -n "$NAMESPACE" create job --from="cronjob/${cronjob_name}" "$job_name"
    fi
    SYNC_TO_S3_JOB_NAMES+=("$job_name")
    sleep 1
  done
}

wait_for_jobs_complete() {
  local context="$1"
  shift
  local jobs=("$@")

  [ "$DRY_RUN" = "false" ] || die "Cannot wait for Jobs in --dry-run mode."
  [ "${#jobs[@]}" -gt 0 ] || return 0

  log "Waiting for Jobs to complete: ${jobs[*]}"
  for j in "${jobs[@]}"; do
    local out rc
    if [ -n "$context" ]; then
      out="$(kubectl --context "$context" -n "$NAMESPACE" wait --for=condition=complete "job/${j}" --timeout="${WAIT_TOKEN_TIMEOUT}s" 2>&1)" || rc=$?
    else
      out="$(kubectl -n "$NAMESPACE" wait --for=condition=complete "job/${j}" --timeout="${WAIT_TOKEN_TIMEOUT}s" 2>&1)" || rc=$?
    fi

    rc="${rc:-0}"
    if [ "$rc" -eq 0 ]; then
      continue
    fi

    if printf '%s' "$out" | rg -q 'Error from server \(NotFound\): jobs\.batch'; then
      log "Job ${j} not found; assuming it already finished/was cleaned up."
      continue
    fi

    die "Waiting for job/${j} failed: ${out}"
  done
}

trigger_replicate_between_regions_jobs() {
  local context="$1"
  local cronjobs cronjob_name job_name ts
  local required=(
    "w4-replicate-assets-s3-between-regions"
    "w4-replicate-files-s3-between-regions"
  )

  if [ -n "$context" ]; then
    cronjobs="$(kubectl --context "$context" -n "$NAMESPACE" get cronjobs -o name 2>/dev/null || true)"
  else
    cronjobs="$(kubectl -n "$NAMESPACE" get cronjobs -o name 2>/dev/null || true)"
  fi

  for cronjob_name in "${required[@]}"; do
    printf '%s\n' "$cronjobs" | rg -q "^cronjob.batch/${cronjob_name}$" || die "Required CronJob missing in $NAMESPACE: $cronjob_name"
    ts="$(date +%s)"
    job_name="${cronjob_name:0:52}-${ts}"
    log "Triggering replicate CronJob: $cronjob_name (job: $job_name)"
    if [ -n "$context" ]; then
      run_cmd kubectl --context "$context" -n "$NAMESPACE" create job --from="cronjob/${cronjob_name}" "$job_name"
    else
      run_cmd kubectl -n "$NAMESPACE" create job --from="cronjob/${cronjob_name}" "$job_name"
    fi
    sleep 1
  done
}

extract_demotion_token() {
  local cluster_yaml="$1"
  local token=""

  token="$(printf '%s\n' "$cluster_yaml" | yq eval -r '.. | select(type == "!!map" and has("demotionToken")) | .demotionToken' - 2>/dev/null | rg -v '^null$' | rg -v '^$' | awk 'NF { print; exit }' || true)"
  if [ -z "$token" ]; then
    token="$(printf '%s\n' "$cluster_yaml" | rg -o 'demotionToken:\s*"?([^"[:space:]]+)"?' -r '$1' | awk 'NF { print; exit }' || true)"
  fi
  printf '%s' "$token"
}

get_cluster_yaml() {
  local context="$1"
  if [ -n "$context" ]; then
    run_cmd kubectl --context "$context" -n "$NAMESPACE" get cluster w4-db -o yaml
  else
    run_cmd kubectl -n "$NAMESPACE" get cluster w4-db -o yaml
  fi
}

wait_for_demotion_token() {
  local context="$1"
  local elapsed=0
  local yaml token
  DEMOTION_TOKEN_RESULT=""

  [ "$DRY_RUN" = "false" ] || die "Cannot auto-wait for demotion token in --dry-run mode."

  log "Waiting for demotion token (timeout=${WAIT_TOKEN_TIMEOUT}s interval=${WAIT_TOKEN_INTERVAL}s)..."
  while [ "$elapsed" -lt "$WAIT_TOKEN_TIMEOUT" ]; do
    yaml="$(get_cluster_yaml "$context" || true)"
    if [ -n "$yaml" ]; then
      token="$(extract_demotion_token "$yaml")"
      if [ -n "$token" ]; then
        log "Demotion token detected."
        DEMOTION_TOKEN_RESULT="$token"
        return 0
      fi
    fi
    sleep "$WAIT_TOKEN_INTERVAL"
    elapsed=$((elapsed + WAIT_TOKEN_INTERVAL))
    log "Still waiting... (${elapsed}s elapsed)"
  done

  return 1
}

wait_for_promotion_applied_and_healthy() {
  local context="$1"
  local expected_token="$2"
  local elapsed=0
  local yaml applied_token ready_status phase

  [ "$DRY_RUN" = "false" ] || die "Cannot verify promotion/health in --dry-run mode."

  log "Waiting for promotion token + healthy cluster state (timeout=${WAIT_TOKEN_TIMEOUT}s interval=${WAIT_TOKEN_INTERVAL}s)..."
  while [ "$elapsed" -lt "$WAIT_TOKEN_TIMEOUT" ]; do
    yaml="$(get_cluster_yaml "$context" || true)"
    if [ -n "$yaml" ]; then
      applied_token="$(printf '%s\n' "$yaml" | yq eval -r '.spec.replica.promotionToken // ""' - 2>/dev/null || true)"
      ready_status="$(printf '%s\n' "$yaml" | yq eval -r '.status.conditions[]? | select(.type == "Ready") | .status' - 2>/dev/null | awk 'NF { print; exit }' || true)"
      phase="$(printf '%s\n' "$yaml" | yq eval -r '.status.phase // ""' - 2>/dev/null || true)"
      if [ "$applied_token" = "$expected_token" ] && [ "$ready_status" = "True" ] && [[ "$phase" == *"healthy"* || "$phase" == *"Healthy"* ]]; then
        log "Promotion token applied and cluster healthy."
        return 0
      fi
    fi

    sleep "$WAIT_TOKEN_INTERVAL"
    elapsed=$((elapsed + WAIT_TOKEN_INTERVAL))
    log "Still waiting for promotion+health gate... (${elapsed}s elapsed)"
  done

  die "Timed out waiting for promotion token to apply and cluster to become healthy."
}

check_primary_matches_from() {
  local from="$1"
  local expected
  local bgo_primary
  local osl_primary

  expected="$(cluster_name "$from")"
  bgo_primary="$(yq_get_substitute_key "$W4_BGO_FILE" "primary_cluster")"
  osl_primary="$(yq_get_substitute_key "$W4_OSL_FILE" "primary_cluster")"

  [ "$bgo_primary" = "$expected" ] || die "bgo1 file primary_cluster=$bgo_primary, expected $expected"
  [ "$osl_primary" = "$expected" ] || die "osl1 file primary_cluster=$osl_primary, expected $expected"
}

cmd_status() {
  local region=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --region) region="$2"; shift 2 ;;
      *) die "Unknown status flag: $1" ;;
    esac
  done

  [ -n "$region" ] || die "status requires --region"
  validate_region "$region"

  local file primary source token is_replica sync repl ro
  file="$(region_file "$region")"
  primary="$(yq_get_substitute_key "$file" "primary_cluster")"
  source="$(yq_get_substitute_key "$file" "source_cluster")"
  token="$(yq_get_substitute_key "$file" "promotion_token")"
  is_replica="$(yq_get_substitute_key "$file" "is_replica")"
  sync="$(yq_get_substitute_key "$file" "suspend_sync_files")"
  repl="$(yq_get_substitute_key "$file" "suspend_replicate_files")"
  ro="$(yq_get_substitute_key "$file" "phpfpm_pvm_readonly")"

  echo "region=$region"
  echo "file=$file"
  echo "primary_cluster=$primary"
  echo "source_cluster=$source"
  echo "promotion_token=${token:-<empty>}"
  echo "is_replica=$is_replica"
  echo "suspend_sync_files=$sync"
  echo "suspend_replicate_files=$repl"
  echo "phpfpm_pvm_readonly=$ro"
}

cmd_prepare_demotion() {
  local from="" to=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="$2"; shift 2 ;;
      --to) to="$2"; shift 2 ;;
      *) die "Unknown prepare-demotion flag: $1" ;;
    esac
  done

  [ -n "$from" ] || die "prepare-demotion requires --from"
  [ -n "$to" ] || die "prepare-demotion requires --to"
  validate_region "$from"
  validate_region "$to"
  [ "$from" != "$to" ] || die "--from and --to must differ"

  check_primary_matches_from "$from"
  local from_file to_cluster from_context
  from_file="$(region_file "$from")"
  to_cluster="$(cluster_name "$to")"
  from_context="$(context_for_region "$from")"

  confirm "Prepare demotion by setting $from primary/source to $to_cluster?"
  yq_set_substitute_key "$from_file" "promotion_token" ""
  yq_set_substitute_key "$from_file" "primary_cluster" "$to_cluster"
  yq_set_substitute_key "$from_file" "source_cluster" "$to_cluster"
  yq_set_substitute_key "$from_file" "is_replica" "true"
  yq_set_substitute_key "$from_file" "mq_listen_replicas" "0"
  yq_set_substitute_key "$from_file" "phpfpm_pvm_readonly" "true"

  git_commit_files "w4 dr: prepare ${from} demotion toward ${to}" "$from_file"
  run_flux_reconcile "$from_context"

  log "Fetch demotion token (run in source region context):"
  log "kubectl --context $from_context -n $NAMESPACE get cluster w4-db -o yaml | rg -n 'demotion|token'"
}

cmd_promote() {
  local to="" token=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) to="$2"; shift 2 ;;
      --token) token="$2"; shift 2 ;;
      *) die "Unknown promote flag: $1" ;;
    esac
  done

  [ -n "$to" ] || die "promote requires --to"
  [ -n "$token" ] || die "promote requires --token"
  validate_region "$to"

  local to_file to_cluster to_context
  to_file="$(region_file "$to")"
  to_cluster="$(cluster_name "$to")"
  to_context="$(context_for_region "$to")"

  confirm "Promote $to with provided demotion token?"
  yq_set_substitute_key "$to_file" "promotion_token" "$token"
  yq_set_substitute_key "$to_file" "primary_cluster" "$to_cluster"
  yq_set_substitute_key "$to_file" "source_cluster" "$to_cluster"

  git_commit_files "w4 dr: promote ${to} with demotion token" "$to_file"
  run_flux_reconcile "$to_context"
}

cmd_flip_workload() {
  local primary="" replica
  while [ $# -gt 0 ]; do
    case "$1" in
      --primary) primary="$2"; shift 2 ;;
      *) die "Unknown flip-workload flag: $1" ;;
    esac
  done

  [ -n "$primary" ] || die "flip-workload requires --primary"
  validate_region "$primary"
  replica="$(other_region "$primary")"

  local primary_file replica_file primary_context
  primary_file="$(region_file "$primary")"
  replica_file="$(region_file "$replica")"
  primary_context="$(context_for_region "$primary")"

  confirm "Flip workload flags: $primary active, $replica replica-safe?"
  yq_set_substitute_key "$primary_file" "is_replica" "false"
  yq_set_substitute_key "$primary_file" "mq_listen_replicas" "1"
  yq_set_substitute_key "$primary_file" "suspend_replicate_files" "true"
  yq_set_substitute_key "$primary_file" "suspend_sync_files" "false"
  yq_set_substitute_key "$primary_file" "phpfpm_pvm_readonly" "false"

  yq_set_substitute_key "$replica_file" "is_replica" "true"
  yq_set_substitute_key "$replica_file" "mq_listen_replicas" "0"
  yq_set_substitute_key "$replica_file" "suspend_replicate_files" "false"
  yq_set_substitute_key "$replica_file" "suspend_sync_files" "true"
  yq_set_substitute_key "$replica_file" "phpfpm_pvm_readonly" "true"

  git_commit_files "w4 dr: switch active workload flags to ${primary}" "$primary_file" "$replica_file"

  run_flux_reconcile "$primary_context"
  run_cmd kubectl --context "$primary_context" -n "$NAMESPACE" get cronjobs
}

cmd_move() {
  local from="" to="" token=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from) from="$2"; shift 2 ;;
      --to) to="$2"; shift 2 ;;
      --token) token="$2"; shift 2 ;;
      *) die "Unknown move flag: $1" ;;
    esac
  done

  # Simple validation
  [ -n "$from" ] || die "move requires --from"
  [ -n "$to" ] || die "move requires --to"
  validate_region "$from"
  validate_region "$to"
  [ "$from" != "$to" ] || die "--from and --to must differ"

  # Trigger demotion in $from + mark as replica / read only
  cmd_prepare_demotion --from "$from" --to "$to"

  # Validate that we got the token
  if [ -z "$token" ] && [ -n "$RUN_TOKEN" ]; then
    token="$RUN_TOKEN"
  fi

  if [ -z "$token" ] && [ "$AUTO_WAIT_TOKEN" = "true" ]; then
    if wait_for_demotion_token "$(context_for_region "$from")"; then
      token="$DEMOTION_TOKEN_RESULT"
    fi
  fi

  if [ -z "$token" ]; then
    if [ "$ASSUME_YES" = "true" ]; then
      die "move with --yes requires a token. Provide --token, or allow auto-wait to find it."
    fi
    read -r -p "Paste demotion token from previous step: " token
    [ -n "$token" ] || die "No token provided."
  fi

  # Sync files locally in $from
  trigger_sync_to_s3_jobs "$(context_for_region "$from")"
  wait_for_jobs_complete "$(context_for_region "$from")" "${SYNC_TO_S3_JOB_NAMES[@]}"
  trigger_replicate_between_regions_jobs "$(context_for_region "$to")"

  # Promote $to as new replcia
  cmd_promote --to "$to" --token "$token"
  wait_for_promotion_applied_and_healthy "$(context_for_region "$to")" "$token"

  # Mark $to as ready for cron-jobs / rabbitmq messages
  cmd_flip_workload --primary "$to"
}

main() {
  require_tools
  require_files

  local command=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=true; shift ;;
      --yes) ASSUME_YES=true; shift ;;
      --no-git) NO_GIT=true; shift ;;
      --no-reconcile) NO_RECONCILE=true; shift ;;
      --namespace) NAMESPACE="$2"; shift 2 ;;
      --kustomization) KUSTOMIZATION_NAME="$2"; shift 2 ;;
      --context-scope) CONTEXT_SCOPE="$2"; shift 2 ;;
      --token) RUN_TOKEN="$2"; shift 2 ;;
      --wait-token-timeout) WAIT_TOKEN_TIMEOUT="$2"; shift 2 ;;
      --wait-token-interval) WAIT_TOKEN_INTERVAL="$2"; shift 2 ;;
      --no-wait-token) AUTO_WAIT_TOKEN=false; shift ;;
      -h|--help|help)
        usage
        exit 0
        ;;
      *)
        command="$1"
        shift
        break
        ;;
    esac
  done

  [ -n "$command" ] || { usage; exit 1; }
  [[ "$WAIT_TOKEN_TIMEOUT" =~ ^[0-9]+$ ]] || die "--wait-token-timeout must be an integer >= 0"
  [[ "$WAIT_TOKEN_INTERVAL" =~ ^[0-9]+$ ]] || die "--wait-token-interval must be an integer >= 0"
  [ "$WAIT_TOKEN_INTERVAL" -gt 0 ] || die "--wait-token-interval must be > 0"

  case "$command" in
    move) cmd_move "$@" ;;
    *) die "Unknown command: $command" ;;
  esac
}

main "$@"
