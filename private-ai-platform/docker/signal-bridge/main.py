"""
Signal <-> Open WebUI bridge: 1:1 chats, allowlist, optional pairing, rate limits.
Repo doc: private-ai-platform/SIGNAL-OPEN-WEBUI.md
Open WebUI: POST /api/chat/completions with Bearer (see upstream API reference).
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import sqlite3
import time
from pathlib import Path
from typing import Any, Optional
from urllib.parse import quote, urljoin

import aiohttp
from aiohttp import web

LOG = logging.getLogger("signal-bridge")


def _env(name: str, default: Optional[str] = None) -> str:
    v = os.environ.get(name, default)
    if v is None or v == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return v


def _env_opt(name: str, default: str = "") -> str:
    return os.environ.get(name, default) or default


def normalize_e164(num: str) -> str:
    n = (num or "").strip().replace(" ", "")
    if not n.startswith("+"):
        n = "+" + n.lstrip("+")
    return n


def parse_allowlist(raw: str) -> set[str]:
    out: set[str] = set()
    for part in raw.split(","):
        p = part.strip()
        if p:
            out.add(normalize_e164(p))
    return out


def ws_base_from_http(http_base: str) -> str:
    if http_base.startswith("https://"):
        return "wss://" + http_base[len("https://") :]
    if http_base.startswith("http://"):
        return "ws://" + http_base[len("http://") :]
    raise RuntimeError("SIGNAL_REST_URL must start with http:// or https://")


class Store:
    """SQLite: pairing, dedupe, per-sender history for chat completions."""

    def __init__(self, path: Path, max_history_rows: int) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.max_history_rows = max_history_rows
        self._init()

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(self.path)
        con.row_factory = sqlite3.Row
        return con

    def _init(self) -> None:
        with self._connect() as con:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS paired (
                  sender TEXT PRIMARY KEY,
                  paired_at REAL NOT NULL
                )
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS dedupe (
                  id TEXT PRIMARY KEY,
                  seen_at REAL NOT NULL
                )
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS history (
                  sender TEXT NOT NULL,
                  role TEXT NOT NULL,
                  content TEXT NOT NULL,
                  ts REAL NOT NULL
                )
                """
            )
            con.execute(
                "CREATE INDEX IF NOT EXISTS idx_history_sender_ts ON history(sender, ts)"
            )

    def claim_dedupe(self, dedupe_id: str) -> bool:
        """Return True if this id is new and was claimed; False if already seen."""
        now = time.time()
        with self._connect() as con:
            cur = con.execute(
                "INSERT OR IGNORE INTO dedupe (id, seen_at) VALUES (?, ?)",
                (dedupe_id, now),
            )
            if cur.rowcount != 1:
                return False
            con.execute("DELETE FROM dedupe WHERE seen_at < ?", (now - 86400 * 7,))
        return True

    def release_dedupe(self, dedupe_id: str) -> None:
        with self._connect() as con:
            con.execute("DELETE FROM dedupe WHERE id = ?", (dedupe_id,))

    def is_paired(self, sender: str) -> bool:
        with self._connect() as con:
            r = con.execute("SELECT 1 FROM paired WHERE sender = ?", (sender,)).fetchone()
            return r is not None

    def mark_paired(self, sender: str) -> None:
        with self._connect() as con:
            con.execute(
                "INSERT OR REPLACE INTO paired (sender, paired_at) VALUES (?, ?)",
                (sender, time.time()),
            )

    def load_history(self, sender: str, max_messages: int) -> list[dict[str, str]]:
        with self._connect() as con:
            rows = con.execute(
                """
                SELECT role, content FROM history
                WHERE sender = ? ORDER BY ts ASC LIMIT ?
                """,
                (sender, max_messages),
            ).fetchall()
        return [{"role": r["role"], "content": r["content"]} for r in rows]

    def append_message(self, sender: str, role: str, content: str) -> None:
        with self._connect() as con:
            con.execute(
                "INSERT INTO history (sender, role, content, ts) VALUES (?, ?, ?, ?)",
                (sender, role, content, time.time()),
            )
            while True:
                row = con.execute(
                    "SELECT COUNT(*) AS c FROM history WHERE sender = ?", (sender,)
                ).fetchone()
                if row is None or int(row["c"]) <= self.max_history_rows:
                    break
                oldest = con.execute(
                    """
                    SELECT rowid FROM history
                    WHERE sender = ? ORDER BY ts ASC LIMIT 1
                    """,
                    (sender,),
                ).fetchone()
                if oldest is None:
                    break
                con.execute("DELETE FROM history WHERE rowid = ?", (oldest["rowid"],))


