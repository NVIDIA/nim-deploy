#!/usr/bin/env bash
# Deletes and recreates the NAT config profile eval Jobs (standard + trie).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete job nat-config-profile-eval nat-config-profile-with-trie-eval -n nat-dynamo --ignore-not-found
"${SCRIPT_DIR}/apply_config_profile_jobs.sh"
