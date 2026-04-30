#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
"""Smoke tests for a Dynamo OpenAI-compatible HTTP API (default port 8080)."""
#
# Checks GET /health and POST /v1/chat/completions. The frontend
# is usually 8000 in-cluster; use port-forward to 8080, e.g.:
#   kubectl port-forward -n dynamo-system svc/<release>-frontend 8080:8000
# Env: DYNAMO_BASE_URL (default http://127.0.0.1:8080), DYNAMO_MODEL, OPENAI_API_KEY

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any


def _origin(base: str) -> str:
    return base.rstrip("/")


def _http_get(url: str, timeout: float) -> tuple[int, str]:
    req = urllib.request.Request(
        url, method="GET", headers={"Accept": "application/json, */*"}
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        return resp.getcode(), raw


def _json_request(
    method: str,
    url: str,
    *,
    body: dict[str, Any] | None = None,
    api_key: str | None = None,
    timeout: float = 300.0,
) -> tuple[int, Any]:
    data: bytes | None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    else:
        data = None
    headers: dict[str, str] = {
        "Accept": "application/json",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        if not raw:
            return resp.getcode(), None
        return resp.getcode(), json.loads(raw)


def _try_health(base: str, timeout: float) -> bool:
    url = f"{_origin(base)}/health"
    try:
        code, _ = _http_get(url, timeout)
        if code // 100 == 2:
            return True
    except urllib.error.HTTPError as e:
        if e.code // 100 == 2:
            return True
    except OSError as e:
        print(f"health: unreachable ({e!s})", file=sys.stderr)
    return False


def main() -> int:
    default_base = os.environ.get("DYNAMO_BASE_URL", "http://52.142.237.163:8080")
    default_model = os.environ.get("DYNAMO_MODEL", "Qwen/Qwen3-32B")
    p = argparse.ArgumentParser(
        description=__doc__,
        epilog=(
            "Environment variables: DYNAMO_BASE_URL, DYNAMO_MODEL, OPENAI_API_KEY. "
            "If workers set DYN_HEALTH_CHECK_ENABLED=false, use --skip-health."
        ),
    )
    p.add_argument(
        "--base-url",
        default=default_base,
        help="HTTP origin for the frontend (no /v1), default: %(default)s",
    )
    p.add_argument(
        "--model",
        default=default_model,
        help="Served model id for /v1/chat/completions, default: %(default)s",
    )
    p.add_argument(
        "--api-key",
        default=os.environ.get("OPENAI_API_KEY"),
        help="Bearer token if required (or set OPENAI_API_KEY)",
    )
    p.add_argument(
        "--timeout",
        type=float,
        default=300.0,
        help="Request timeout in seconds, default: %(default)s",
    )
    p.add_argument(
        "--max-tokens",
        type=int,
        default=32,
        help="max_tokens in the chat test, default: %(default)s",
    )
    p.add_argument(
        "--skip-health",
        action="store_true",
        help="Do not call GET /health (some configs disable it)",
    )
    args = p.parse_args()
    base = _origin(args.base_url)
    v1 = f"{base}/v1"
    api_key = args.api_key

    print(f"Base: {base}")
    if not args.skip_health:
        print("GET /health …", end=" ", flush=True)
        if _try_health(base, args.timeout):
            print("ok")
        else:
            print("failed or not available (continuing)")

    print("POST /v1/chat/completions …", end=" ", flush=True)
    payload: dict[str, Any] = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": "Reply with a single short sentence: what is 2+2?",
            }
        ],
        "stream": False,
        "max_tokens": args.max_tokens,
    }
    try:
        c2, cdata = _json_request(
            "POST",
            f"{v1}/chat/completions",
            body=payload,
            api_key=api_key,
            timeout=args.timeout,
        )
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}")
        try:
            err_j = json.loads(err_body)
            err_body = json.dumps(err_j, indent=2)
        except json.JSONDecodeError:
            pass
        print(err_body[:4000], file=sys.stderr)
        return 1
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    if c2 // 100 != 2:
        print(f"HTTP {c2}")
        print(cdata, file=sys.stderr)
        return 1
    print(f"ok ({c2})")
    if isinstance(cdata, dict) and cdata.get("choices"):
        msg = (cdata["choices"][0].get("message") or {}).get("content")
        if msg:
            print("assistant:", msg.strip()[:2000])
        else:
            print("response (truncated):", json.dumps(cdata)[:2000])
    else:
        print("response (truncated):", json.dumps(cdata)[:2000])

    print("All tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