def _sender_e164_from_envelope(env: dict[str, Any]) -> Optional[str]:
    n = env.get("sourceNumber")
    if isinstance(n, str) and n.strip():
        return normalize_e164(n)
    s = env.get("source")
    if isinstance(s, str) and s.strip():
        return normalize_e164(s)
    sa = env.get("sourceAddress")
    if isinstance(sa, dict):
        m = sa.get("number")
        if isinstance(m, str) and m.strip():
            return normalize_e164(m)
    return None


def extract_incoming(obj: Any) -> Optional[tuple[str, str, str]]:
    """Return (dedupe_id, sender_e164, user_text) or None."""
    if not isinstance(obj, dict):
        return None
    env = obj.get("envelope")
    if not isinstance(env, dict):
        return None
    dm = env.get("dataMessage")
    if not isinstance(dm, dict):
        return None
    text = dm.get("message")
    if not isinstance(text, str) or not text.strip():
        return None
    sender = _sender_e164_from_envelope(env)
    if not sender:
        return None
    ts = env.get("timestamp")
    dedupe_id = f"{sender}:{ts}:{hash(text)}"
    return (dedupe_id, sender, text.strip())


class Bridge:
    def __init__(self) -> None:
        self.signal_rest = _env_opt("SIGNAL_REST_URL", "http://signal-cli-rest-api:8080").rstrip(
            "/"
        )
        self.bot_number = normalize_e164(_env("SIGNAL_BOT_NUMBER"))
        self.allowlist = parse_allowlist(_env("SIGNAL_ALLOWLIST"))
        if not self.allowlist:
            raise RuntimeError("SIGNAL_ALLOWLIST must list at least one E.164 number")

        self.owui_base = _env_opt("OPENWEBUI_BASE_URL", "http://open-webui:8080").rstrip("/")
        self.owui_key = _env("OPENWEBUI_API_KEY")
        self.owui_model = _env("OPENWEBUI_MODEL")

        self.pairing_enabled = _env_opt("PAIRING_ENABLED", "0").strip().lower() in (
            "1",
            "true",
            "yes",
        )
        self.pairing_secret = _env_opt("PAIRING_SECRET", "").strip()
        if self.pairing_enabled and not self.pairing_secret:
            raise RuntimeError("PAIRING_SECRET is required when PAIRING_ENABLED is set")

        self.rate_limit_s = float(_env_opt("RATE_LIMIT_SECONDS", "3"))
        self._last_reply: dict[str, float] = {}

        self.max_hist = int(_env_opt("OPENWEBUI_MAX_HISTORY_MESSAGES", "40"))
        db_path = Path(_env_opt("SQLITE_PATH", "/data/bridge.sqlite3"))
        self.store = Store(db_path, self.max_hist)

        self.owui_timeout = aiohttp.ClientTimeout(
            connect=30,
            sock_read=int(_env_opt("OPENWEBUI_READ_TIMEOUT_SECONDS", "600")),
        )

        # Path must use literal "+" (E.164). quote(..., safe="") turns + into %2B and the API returns 400.
        recv_path = "/v1/receive/" + quote(self.bot_number, safe="+")
        self._ws_url = ws_base_from_http(self.signal_rest) + recv_path

    def _rate_ok(self, sender: str) -> bool:
        now = time.time()
        last = self._last_reply.get(sender, 0.0)
        if now - last < self.rate_limit_s:
            return False
        self._last_reply[sender] = now
        return True

    async def send_signal(self, session: aiohttp.ClientSession, recipient: str, text: str) -> None:
        url = urljoin(self.signal_rest + "/", "v2/send")
        body = {
            "number": self.bot_number,
            "recipients": [normalize_e164(recipient)],
            "message": text,
        }
        async with session.post(
            url,
            json=body,
            headers={"Content-Type": "application/json"},
            timeout=aiohttp.ClientTimeout(total=120),
        ) as resp:
            if resp.status >= 400:
                err = await resp.text()
                LOG.error("signal send failed: %s %s", resp.status, err[:500])
                resp.raise_for_status()

    async def complete_openwebui(
        self, session: aiohttp.ClientSession, messages: list[dict[str, str]]
    ) -> str:
        url = urljoin(self.owui_base + "/", "api/chat/completions")
        payload: dict[str, Any] = {
            "model": self.owui_model,
            "messages": messages,
            "stream": False,
        }
        kids_raw = _env_opt("OPENWEBUI_KNOWLEDGE_ID", "").strip()
        if kids_raw:
            payload["files"] = [
                {"type": "collection", "id": k.strip()}
                for k in kids_raw.split(",")
                if k.strip()
            ]

        async with session.post(
            url,
            json=payload,
            headers={
                "Authorization": f"Bearer {self.owui_key}",
                "Content-Type": "application/json",
            },
            timeout=self.owui_timeout,
        ) as resp:
            raw = await resp.text()
            if resp.status >= 400:
                LOG.error("openwebui chat failed: %s %s", resp.status, raw[:800])
                resp.raise_for_status()
            # Open WebUI streams Server-Sent Events even with stream=false when
            # the requested model has knowledge/tools attached. Reassemble both
            # streamed deltas and any final whole-message frames into one reply.
            if raw.lstrip().startswith("data:"):
                final, stats = self._reassemble_sse(raw)
                if final:
                    return final
                # No content. Diagnose the most common cause: OWUI model preset
                # uses function_calling="native", so OWUI passes tool_calls
                # straight back to this API client instead of running the tool
                # loop server-side. The bridge does not execute OWUI's internal
                # tools, so the stream ends with only tool_calls / sources.
                if stats["tool_calls"] > 0 and stats["delta_content"] == 0 and stats["message_content"] == 0:
                    LOG.warning(
                        "openwebui returned tool_calls only (count=%d, sources=%d); "
                        "set model preset 'function_calling' to 'default' so OWUI runs "
                        "the tool loop server-side; raw[:800]=%r",
                        stats["tool_calls"], stats["sources"], raw[:800],
                    )
                    return (
                        "Das Modell wollte Tools (z. B. Knowledge-Suche) nutzen, "
                        "aber das OWUI-Preset ist auf 'function_calling: native' gesetzt. "
                        "Bitte im OWUI-Admin im Modell-Preset auf 'default' umstellen, "
                        "dann liefert OWUI die Antwort direkt."
                    )
                LOG.warning(
                    "openwebui empty SSE reply; stats=%s raw[:1500]=%r",
                    stats, raw[:1500],
                )
                return "(empty reply)"
            data = json.loads(raw)
        choices = data.get("choices")
        if not isinstance(choices, list) or not choices:
            LOG.error("openwebui unexpected json: %s", raw[:800])
            raise RuntimeError("openwebui: missing choices")
        msg = choices[0].get("message", {})
        content = msg.get("content") if isinstance(msg, dict) else None
        if not isinstance(content, str):
            raise RuntimeError("openwebui: missing assistant content")
        text = content.strip()
        if not text:
            LOG.warning("openwebui empty JSON reply; raw[:800]=%r", raw[:800])
            return "(empty reply)"
        return text

    @staticmethod
    def _reassemble_sse(raw: str) -> tuple[str, dict[str, int]]:
        """Join Open WebUI SSE frames into a single reply and frame stats.

        OWUI emits a mix of frame types when tools/knowledge are attached:
        - classic streaming: choices[0].delta.content (string pieces)
        - terminal whole-message frame: choices[0].message.content
        - status / sources / tool-call frames without content
        - reasoning frames (delta.reasoning_content) - ignored
        - error frames {"error": {...}} - logged
        Streamed deltas win when present; otherwise the last whole-message
        frame is used as a fallback so single-frame replies are not dropped.
        Returns (reply, stats) where stats counts frame types so callers can
        diagnose empty replies (e.g. tool_calls-only streams).
        """
        deltas: list[str] = []
        last_message: Optional[str] = None
        stats = {
            "frames": 0,
            "delta_content": 0,
            "message_content": 0,
            "tool_calls": 0,
            "reasoning": 0,
            "sources": 0,
            "errors": 0,
        }
        for line in raw.splitlines():
            line = line.strip()
            if not line.startswith("data:"):
                continue
            payload_str = line[5:].strip()
            if not payload_str or payload_str == "[DONE]":
                if payload_str == "[DONE]":
                    break
                continue
            try:
                chunk = json.loads(payload_str)
            except json.JSONDecodeError:
                continue
            if not isinstance(chunk, dict):
                continue
            stats["frames"] += 1
            err = chunk.get("error")
            if err:
                stats["errors"] += 1
                LOG.warning("openwebui SSE error frame: %s", str(err)[:400])
            if "sources" in chunk:
                stats["sources"] += 1
            choices = chunk.get("choices")
            if not isinstance(choices, list) or not choices:
                continue
            choice = choices[0]
            if not isinstance(choice, dict):
                continue
            delta = choice.get("delta")
            if isinstance(delta, dict):
                piece = delta.get("content")
                if isinstance(piece, str) and piece:
                    deltas.append(piece)
                    stats["delta_content"] += 1
                if delta.get("tool_calls"):
                    stats["tool_calls"] += 1
                if isinstance(delta.get("reasoning_content"), str):
                    stats["reasoning"] += 1
            msg = choice.get("message")
            if isinstance(msg, dict):
                msg_content = msg.get("content")
                if isinstance(msg_content, str) and msg_content.strip():
                    last_message = msg_content
                    stats["message_content"] += 1
        joined = "".join(deltas).strip()
        if joined:
            return joined, stats
        if last_message:
            return last_message.strip(), stats
        return "", stats

    async def handle_text_message(
        self,
        session: aiohttp.ClientSession,
        sender: str,
        user_text: str,
        dedupe_id: str,
    ) -> None:
        if sender == self.bot_number:
            return
        if sender not in self.allowlist:
            LOG.info("ignored sender not on allowlist: %s", sender)
            return

        if not self.store.claim_dedupe(dedupe_id):
            return

        try:
            await self._handle_after_claim(session, sender, user_text, dedupe_id)
        except Exception:
            self.store.release_dedupe(dedupe_id)
            raise

    async def _handle_after_claim(
        self,
        session: aiohttp.ClientSession,
        sender: str,
        user_text: str,
        dedupe_id: str,
    ) -> None:
        if self.pairing_enabled and not self.store.is_paired(sender):
            if user_text.strip() == self.pairing_secret:
                self.store.mark_paired(sender)
                await self.send_signal(session, sender, "Paired. You can chat now.")
            else:
                await self.send_signal(
                    session,
                    sender,
                    "Send the pairing code to activate this bot.",
                )
            return

        if not self._rate_ok(sender):
            LOG.info("rate limited: %s", sender)
            self.store.release_dedupe(dedupe_id)
            return

        hist = self.store.load_history(sender, self.max_hist)
        messages = list(hist)
        messages.append({"role": "user", "content": user_text})
        try:
            answer = await self.complete_openwebui(session, messages)
        except Exception:
            LOG.exception("openwebui request failed for sender=%s", sender)
            await self.send_signal(
                session,
                sender,
                "Sorry, the model request failed. Try again later.",
            )
            raise

        self.store.append_message(sender, "user", user_text)
        self.store.append_message(sender, "assistant", answer)
        await self.send_signal(session, sender, answer)


