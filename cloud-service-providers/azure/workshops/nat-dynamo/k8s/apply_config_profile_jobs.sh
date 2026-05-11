#!/usr/bin/env bash
# Apply NAT config profile eval Jobs (baseline config_profile.yml + config_with_trie.yml).
# Requires gettext envsubst (e.g. brew install gettext).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apply_profile_job() {
  local job_name="$1"
  local config_basename="$2"
  export JOB_NAME="$job_name"
  export NAT_CONFIG_BASENAME="$config_basename"
  envsubst '${JOB_NAME}${NAT_CONFIG_BASENAME}' <"${SCRIPT_DIR}/config_profile_job.yaml" | kubectl apply -f -
}

apply_profile_job nat-config-profile-eval config_profile.yml
apply_profile_job nat-config-profile-with-trie-eval config_with_trie.yml
