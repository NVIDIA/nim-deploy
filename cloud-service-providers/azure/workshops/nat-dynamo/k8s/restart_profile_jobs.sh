#!/usr/bin/env bash
# Applies a new timestamped profile-eval Job (does not delete existing Jobs).
# Defaults below are expanded into the Job manifest as CLI-style settings (see config_profile_job.yaml).
# Override any value for this shell before running, e.g. NAT_EVAL_REPS=100 ./restart_profile_jobs.sh baseline
#
# Usage:
#   restart_profile_jobs.sh baseline    — config_profile.yml (nat-config-profile-eval)
#   restart_profile_jobs.sh with_trie   — config_with_trie.yml (alias: with_tree)
#
# With no arguments, applies both variants (same as apply_config_profile_jobs.sh).
set -euo pipefail

export DYNAMO_OPENAI_BASE_URL="${DYNAMO_OPENAI_BASE_URL:-http://agg-8xtp2-frontend.dynamo-cloud.svc.cluster.local:8000/v1}"
export NAT_EVAL_REPS="${NAT_EVAL_REPS:-100}"
export NAT_PERF_DEBUG="${NAT_PERF_DEBUG:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/apply_config_profile_jobs.sh" "$@"