async def dispatch_json(bridge: Bridge, session: aiohttp.ClientSession, obj: Any) -> None:
    if isinstance(obj, list):
        for item in obj:
            await dispatch_json(bridge, session, item)
        return
    got = extract_incoming(obj)
    if not got:
        if isinstance(obj, dict) and obj.get("envelope") is not None:
            ev = obj.get("envelope")
            if isinstance(ev, dict) and ev.get("dataMessage") is not None and not _sender_e164_from_envelope(
                ev
            ):
                LOG.info("unparsed: missing sender (sourceNumber/source) in envelope")
            elif isinstance(ev, dict) and ev.get("dataMessage") is None:
                LOG.debug("skip non-DM signal event keys=%s", list(ev.keys())[:20])
        return
    dedupe_id, sender, text = got
    await bridge.handle_text_message(session, sender, text, dedupe_id)


async def websocket_loop(bridge: Bridge, session: aiohttp.ClientSession) -> None:
    backoff = 3.0
    while True:
        try:
            LOG.info("connecting signal ws: %s", bridge._ws_url)
            async with session.ws_connect(
                bridge._ws_url,
                heartbeat=60,
                autoping=True,
                timeout=aiohttp.ClientTimeout(total=None),
            ) as ws:
                backoff = 3.0
                async for msg in ws:
                    if msg.type == aiohttp.WSMsgType.TEXT:
                        try:
                            data = json.loads(msg.data)
                        except json.JSONDecodeError:
                            LOG.warning("non-json ws frame")
                            continue
                        await dispatch_json(bridge, session, data)
                    elif msg.type in (aiohttp.WSMsgType.CLOSE, aiohttp.WSMsgType.CLOSING, aiohttp.WSMsgType.ERROR):
                        LOG.warning("ws closed or error: %s", msg.type)
                        break
        except asyncio.CancelledError:
            raise
        except Exception:
            LOG.exception("signal websocket error; reconnect in %ss", backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 1.5, 120.0)


