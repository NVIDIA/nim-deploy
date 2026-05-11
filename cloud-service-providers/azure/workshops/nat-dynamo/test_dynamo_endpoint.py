#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
"""Smoke tests for a Dynamo OpenAI-compatible HTTP API (default port 8080)."""
#
# Checks GET /health and POST /v1/chat/completions (streaming SSE). The frontend
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


def _first_content_delta(chunk: dict[str, Any]) -> str | None:
    choices = chunk.get("choices") or []
    if not choices:
        return None
    delta = (choices[0] or {}).get("delta") or {}
    content = delta.get("content")
    if isinstance(content, str) and content:
        return content
    reasoning = delta.get("reasoning_content")
    if isinstance(reasoning, str) and reasoning:
        return reasoning
    return None


def _finish_reason(chunk: dict[str, Any]) -> str | None:
    choices = chunk.get("choices") or []
    if not choices:
        return None
    fr = (choices[0] or {}).get("finish_reason")
    return str(fr) if fr is not None else None


def _usage(chunk: dict[str, Any]) -> tuple[int | None, int | None, int | None]:
    u = chunk.get("usage")
    if not isinstance(u, dict):
        return None, None, None
    pt = u.get("prompt_tokens")
    ct = u.get("completion_tokens")
    tt = u.get("total_tokens")
    return (
        int(pt) if isinstance(pt, int) else None,
        int(ct) if isinstance(ct, int) else None,
        int(tt) if isinstance(tt, int) else None,
    )


