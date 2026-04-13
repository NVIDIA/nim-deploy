#!/bin/sh
# Run onboarding (or non-interactive setup) before the gateway when appropriate.
#
# OPENCLAW_SKIP_ONBOARD=1     — skip onboard/setup; go straight to the command
# OPENCLAW_CONFIG_PATH        — if set, used to detect existing config (see OpenClaw CLI)
# OPENCLAW_GATEWAY_PORT       — if set, passed as `openclaw gateway run --port …`
# OPENCLAW_GATEWAY_TOKEN      — if set, passed as `openclaw gateway run --token …`

set -eu

CONFIG="${OPENCLAW_CONFIG_PATH:-${HOME}/.openclaw/openclaw.json}"

openclaw doctor --fix >/dev/null 2>&1 || true

wants_gateway=false
if [ "$#" -ge 3 ] && [ "$1" = "openclaw" ] && [ "$2" = "gateway" ] && [ "$3" = "run" ]; then
  wants_gateway=true
fi

if [ "${OPENCLAW_SKIP_ONBOARD:-0}" != "1" ] && [ "$wants_gateway" = true ]; then
  if [ ! -f "$CONFIG" ]; then
    if [ -t 0 ]; then
      openclaw onboard
    else
      printf '%s\n' "openclaw: no config at ${CONFIG}; running openclaw setup (non-interactive)." \
        "For full interactive onboarding, use: docker run -it ..." >&2
      openclaw setup
    fi
  fi
fi

# Optional gateway listen/auth flags (e.g. Kubernetes + port-forward).
# Only applies when the command is exactly `openclaw gateway run` with no extra args.
if [ "$wants_gateway" = true ] && [ "$#" -eq 3 ]; then
  if [ -n "${OPENCLAW_GATEWAY_PORT:-}" ] || [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    set -- openclaw gateway run
    [ -n "${OPENCLAW_GATEWAY_PORT:-}" ] && set -- "$@" --port "$OPENCLAW_GATEWAY_PORT"
    [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ] && set -- "$@" --token "$OPENCLAW_GATEWAY_TOKEN"
  fi
fi

exec "$@"