async def http_poll_loop(bridge: Bridge, session: aiohttp.ClientSession) -> None:
    """
    Long-poll HTTP receive (signal-cli-rest-api). Required for MODE=native; WebSocket often returns HTTP 200 there.
    """
    path = "/v1/receive/" + quote(bridge.bot_number, safe="+")
    url = bridge.signal_rest + path
    poll_timeout = int(_env_opt("SIGNAL_HTTP_RECEIVE_TIMEOUT", "30"))
    # Server holds the connection up to poll_timeout; another /v1/receive may run first
    # (same account lock) so wall-clock can be ~2x poll_timeout or more.
    recv_total_s = _env_opt("SIGNAL_HTTP_CLIENT_TOTAL_TIMEOUT", "").strip()
    recv_total = int(recv_total_s) if recv_total_s else max(120, poll_timeout * 2 + 45)
    LOG.info("signal receive via HTTP long-poll: %s (client total=%ss)", url, recv_total)
    while True:
        try:
            params = {"timeout": str(poll_timeout)}
            async with session.get(
                url,
                params=params,
                timeout=aiohttp.ClientTimeout(total=recv_total, connect=30),
            ) as resp:
                if resp.status == 404 or resp.status == 405:
                    LOG.error("http receive not supported (status=%s)", resp.status)
                    await asyncio.sleep(30)
                    continue
                if resp.status >= 400:
                    LOG.error("signal http receive: %s %s", resp.status, (await resp.text())[:300])
                    await asyncio.sleep(10)
                    continue
                body = await resp.text()
                if not body.strip():
                    continue
                try:
                    data = json.loads(body)
                except json.JSONDecodeError:
                    LOG.debug("receive non-json: %s", body[:200])
                    continue
                await dispatch_json(bridge, session, data)
        except asyncio.CancelledError:
            raise
        except TimeoutError:
            LOG.warning(
                "signal http receive: client timeout (increase SIGNAL_HTTP_CLIENT_TOTAL_TIMEOUT "
                "or stop parallel /v1/receive); sleep 5s and retry"
            )
            await asyncio.sleep(5)
        except Exception:
            LOG.exception("http poll error; sleep 5s")
            await asyncio.sleep(5)


