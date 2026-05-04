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
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from typing import Any


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


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
#    default_base = os.environ.get("DYNAMO_BASE_URL", "http://52.142.237.163:8080")
    default_base = os.environ.get("DYNAMO_BASE_URL", "http://localhost:8000")
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
    p.add_argument(
        "--prompt",
        default="Reply with a single short sentence: what is 2+2?",
        help="User message content for the chat completion test",
    )
    p.add_argument(
        "--machine-result-line",
        action="store_true",
        help=(
            "Print a final DYNAMO_RESULT_JSON line (single-line JSON) for scripted parsing"
        ),
    )
    args = p.parse_args()
    base = _origin(args.base_url)
    v1 = f"{base}/v1"
    api_key = args.api_key

    result: dict[str, Any] = {
        "version": 1,
        "base_url": base,
        "model": args.model,
        "health": {},
        "chat": {},
        "exit": 0,
    }

    def finalize(exit_code: int) -> int:
        result["exit"] = exit_code
        if args.machine_result_line:
            print(f"DYNAMO_RESULT_JSON {json.dumps(result)}", flush=True)
        return exit_code

    print(f"Base: {base}")
    if args.skip_health:
        result["health"] = {"skipped": True}
    else:
        print("GET /health …", end=" ", flush=True)
        h_t0 = _utc_now_iso()
        h_t1 = time.perf_counter()
        ok = _try_health(base, args.timeout)
        h_elapsed = time.perf_counter() - h_t1
        h_t2 = _utc_now_iso()
        result["health"] = {
            "skipped": False,
            "ok": ok,
            "t_start": h_t0,
            "t_end": h_t2,
            "elapsed_s": round(h_elapsed, 6),
        }
        if ok:
            print(f"ok  [{h_t0} → {h_t2}, {h_elapsed:.3f}s]")
        else:
            print(
                f"failed or not available (continuing)  [{h_t0} → {h_t2}, {h_elapsed:.3f}s]"
            )

    print("POST /v1/chat/completions …", end=" ", flush=True)
    payload: dict[str, Any] = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": args.prompt,
            }
        ],
        "stream": False,
        "max_tokens": args.max_tokens,
    }
    llm_t0 = _utc_now_iso()
    llm_pc0 = time.perf_counter()
    try:
        c2, cdata = _json_request(
            "POST",
            f"{v1}/chat/completions",
            body=payload,
            api_key=api_key,
            timeout=args.timeout,
        )
    except urllib.error.HTTPError as e:
        llm_elapsed = time.perf_counter() - llm_pc0
        llm_t1 = _utc_now_iso()
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"HTTP {e.code}  [{llm_t0} → {llm_t1}, {llm_elapsed:.3f}s]")
        try:
            err_j = json.loads(err_body)
            err_body = json.dumps(err_j, indent=2)
        except json.JSONDecodeError:
            pass
        print(err_body[:4000], file=sys.stderr)
        result["chat"] = {
            "ok": False,
            "http": e.code,
            "t_start": llm_t0,
            "t_end": llm_t1,
            "elapsed_s": round(llm_elapsed, 6),
            "error": f"HTTPError {e.code}",
        }
        return finalize(1)
    except OSError as e:
        llm_elapsed = time.perf_counter() - llm_pc0
        llm_t1 = _utc_now_iso()
        print(
            f"error: {e}  [{llm_t0} → {llm_t1}, {llm_elapsed:.3f}s]",
            file=sys.stderr,
        )
        result["chat"] = {
            "ok": False,
            "http": None,
            "t_start": llm_t0,
            "t_end": llm_t1,
            "elapsed_s": round(llm_elapsed, 6),
            "error": str(e),
        }
        return finalize(1)

    llm_elapsed = time.perf_counter() - llm_pc0
    llm_t1 = _utc_now_iso()
    if c2 // 100 != 2:
        print(f"HTTP {c2}  [{llm_t0} → {llm_t1}, {llm_elapsed:.3f}s]")
        print(cdata, file=sys.stderr)
        result["chat"] = {
            "ok": False,
            "http": c2,
            "t_start": llm_t0,
            "t_end": llm_t1,
            "elapsed_s": round(llm_elapsed, 6),
            "error": f"HTTP status {c2}",
        }
        return finalize(1)
    print(f"ok ({c2})  [{llm_t0} → {llm_t1}, {llm_elapsed:.3f}s]")
    result["chat"] = {
        "ok": True,
        "http": c2,
        "t_start": llm_t0,
        "t_end": llm_t1,
        "elapsed_s": round(llm_elapsed, 6),
        "error": None,
    }
    if isinstance(cdata, dict) and cdata.get("choices"):
        msg = (cdata["choices"][0].get("message") or {}).get("content")
        if msg:
            print("assistant:", msg.strip()[:2000])
        else:
            print("response (truncated):", json.dumps(cdata)[:2000])
    else:
        print("response (truncated):", json.dumps(cdata)[:2000])

    print("All tests passed.")
    return finalize(0)


if __name__ == "__main__":
    raise SystemExit(main())
