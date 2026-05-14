#!/usr/bin/env bash
# Apply NAT config profile eval Job(s). Job name is JOB_BASE plus the current date/time.
# Requires gettext envsubst (e.g. brew install gettext).
#
# Env vars below are substituted into the manifest as nat eval CLI-style arguments (same defaults as restart_profile_jobs.sh).
#
# Usage:
#   apply_config_profile_jobs.sh               — baseline + with_trie (same timestamp)
#   apply_config_profile_jobs.sh baseline      — config_profile.yml only
#   apply_config_profile_jobs.sh with_trie     — config_with_trie.yml only (alias: with_tree)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DYNAMO_OPENAI_BASE_URL="${DYNAMO_OPENAI_BASE_URL:-http://agg-8xtp2-frontend.dynamo-cloud.svc.cluster.local:8000/v1}"
export NAT_EVAL_REPS="${NAT_EVAL_REPS:-400}"
export NAT_PERF_DEBUG="${NAT_PERF_DEBUG:-1}"

STAMP="$(date +%Y%m%d-%H%M%S)"

SUBST_VARS='${JOB_NAME}${NAT_CONFIG_BASENAME}${JOB_BASE}${DYNAMO_OPENAI_BASE_URL}${NAT_EVAL_REPS}${NAT_PERF_DEBUG}'

apply_profile_job() {
  local job_base="$1"
  local config_basename="$2"
  export JOB_BASE="$job_base"
  export JOB_NAME="${job_base}-${STAMP}"
  export NAT_CONFIG_BASENAME="$config_basename"
  envsubst "${SUBST_VARS}" <"${SCRIPT_DIR}/config_profile_job.yaml" | kubectl apply -f -
  echo "Applied job: ${JOB_NAME}"
}

usage() {
  echo "Usage: $0 [baseline | with_trie]" >&2
  echo "  (no args)   apply both jobs with the same timestamp" >&2
  echo "  baseline      nat-config-profile-eval + config_profile.yml" >&2
  echo "  with_trie     nat-config-profile-with-trie-eval + config_with_trie.yml" >&2
}

main() {
  case "${1:-}" in
    "")
      apply_profile_job nat-config-profile-eval config_profile.yml
      apply_profile_job nat-config-profile-with-trie-eval config_with_trie.yml
      ;;
    baseline)
      apply_profile_job nat-config-profile-eval config_profile.yml
      ;;
    with_trie | with_tree)
      apply_profile_job nat-config-profile-with-trie-eval config_with_trie.yml
      ;;
    -h | --help | help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
