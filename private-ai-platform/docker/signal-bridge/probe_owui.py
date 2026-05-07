"""Diagnose: OWUI chat completions Roh-Antwort + Frame-Typen-Zaehler.

Laeuft im signal-bridge-Container (env vars sind dort gesetzt). Schreibt
die Roh-Antwort nach /tmp/owui_raw.txt (vollstaendig fuer manuelle Sicht)
und gibt einen JSON-Zaehler der Frame-Typen + Latenzen aus. Keine Secrets
im stdout.

CLI:
  probe_owui.py "<prompt>" [--kids id1,id2|none] [--model name] [--label tag]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import time

import aiohttp


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt", nargs="?", default="Sag bitte nur das Wort PING.")
    ap.add_argument("--kids", default=None,
                    help="comma-separated collection IDs, 'none' to disable, default: env OPENWEBUI_KNOWLEDGE_ID")
    ap.add_argument("--model", default=None, help="OWUI model id override")
    ap.add_argument("--label", default="", help="label to print with the result")
    args = ap.parse_args()

    base = os.environ["OPENWEBUI_BASE_URL"].rstrip("/")
    key = os.environ["OPENWEBUI_API_KEY"]
    model = args.model or os.environ["OPENWEBUI_MODEL"]
    if args.kids is None:
        kids = os.environ.get("OPENWEBUI_KNOWLEDGE_ID", "").strip()
    elif args.kids.lower() == "none":
        kids = ""
    else:
        kids = args.kids.strip()

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": args.prompt}],
        "stream": False,
    }
    if kids:
        payload["files"] = [
            {"type": "collection", "id": k.strip()}
            for k in kids.split(",")
            if k.strip()
        ]

    t0 = time.monotonic()
    ttfb: float | None = None
    async with aiohttp.ClientSession() as s:
        async with s.post(
            base + "/api/chat/completions",
            json=payload,
            headers={
                "Authorization": "Bearer " + key,
                "Content-Type": "application/json",
            },
            timeout=aiohttp.ClientTimeout(total=600),
        ) as r:
            ttfb = time.monotonic() - t0
            txt = await r.text()
            status = r.status
            ctype = r.headers.get("content-type", "")
    total = time.monotonic() - t0

    with open("/tmp/owui_raw.txt", "w", encoding="utf-8") as f:
        f.write(txt)

    types = {
        "sources": 0,
        "choices_delta_content": 0,
        "choices_message_content": 0,
        "choices_delta_tool_calls": 0,
        "choices_delta_reasoning": 0,
        "error": 0,
        "done": 0,
        "choices_other": 0,
        "non_data_lines": 0,
        "unknown_json": 0,
    }
    sample_other_keys: list[str] = []

    if txt.lstrip().startswith("data:"):
        for line in txt.splitlines():
            ls = line.strip()
            if not ls:
                continue
            if not ls.startswith("data:"):
                types["non_data_lines"] += 1
                continue
            p = ls[5:].strip()
            if p == "[DONE]":
                types["done"] += 1
                continue
            try:
                c = json.loads(p)
            except Exception:
                types["unknown_json"] += 1
                continue
            if not isinstance(c, dict):
                types["unknown_json"] += 1
                continue
            if c.get("error"):
                types["error"] += 1
            if "sources" in c:
                types["sources"] += 1
            ch = c.get("choices")
            if isinstance(ch, list) and ch:
                ch0 = ch[0] if isinstance(ch[0], dict) else {}
                d = ch0.get("delta") if isinstance(ch0.get("delta"), dict) else None
                m = ch0.get("message") if isinstance(ch0.get("message"), dict) else None
                consumed = False
                if d is not None:
                    if isinstance(d.get("content"), str) and d["content"]:
                        types["choices_delta_content"] += 1
                        consumed = True
                    elif d.get("tool_calls"):
                        types["choices_delta_tool_calls"] += 1
                        consumed = True
                    elif isinstance(d.get("reasoning_content"), str):
                        types["choices_delta_reasoning"] += 1
                        consumed = True
                if not consumed and m is not None:
                    if isinstance(m.get("content"), str) and m["content"]:
                        types["choices_message_content"] += 1
                        consumed = True
                if not consumed:
                    types["choices_other"] += 1
                    if len(sample_other_keys) < 5 and isinstance(ch0, dict):
                        sample_other_keys.append(
                            sorted(ch0.keys())
                            + (sorted(d.keys()) if isinstance(d, dict) else [])
                            + (sorted(m.keys()) if isinstance(m, dict) else [])
                        )

    print(
        json.dumps(
            {
                "label": args.label,
                "model": model,
                "kids": kids or None,
                "status": status,
                "content_type": ctype,
                "bytes": len(txt),
                "starts_with_data": txt.lstrip().startswith("data:"),
                "ttfb_s": round(ttfb or 0.0, 2),
                "total_s": round(total, 2),
                "frames": types,
                "sample_other_keys": sample_other_keys,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