def _stream_chat_completion(
    *,
    url: str,
    body: dict[str, Any],
    api_key: str | None,
    timeout: float,
) -> dict[str, Any]:
    """POST chat/completions with stream:true; parse SSE and aggregate text deltas."""
    data = json.dumps(body).encode("utf-8")
    headers: dict[str, str] = {
        "Accept": "text/event-stream",
        "Content-Type": "application/json",
    }
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"

    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    t0 = time.perf_counter()
    ttft: float | None = None
    chunks = 0
    parts: list[str] = []
    finish_reason: str | None = None
    ptokens: int | None = None
    ctokens: int | None = None
    ttokens: int | None = None

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            code = resp.getcode()
            if code // 100 != 2:
                raw = resp.read().decode("utf-8", errors="replace")
                return {
                    "ok": False,
                    "http": code,
                    "error": raw[:4000],
                    "content": "",
                    "ttft_s": None,
                    "elapsed_s": time.perf_counter() - t0,
                    "chunks": 0,
                    "finish_reason": None,
                    "prompt_tokens": None,
                    "completion_tokens": None,
                    "total_tokens": None,
                }

            buffer = b""
            while True:
                chunk_bytes = resp.read(8192)
                if not chunk_bytes:
                    break
                buffer += chunk_bytes
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line_s = line.decode("utf-8", errors="replace").strip()
                    if not line_s or line_s.startswith(":"):
                        continue
                    if not line_s.startswith("data:"):
                        continue
                    payload = line_s[5:].strip()
                    if payload == "[DONE]":
                        return {
                            "ok": True,
                            "http": code,
                            "error": None,
                            "content": "".join(parts),
                            "ttft_s": ttft,
                            "elapsed_s": time.perf_counter() - t0,
                            "chunks": chunks,
                            "finish_reason": finish_reason,
                            "prompt_tokens": ptokens,
                            "completion_tokens": ctokens,
                            "total_tokens": ttokens,
                        }
                    try:
                        obj = json.loads(payload)
                    except json.JSONDecodeError:
                        continue
                    chunks += 1
                    piece = _first_content_delta(obj)
                    if piece is not None:
                        if ttft is None:
                            ttft = time.perf_counter() - t0
                        parts.append(piece)
                    fr = _finish_reason(obj)
                    if fr:
                        finish_reason = fr
                    u_pt, u_ct, u_tt = _usage(obj)
                    if u_pt is not None:
                        ptokens = u_pt
                    if u_ct is not None:
                        ctokens = u_ct
                    if u_tt is not None:
                        ttokens = u_tt

            return {
                "ok": False,
                "http": code,
                "error": "stream ended without [DONE]",
                "content": "".join(parts),
                "ttft_s": ttft,
                "elapsed_s": time.perf_counter() - t0,
                "chunks": chunks,
                "finish_reason": finish_reason,
                "prompt_tokens": ptokens,
                "completion_tokens": ctokens,
                "total_tokens": ttokens,
            }
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        return {
            "ok": False,
            "http": e.code,
            "error": err_body[:4000],
            "content": "".join(parts),
            "ttft_s": ttft,
            "elapsed_s": time.perf_counter() - t0,
            "chunks": chunks,
            "finish_reason": finish_reason,
            "prompt_tokens": ptokens,
            "completion_tokens": ctokens,
            "total_tokens": ttokens,
        }
    except OSError as e:
        return {
            "ok": False,
            "http": None,
            "error": str(e),
            "content": "".join(parts),
            "ttft_s": ttft,
            "elapsed_s": time.perf_counter() - t0,
            "chunks": chunks,
            "finish_reason": finish_reason,
            "prompt_tokens": ptokens,
            "completion_tokens": ctokens,
            "total_tokens": ttokens,
        }


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
        default="I was billed twice for my subscription last month—can I receive a refund for the extra charge?",
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

    print("Prompt:")
    print(args.prompt)
    print("POST /v1/chat/completions (stream) …", end=" ", flush=True)
    payload: dict[str, Any] = {
        "model": args.model,
        "messages": [
            {
                "role": "user",
                "content": args.prompt,
            }
        ],
        "stream": True,
        "max_tokens": args.max_tokens,
        "stream_options": {"include_usage": True},
    }
    llm_t0 = _utc_now_iso()
    llm_pc0 = time.perf_counter()
    sm = _stream_chat_completion(
        url=f"{v1}/chat/completions",
        body=payload,
        api_key=api_key,
        timeout=args.timeout,
    )
    llm_elapsed = sm["elapsed_s"]
    llm_t1 = _utc_now_iso()

    if not sm["ok"]:
        print(f"fail  [{llm_t0} → {llm_t1}, {llm_elapsed:.3f}s]")
        err_msg = sm["error"] or "unknown error"
        if isinstance(err_msg, str) and err_msg.strip().startswith("{"):
            try:
                err_j = json.loads(err_msg)
                err_msg = json.dumps(err_j, indent=2)
            except json.JSONDecodeError:
                pass
        print(err_msg[:4000], file=sys.stderr)
        result["chat"] = {
            "ok": False,
            "http": sm["http"],
            "t_start": llm_t0,
            "t_end": llm_t1,
            "elapsed_s": round(llm_elapsed, 6),
            "error": sm["error"],
            "streaming": True,
            "ttft_s": round(sm["ttft_s"], 6) if sm["ttft_s"] is not None else None,
            "chunks": sm["chunks"],
        }
        return finalize(1)

    http_code = sm["http"]
    assert http_code is not None
    print(f"ok ({http_code})  [{llm_t0} → {llm_t1}, {llm_elapsed:.3f}s]")
    chat_out: dict[str, Any] = {
        "ok": True,
        "http": http_code,
        "t_start": llm_t0,
        "t_end": llm_t1,
        "elapsed_s": round(llm_elapsed, 6),
        "error": None,
        "streaming": True,
        "ttft_s": round(sm["ttft_s"], 6) if sm["ttft_s"] is not None else None,
        "chunks": sm["chunks"],
        "finish_reason": sm["finish_reason"],
        "prompt_tokens": sm["prompt_tokens"],
        "completion_tokens": sm["completion_tokens"],
        "total_tokens": sm["total_tokens"],
    }
    result["chat"] = chat_out

    msg = sm["content"].strip()
    if msg:
        print("assistant:", msg[:2000])
    else:
        print(
            "assistant: (no text deltas; tool-only or empty stream)",
            file=sys.stderr,
        )

    print("All tests passed.")
    return finalize(0)


if __name__ == "__main__":
    raise SystemExit(main())
