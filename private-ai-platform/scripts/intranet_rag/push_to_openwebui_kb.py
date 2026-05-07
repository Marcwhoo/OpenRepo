#!/usr/bin/env python3
"""
Liest exportierte .txt (z. B. INTRANET_OUTPUT_DIR), laedt sie in Open WebUI
(API: POST /api/v1/files/, warten, POST /api/v1/knowledge/{id}/file/add) und
haelt einen State (SHA-256) fuer inkrementelle Updates. Bei Inhaltsswechsel
wird der alte KB-Eintrag entfernt (file/remove) bevor der neue hochkommt.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import sys
import time
from typing import Any

import requests
import urllib3
from urllib3.util.retry import Retry
from requests.adapters import HTTPAdapter

from job_debug_log import install_debug_file

LOG = logging.getLogger("push_openwebui_kb")

STATE_VERSION = 1


def _env(name: str, default: str | None = None) -> str:
    v = os.environ.get(name, "").strip()
    if v:
        return v
    if default is not None:
        return default
    raise SystemExit(f"missing required env: {name}")


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    return int(raw, 10)


def _env_float(name: str, default: float) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    return float(raw)


def _env_bool01(name: str, default: bool) -> bool:
    raw = (os.environ.get(name) or "").strip().lower()
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off"):
        return False
    return default


def _mount_retries(session: requests.Session) -> None:
    retries = _env_int("OPENWEBUI_API_RETRIES", 3)
    if retries <= 0:
        return
    retry = Retry(
        total=retries,
        connect=retries,
        read=retries,
        status=retries,
        backoff_factor=_env_float("OPENWEBUI_API_BACKOFF", 1.0),
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=frozenset({"GET", "POST"}),
        respect_retry_after_header=True,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://", adapter)


def _file_sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _load_state(path: str) -> dict[str, Any]:
    if not os.path.isfile(path):
        return {"version": STATE_VERSION, "by_rel": {}}
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if int(data.get("version", 1)) != STATE_VERSION:
        data = {"version": STATE_VERSION, "by_rel": data.get("by_rel", data)}
    data.setdefault("by_rel", {})
    return data


def _save_state(path: str, data: dict[str, Any]) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=0)
    os.replace(tmp, path)


def _wait_processing(
    session: requests.Session, base: str, file_id: str, timeout: int, interval: float
) -> None:
    url = f"{base.rstrip('/')}/api/v1/files/{file_id}/process/status"
    t0 = time.time()
    while time.time() - t0 < timeout:
        r = session.get(url, timeout=60)
        r.raise_for_status()
        body = r.json()
        status = body.get("status")
        if status == "completed":
            return
        if status == "failed":
            err = body.get("error", body)
            raise RuntimeError(f"file processing failed: {err}")
        time.sleep(interval)
    raise TimeoutError(f"file {file_id} not processed after {timeout}s")


def _upload_file(session: requests.Session, base: str, path: str) -> str:
    url = f"{base.rstrip('/')}/api/v1/files/"
    name = os.path.basename(path)
    with open(path, "rb") as f:
        r = session.post(
            url,
            files={"file": (name, f, "text/plain")},
            params={"process": "true", "process_in_background": "true"},
            timeout=300,
        )
    r.raise_for_status()
    data = r.json()
    fid = data.get("id")
    if not fid:
        raise RuntimeError(f"upload: no id in response: {data!r}")
    return str(fid)


def _kb_add(session: requests.Session, base: str, kid: str, file_id: str) -> None:
    url = f"{base.rstrip('/')}/api/v1/knowledge/{kid}/file/add"
    add_timeout = _env_int("OPENWEBUI_KB_ADD_TIMEOUT", 900)
    r = session.post(url, json={"file_id": file_id}, timeout=add_timeout)
    r.raise_for_status()


def _kb_remove(session: requests.Session, base: str, kid: str, file_id: str) -> None:
    url = f"{base.rstrip('/')}/api/v1/knowledge/{kid}/file/remove"
    r = session.post(
        url,
        params={"delete_file": "true"},
        json={"file_id": file_id},
        timeout=120,
    )
    r.raise_for_status()


def _preflight(session: requests.Session, base: str, kid: str) -> None:
    """Fail once for global TLS/auth/base-url/knowledge problems before looping over files."""
    url = f"{base.rstrip('/')}/api/v1/knowledge/{kid}"
    r = session.get(url, timeout=60)
    r.raise_for_status()


def _is_internal_txt(abs_path: str, root: str, debug_log: str) -> bool:
    rel = os.path.relpath(abs_path, root).replace("\\", "/")
    name = os.path.basename(abs_path).lower()
    if rel.startswith(".") or name.startswith("."):
        return True
    if name in {"debug.txt"}:
        return True
    if name.startswith((".owui-", ".ingest-")):
        return True
    if debug_log and os.path.abspath(abs_path) == os.path.abspath(debug_log):
        return True
    return False


def _collect_txt(root: str) -> list[str]:
    out: list[str] = []
    debug_log = (os.environ.get("INTRANET_DEBUG_LOG") or "").strip()
    if debug_log == "0":
        debug_log = ""
    abs_root = os.path.abspath(root)
    for dirpath, dirnames, filenames in os.walk(abs_root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in filenames:
            if not fn.lower().endswith(".txt"):
                continue
            if fn.startswith("."):
                continue
            abs_path = os.path.join(dirpath, fn)
            if _is_internal_txt(abs_path, abs_root, debug_log):
                continue
            out.append(abs_path)
    out.sort()
    return out


def _finish_pending(
    session: requests.Session,
    base: str,
    kid: str,
    state_path: str,
    state: dict[str, Any],
    rel: str,
    timeout: int,
    interval: float,
) -> bool:
    by_rel: dict[str, dict] = state["by_rel"]
    item = by_rel.get(rel) or {}
    fid = item.get("file_id")
    if not fid:
        return False
    status = item.get("status", "complete")
    if status == "complete":
        return True
    if status == "uploaded":
        _wait_processing(session, base, str(fid), timeout, interval)
        item["status"] = "processed"
        by_rel[rel] = item
        _save_state(state_path, state)
    if item.get("status") == "processed":
        _kb_add(session, base, kid, str(fid))
        old_file_id = item.pop("old_file_id", None)
        if old_file_id and old_file_id != fid:
            try:
                _kb_remove(session, base, kid, str(old_file_id))
            except requests.HTTPError as e:
                LOG.warning("remove old after pending add (continuing) %s: %s", rel, e)
        item["status"] = "complete"
        by_rel[rel] = item
        _save_state(state_path, state)
    return item.get("status") == "complete"


def main() -> int:
    ap = argparse.ArgumentParser(description="Intranet-RAG .txt in Open WebUI-KB (API).")
    ap.add_argument(
        "--dry-run", action="store_true", help="Nur anzeigen, nichts hochladen/loeschen."
    )
    ap.add_argument(
        "--prune",
        action="store_true",
        help="Eintrag entfernen, die nicht mehr auf der Platte sind (laut State).",
    )
    ap.add_argument(
        "--reset-state",
        action="store_true",
        help="State-Datei loeschen und beenden; KB bitte in OWUI leeren (sonst Duplikate).",
    )
    ap.add_argument(
        "--knowledge-id",
        default="",
        help="UUID der Ziel-Knowledge-Base (ueberschreibt OPENWEBUI_KNOWLEDGE_ID / OPENWEBUI_KNOWLEDGE_ID_DIRECTORY).",
    )
    ap.add_argument(
        "--sync-dir",
        default="",
        help="Verzeichnis mit .txt fuer diesen Push (ueberschreibt OPENWEBUI_SYNC_DIR / INTRANET_OUTPUT_DIR).",
    )
    ap.add_argument(
        "--state-file",
        default="",
        help="Pfad zur State-JSON (ueberschreibt OPENWEBUI_KB_STATE_FILE).",
    )
    args = ap.parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
    started_at = time.monotonic()
    counters = {"skip": 0, "upload": 0, "errors": 0}

    base = _env("OPENWEBUI_BASE_URL")
    if not (base.startswith("http://") or base.startswith("https://")):
        raise SystemExit("OPENWEBUI_BASE_URL must be http or https, no path")
    # remove trailing /api
    if base.rstrip("/").endswith("/api"):
        base = base.rsplit("/api", 1)[0]
    key = _env("OPENWEBUI_API_KEY")
    kid = (args.knowledge_id or "").strip()
    if not kid:
        kid = (os.environ.get("OPENWEBUI_KNOWLEDGE_ID") or "").strip()
    if not kid:
        kid = (os.environ.get("OPENWEBUI_KNOWLEDGE_ID_DIRECTORY") or "").strip()
    if not kid:
        raise SystemExit(
            "set OPENWEBUI_KNOWLEDGE_ID or OPENWEBUI_KNOWLEDGE_ID_DIRECTORY or pass --knowledge-id"
        )
    sync_dir = (args.sync_dir or "").strip()
    if not sync_dir:
        sync_dir = _env("OPENWEBUI_SYNC_DIR", _env("INTRANET_OUTPUT_DIR", ""))
    if not sync_dir:
        raise SystemExit("set OPENWEBUI_SYNC_DIR or INTRANET_OUTPUT_DIR or pass --sync-dir")
    if not os.path.isdir(sync_dir):
        raise SystemExit(f"sync dir not found: {sync_dir}")
    install_debug_file(sync_dir, truncate=False, job_label="push_to_openwebui_kb")
    state_path = (args.state_file or "").strip()
    if not state_path:
        state_path = _env("OPENWEBUI_KB_STATE_FILE", os.path.join(sync_dir, ".owui-kb-state.json"))
    timeout = _env_int("OPENWEBUI_PROCESS_TIMEOUT", 600)
    interval = _env_float("OPENWEBUI_POLL_INTERVAL", 2.0)
    post_delay = _env_float("OPENWEBUI_API_DELAY", 0.0)
    max_file_size = _env_int("OPENWEBUI_MAX_FILE_SIZE", 2 * 1024 * 1024)

    if args.reset_state:
        if args.dry_run:
            LOG.info("dry-run: would remove state %s", state_path)
        elif os.path.isfile(state_path):
            os.remove(state_path)
            LOG.info("removed %s", state_path)
        else:
            LOG.info("no state at %s", state_path)
        return 0

    state = _load_state(state_path)
    by_rel: dict[str, dict] = state["by_rel"]

    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
        }
    )
    _mount_retries(session)
    # Fuer internes TLS nach Moeglichkeit ein CA-Bundle nutzen. Wenn das nicht geht,
    # kann OPENWEBUI_INSECURE_TLS=1 die Pruefung explizit abschalten.
    ca_bundle = (os.environ.get("OPENWEBUI_CA_BUNDLE") or "").strip()
    if ca_bundle:
        session.verify = ca_bundle
    elif _env_bool01("OPENWEBUI_INSECURE_TLS", False):
        session.verify = False
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    try:
        try:
            _preflight(session, base, kid)
        except requests.RequestException as e:
            LOG.error("preflight failed: %s", e)
            return 1

        return _run_loop(
            session, base, kid, sync_dir, state, state_path,
            timeout, interval, post_delay, args, counters,
            max_file_size=max_file_size,
        )
    finally:
        elapsed = time.monotonic() - started_at
        LOG.warning(
            "push done elapsed=%.1fs (%dm%02ds) skip=%d upload=%d errors=%d (dry_run=%s)",
            elapsed,
            int(elapsed) // 60,
            int(elapsed) % 60,
            counters["skip"],
            counters["upload"],
            counters["errors"],
            args.dry_run,
        )


def _run_loop(
    session: requests.Session,
    base: str,
    kid: str,
    sync_dir: str,
    state: dict[str, Any],
    state_path: str,
    timeout: int,
    interval: float,
    post_delay: float,
    args: argparse.Namespace,
    counters: dict[str, int],
    *,
    max_file_size: int = 2 * 1024 * 1024,
) -> int:
    by_rel: dict[str, dict] = state["by_rel"]
    if args.prune and not args.dry_run:
        on_disk: set[str] = set()
        for abs_path in _collect_txt(sync_dir):
            rel = os.path.relpath(abs_path, os.path.abspath(sync_dir)).replace("\\", "/")
            on_disk.add(rel)
        to_drop = [r for r in by_rel if r not in on_disk]
        for rel in to_drop:
            file_id = by_rel[rel].get("file_id")
            sha = by_rel[rel].get("sha256", "?")[:12]
            if not file_id:
                del by_rel[rel]
                continue
            LOG.info("prune: remove from KB (missing on disk) %s sha=%s...", rel, sha)
            try:
                _kb_remove(session, base, kid, file_id)
            except requests.HTTPError as e:
                LOG.error("prune remove failed %s: %s", rel, e)
            else:
                del by_rel[rel]
            if post_delay > 0:
                time.sleep(post_delay)
        if to_drop:
            _save_state(state_path, state)

    paths = _collect_txt(sync_dir)
    if not paths:
        LOG.warning("no .txt under %s", sync_dir)
        return 0

    for abs_path in paths:
        rel = os.path.relpath(abs_path, os.path.abspath(sync_dir)).replace("\\", "/")
        fsize = os.path.getsize(abs_path)
        if fsize > max_file_size:
            LOG.warning("skip oversized file (%d bytes > %d max): %s", fsize, max_file_size, rel)
            counters["skip"] += 1
            continue
        try:
            sha = _file_sha256(abs_path)
        except OSError as e:
            LOG.error("hash %s: %s", rel, e)
            counters["errors"] += 1
            continue
        old = by_rel.get(rel)
        if old and old.get("sha256") == sha:
            if old.get("status", "complete") == "complete":
                counters["skip"] += 1
                continue
            try:
                if _finish_pending(session, base, kid, state_path, state, rel, timeout, interval):
                    counters["skip"] += 1
                    continue
            except (requests.RequestException, TimeoutError, RuntimeError) as e:
                LOG.error("%s: %s", rel, e)
                counters["errors"] += 1
                continue
        if args.dry_run:
            if old:
                LOG.info("would replace %s (old file_id=%s)", rel, old.get("file_id"))
            else:
                LOG.info("would add %s", rel)
            continue

        try:
            old_file_id = str(old["file_id"]) if old and old.get("file_id") else None
            if old and old.get("file_id"):
                LOG.info("replacing KB file %s old_file_id=%s", rel, str(old["file_id"])[:8])
            fid = _upload_file(session, base, abs_path)
            LOG.info("uploaded %s file_id=%s", rel, str(fid)[:8])
            by_rel[rel] = {
                "sha256": sha,
                "file_id": fid,
                "status": "uploaded",
                "old_file_id": old_file_id,
            }
            _save_state(state_path, state)
            _wait_processing(session, base, fid, timeout, interval)
            by_rel[rel]["status"] = "processed"
            _save_state(state_path, state)
            _kb_add(session, base, kid, fid)
            if old_file_id and old_file_id != fid:
                try:
                    _kb_remove(session, base, kid, old_file_id)
                except requests.HTTPError as e:
                    LOG.warning("remove old after add (continuing) %s: %s", rel, e)
            by_rel[rel] = {"sha256": sha, "file_id": fid, "status": "complete"}
            counters["upload"] += 1
            if post_delay > 0:
                time.sleep(post_delay)
            if counters["upload"] % 5 == 0:
                _save_state(state_path, state)
        except (requests.RequestException, TimeoutError, RuntimeError) as e:
            LOG.error("%s: %s", rel, e)
            counters["errors"] += 1
        except OSError as e:
            LOG.error("%s: %s", rel, e)
            counters["errors"] += 1

    if not args.dry_run and counters["upload"]:
        _save_state(state_path, state)

    LOG.info(
        "done: skip=%d upload=%d errors=%d (dry_run=%s)",
        counters["skip"], counters["upload"], counters["errors"], args.dry_run,
    )
    return 1 if counters["errors"] else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130) from None