async def health(_: web.Request) -> web.Response:
    return web.Response(text="ok")


async def main_async() -> None:
    logging.basicConfig(
        level=getattr(logging, _env_opt("LOG_LEVEL", "INFO").upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    bridge = Bridge()
    # native: HTTP long-poll. json-rpc: optional WebSocket (SIGNAL_RECEIVE_MODE=ws).
    receive_mode = _env_opt("SIGNAL_RECEIVE_MODE", "http").strip().lower()
    if _env_opt("SIGNAL_USE_HTTP_POLL", "").strip().lower() in ("1", "true", "yes"):
        receive_mode = "http"
    if receive_mode not in ("http", "ws"):
        receive_mode = "http"

    async def health_app() -> None:
        app = web.Application()
        app.router.add_get("/health", health)
        runner = web.AppRunner(app)
        await runner.setup()
        site = web.TCPSite(runner, "0.0.0.0", int(_env_opt("HEALTH_PORT", "8765")))
        await site.start()
        LOG.info("health on :%s", _env_opt("HEALTH_PORT", "8765"))
        await asyncio.Event().wait()

    connector = aiohttp.TCPConnector(limit=10)
    async with aiohttp.ClientSession(connector=connector) as session:
        receive_task: asyncio.Task[None]
        if receive_mode == "ws":
            LOG.info("signal receive mode: websocket (use with json-rpc if supported)")
            receive_task = asyncio.create_task(websocket_loop(bridge, session))
        else:
            LOG.info("signal receive mode: http long-poll (default for signal-cli MODE=native)")
            receive_task = asyncio.create_task(http_poll_loop(bridge, session))
        await asyncio.gather(
            asyncio.create_task(health_app()),
            receive_task,
        )


def main() -> None:
    asyncio.run(main_async())


if __name__ == "__main__":
    main()
