#!/usr/bin/env python3
"""
Intranet text export for Open WebUI Knowledge. Apache NTLM (mod_authn_ntlm) + Contao/PHP.
Requires: NTLM-capable path from host to AD; use INTRANET_INSECURE_TLS=1 or install internal CA in OS.
"""
from __future__ import annotations

import hashlib
import html
import logging
import os
import re
import sqlite3
import sys
import threading
import time
import urllib3
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from io import BytesIO
from typing import Set
from urllib.parse import parse_qsl, urlencode, urldefrag, urljoin, urlparse, urlunparse, unquote
from xml.etree import ElementTree

import requests
from lxml import html as lxml_html
from pypdf import PdfReader
from pypdf.errors import PdfReadError
from requests_ntlm import HttpNtlmAuth
import trafilatura
from trafilatura.settings import use_config

from job_debug_log import install_debug_file

LOG = logging.getLogger("intranet_rag")

_CFG = use_config()
_CFG.set("DEFAULT", "MIN_OUTPUT_SIZE", "0")
_tls = threading.local()
_NTLM_CREDS: tuple[str, str] | None = None


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


def _env_bool01(name: str, default: bool) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "y")


def _now() -> float:
    return time.time()


def _parse_http_date(value: str | None) -> str | None:
    if not value:
        return None
    from email.utils import parsedate_to_datetime
    try:
        return parsedate_to_datetime(value).strftime("%Y-%m-%d")
    except Exception:
        return None


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


_STRIP_PARAMS = frozenset({
    "nc", "gclid", "fbclid", "msclkid", "_ga", "_gl",
})
_STRIP_PREFIXES = ("utm_", "mtm_")


def _canonical_url(u: str) -> str:
    u, _ = urldefrag(u)
    p = urlparse(u)
    scheme = (p.scheme or "https").lower()
    host = (p.hostname or "").lower()
    port = p.port
    netloc = host
    if port and not ((scheme == "http" and port == 80) or (scheme == "https" and port == 443)):
        netloc = f"{host}:{port}"
    pairs = parse_qsl(p.query, keep_blank_values=True)
    filtered = [(k, v) for k, v in pairs
                if k.lower() not in _STRIP_PARAMS
                and not any(k.lower().startswith(px) for px in _STRIP_PREFIXES)]
    query = urlencode(sorted(filtered), doseq=True)
    path = p.path or "/"
    return urlunparse((scheme, netloc, path, "", query, ""))


class CrawlState:
    def __init__(self, path: str) -> None:
        self.path = path
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        self._lock = threading.Lock()
        self._db = sqlite3.connect(path, timeout=30, check_same_thread=False)
        self._db.execute("PRAGMA journal_mode=WAL")
        self._db.execute("PRAGMA busy_timeout=30000")
        self._init_schema()

    def close(self) -> None:
        with self._lock:
            self._db.close()

    def _init_schema(self) -> None:
        with self._lock:
            self._db.executescript(
                """
                CREATE TABLE IF NOT EXISTS runs (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    started_at REAL NOT NULL,
                    finished_at REAL,
                    note TEXT
                );
                CREATE TABLE IF NOT EXISTS urls (
                    url TEXT PRIMARY KEY,
                    original_url TEXT NOT NULL,
                    kind TEXT NOT NULL DEFAULT 'unknown',
                    status TEXT NOT NULL DEFAULT 'pending',
                    output_path TEXT,
                    sha256 TEXT,
                    etag TEXT,
                    last_modified TEXT,
                    http_status INTEGER,
                    error TEXT,
                    fail_count INTEGER NOT NULL DEFAULT 0,
                    fetched_at REAL,
                    updated_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_urls_status_updated ON urls(status, updated_at);
                """
            )
            self._db.commit()

    def start_run(self, note: str) -> int:
        with self._lock:
            cur = self._db.execute(
                "INSERT INTO runs(started_at, note) VALUES (?, ?)", (_now(), note)
            )
            self._db.commit()
            return int(cur.lastrowid)

    def finish_run(self, run_id: int) -> None:
        with self._lock:
            self._db.execute("UPDATE runs SET finished_at=? WHERE id=?", (_now(), run_id))
            self._db.commit()

    def enqueue(self, url: str, kind: str = "unknown", refresh: bool = False) -> str:
        canon = _canonical_url(url)
        with self._lock:
            self._db.execute(
                """
                INSERT INTO urls(url, original_url, kind, status, updated_at)
                VALUES (?, ?, ?, 'pending', ?)
                ON CONFLICT(url) DO UPDATE SET
                    original_url=excluded.original_url,
                    kind=CASE WHEN urls.kind='unknown' THEN excluded.kind ELSE urls.kind END,
                    status=CASE WHEN ? OR urls.status IN ('error', 'fetching') THEN 'pending' ELSE urls.status END,
                    updated_at=excluded.updated_at
                """,
                (canon, url, kind, _now(), 1 if refresh else 0),
            )
            self._db.commit()
        return canon

    def pending_urls(self, limit: int) -> list[str]:
        with self._lock:
            rows = self._db.execute(
                """
                SELECT original_url FROM urls
                WHERE status IN ('pending', 'fetching')
                ORDER BY updated_at
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [str(r[0]) for r in rows]

    def conditional_headers(self, url: str) -> dict[str, str]:
        canon = _canonical_url(url)
        with self._lock:
            row = self._db.execute(
                "SELECT etag, last_modified FROM urls WHERE url=?", (canon,)
            ).fetchone()
        out: dict[str, str] = {}
        if not row:
            return out
        if row[0]:
            out["If-None-Match"] = str(row[0])
        if row[1]:
            out["If-Modified-Since"] = str(row[1])
        return out

    def should_skip_done_without_validator(self, url: str, skip_without_validator: bool) -> bool:
        if not skip_without_validator:
            return False
        canon = _canonical_url(url)
        with self._lock:
            row = self._db.execute(
                "SELECT status, etag, last_modified FROM urls WHERE url=?", (canon,)
            ).fetchone()
        return bool(row and row[0] == "done" and not row[1] and not row[2])

    def mark_fetching(self, url: str, kind: str) -> None:
        canon = self.enqueue(url, kind)
        with self._lock:
            self._db.execute(
                "UPDATE urls SET status='fetching', kind=?, error=NULL, updated_at=? WHERE url=?",
                (kind, _now(), canon),
            )
            self._db.commit()

    def mark_done(
        self,
        url: str,
        kind: str,
        output_path: str | None,
        sha256: str | None,
        http_status: int,
        headers: requests.structures.CaseInsensitiveDict[str],
    ) -> None:
        canon = _canonical_url(url)
        with self._lock:
            self._db.execute(
                """
                INSERT INTO urls(url, original_url, kind, status, output_path, sha256, etag, last_modified, http_status, error, fetched_at, updated_at)
                VALUES (?, ?, ?, 'done', ?, ?, ?, ?, ?, NULL, ?, ?)
                ON CONFLICT(url) DO UPDATE SET
                    original_url=excluded.original_url,
                    kind=excluded.kind,
                    status='done',
                    output_path=excluded.output_path,
                    sha256=excluded.sha256,
                    etag=excluded.etag,
                    last_modified=excluded.last_modified,
                    http_status=excluded.http_status,
                    error=NULL,
                    fetched_at=excluded.fetched_at,
                    updated_at=excluded.updated_at
                """,
                (
                    canon,
                    url,
                    kind,
                    output_path,
                    sha256,
                    headers.get("ETag"),
                    headers.get("Last-Modified"),
                    http_status,
                    _now(),
                    _now(),
                ),
            )
            self._db.commit()

    def mark_not_modified(self, url: str) -> None:
        canon = _canonical_url(url)
        with self._lock:
            self._db.execute(
                "UPDATE urls SET status='done', http_status=304, error=NULL, fetched_at=?, updated_at=? WHERE url=?",
                (_now(), _now(), canon),
            )
            self._db.commit()

    def mark_error(self, url: str, kind: str, ex: Exception) -> None:
        canon = self.enqueue(url, kind)
        with self._lock:
            self._db.execute(
                """
                UPDATE urls
                SET status='error', kind=?, error=?, fail_count=fail_count+1, updated_at=?
                WHERE url=?
                """,
                (kind, str(ex)[:1000], _now(), canon),
            )
            self._db.commit()

    def summary(self) -> dict[str, int]:
        with self._lock:
            rows = self._db.execute(
                "SELECT status, COUNT(*) FROM urls GROUP BY status"
            ).fetchall()
        return {str(k): int(v) for k, v in rows}


class RateLimiter:
    def __init__(self, delay: float) -> None:
        self.delay = max(0.0, delay)
        self._lock = threading.Lock()
        self._next_at = 0.0

    def wait(self) -> None:
        if self.delay <= 0:
            return
        with self._lock:
            now = time.time()
            if now < self._next_at:
                time.sleep(self._next_at - now)
                now = time.time()
            self._next_at = now + self.delay


def _set_ntlm_creds(nuser: str, npass: str) -> None:
    global _NTLM_CREDS
    _NTLM_CREDS = (nuser, npass)


def _thread_local_session() -> requests.Session:
    s = getattr(_tls, "session", None)
    if s is None:
        if _NTLM_CREDS is None:
            raise RuntimeError("ntlm creds not set for parallel fetch")
        n, p = _NTLM_CREDS
        s = requests.Session()
        s.auth = HttpNtlmAuth(n, p)
        s.headers["User-Agent"] = "private-ai-platform-intranet-rag/1.0"
        _tls.session = s
    return s


def _local_tag(tag: str) -> str:
    if "}" in tag:
        return tag.rsplit("}", 1)[-1]
    return tag


def _same_host(base_url: str, other: str) -> bool:
    return urlparse(base_url).netloc.lower() == urlparse(other).netloc.lower()


def _is_skippable_path(path: str) -> bool:
    p = path.lower()
    for ext in (
        ".css", ".js", ".woff", ".woff2", ".ttf", ".ico",
        ".png", ".jpg", ".jpeg", ".gif", ".svg", ".mp4", ".webm", ".zip",
        ".xls", ".xlsx", ".ppt", ".pptx",
        ".odt", ".ods", ".odp",
    ):
        if p.endswith(ext):
            return True
    return False


def collect_sitemap_locs(
    session: requests.Session, sitemap_url: str, seen: Set[str], depth: int, verify: bool
) -> list[str]:
    if sitemap_url in seen or depth > 25:
        return []
    seen.add(sitemap_url)
    try:
        r = session.get(sitemap_url, timeout=120, allow_redirects=True, verify=verify)
    except OSError as ex:
        LOG.warning("sitemap fetch %s: %s", sitemap_url, ex)
        return []
    if r.status_code != 200:
        LOG.warning("sitemap %s -> HTTP %s", sitemap_url, r.status_code)
        return []
    if not (r.text or "").strip():
        return []
    try:
        root = ElementTree.fromstring(r.content)
    except ElementTree.ParseError as ex:
        LOG.warning("sitemap parse %s: %s", sitemap_url, ex)
        return []
    is_index = any(_local_tag(t.tag).lower() == "sitemap" for t in root.iter())
    out: list[str] = []
    for el in root.iter():
        if _local_tag(el.tag).lower() != "loc" or not (el.text or "").strip():
            continue
        loc = el.text.strip()
        if is_index and (loc.endswith(".xml") or "sitemap" in loc):
            out.extend(
                collect_sitemap_locs(session, loc, seen, depth + 1, verify)
            )
        else:
            out.append(loc)
    return out


def _unique_urls(urls: list[str]) -> list[str]:
    seen: set[str] = set()
    o: list[str] = []
    for u in urls:
        u0, _ = urldefrag(u)
        if u0 not in seen:
            seen.add(u0)
            o.append(u0)
    return o


def _path_for_file(u: str) -> str:
    p = unquote(urlparse(u).path) or "index"
    p = p.strip("/").replace("/", "_")
    p = re.sub(r"[^a-zA-Z0-9._-]+", "_", p)[:150]
    return p if p and p != "." else "page"


def _apply_boilerplate_filter(text: str) -> str:
    """Remove lines matching configured boilerplate substrings."""
    raw = (os.environ.get("INTRANET_BOILERPLATE_LINES") or "").strip()
    if not raw:
        return text
    patterns = [line.strip() for line in raw.split("\n") if line.strip()]
    if not patterns:
        return text
    out: list[str] = []
    for line in text.split("\n"):
        if any(pat in line for pat in patterns):
            continue
        out.append(line)
    return "\n".join(out)


def _write_text(out_path: str, source_url: str, body: str, date: str | None = None, meta: dict[str, str] | None = None) -> None:
    """Write export file with structured INTRANET_SEITE header for RAG chunking."""
    meta = meta or {}
    title = meta.get("title", "")
    breadcrumb = meta.get("breadcrumb", "")
    description = meta.get("description", "")
    author = meta.get("author", "")

    lines: list[str] = ["### INTRANET_SEITE"]
    if title:
        lines.append(f"title: {title}")
    lines.append(f"source_url: {source_url}")
    if date:
        lines.append(f"date: {date}")
    if breadcrumb:
        lines.append(f"breadcrumb: {breadcrumb}")
    if description:
        lines.append(f"description: {description}")
    if author:
        lines.append(f"cms_seitenredakteur: {author}")
    lines.append("---")

    head = "\n".join(lines) + "\n"
    foot = f"\n---\nsource_url: {source_url}\n"
    if date:
        foot += f"date: {date}\n"

    body = _apply_boilerplate_filter(body or "")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(head)
        f.write("\n")
        f.write(body.rstrip())
        f.write(foot)


def _extract_contao_dom(got: str, u: str) -> tuple[str, dict[str, str]]:
    """Fallback extractor for Contao CMS pages using lxml DOM parsing.
    Returns (text, metadata_dict) where metadata has title, date, author, breadcrumb, description."""
    meta: dict[str, str] = {}
    try:
        doc = lxml_html.fromstring(
            got.encode("utf-8", errors="replace") if isinstance(got, str) else got
        )
    except Exception:
        return "", meta

    for m in doc.xpath('//meta[@name="description"]/@content'):
        if m and m.strip():
            meta["description"] = m.strip()
            break

    for h1 in doc.xpath('//main//h1/text() | //article//h1/text()'):
        if h1 and h1.strip():
            meta["title"] = h1.strip()
            break
    if "title" not in meta:
        for t in doc.xpath('//title/text()'):
            if t and t.strip():
                raw = t.strip()
                meta["title"] = re.sub(r"\s*[-|]\s*Intranet$", "", raw).strip() or raw
                break

    for el in doc.cssselect('.newsDatum') if hasattr(doc, 'cssselect') else doc.xpath('//*[contains(@class,"newsDatum")]'):
        txt = (el.text_content() or "").strip()
        if txt:
            meta["date_raw"] = txt
            break

    for el in doc.xpath('//*[contains(@class,"newsAuthor")]'):
        txt = (el.text_content() or "").strip()
        if txt:
            meta["author"] = txt
            break

    for el in doc.xpath('//*[contains(@class,"breadcrumbList")] | //*[contains(@class,"mod_breadcrumb")]'):
        parts = [s.strip() for s in el.text_content().split(">") if s.strip()]
        if parts:
            meta["breadcrumb"] = " > ".join(parts)
            break

    content_el = None
    for sel in ('//main[@id="main"]', '//main', '//article',
                '//*[contains(@class,"mod_newsreader")]',
                '//*[contains(@class,"mod_article")]'):
        found = doc.xpath(sel)
        if found:
            content_el = found[0]
            break

    if content_el is None:
        return "", meta

    from lxml import etree
    for tag in content_el.xpath('.//script | .//style | .//nav | .//noscript'):
        tag.getparent().remove(tag)
    for comment in content_el.xpath('.//comment()'):
        if 'indexer::stop' in str(comment) or 'indexer::continue' in str(comment):
            parent = comment.getparent()
            if parent is not None:
                parent.remove(comment)

    text = (content_el.text_content() or "").strip()
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip(), meta


def _extract_html_to_text(got: str, u: str) -> tuple[str, str | None, dict[str, str]]:
    """Return (extracted_text, page_date_or_None, metadata_dict).
    Tries trafilatura first, falls back to Contao DOM extractor. Never returns raw HTML."""
    date_str: str | None = None
    meta: dict[str, str] = {}
    try:
        result = trafilatura.bare_extraction(got, url=u, config=_CFG)
        if result and isinstance(result, dict):
            t = (result.get("text") or "").strip()
            date_str = result.get("date") or None
            if result.get("title"):
                meta["title"] = result["title"]
            if result.get("description"):
                meta["description"] = result["description"]
        else:
            t = ""
    except Exception:
        t = ""

    if len(t) >= 30:
        return t, date_str, meta

    dom_text, dom_meta = _extract_contao_dom(got, u)
    meta.update(dom_meta)

    if dom_text and len(dom_text) >= 30:
        if not date_str and dom_meta.get("date_raw"):
            date_str = dom_meta["date_raw"]
        return dom_text, date_str, meta

    if t:
        return t, date_str, meta
    if dom_text:
        return dom_text, date_str, meta

    LOG.info("both extractors empty for %s (html=%d bytes), skipping content", u, len(got))
    return "", date_str, meta


def _body_looks_like_html(b: bytes) -> bool:
    s = b.lstrip(b"\x00 \t\n\r\xef\xbb\xbf")
    if s.startswith(b"PK\x03\x04"):
        return False
    if not s:
        return False
    if s[0:1] == b"<" or s[:5].lower() == b"<?xml":
        return True
    return False


def _body_starts_with_pdf(b: bytes) -> bool:
    s = _normalize_pdf_bytes(b)
    return len(s) >= 5 and s[:4] == b"%PDF"


def _normalize_pdf_bytes(data: bytes) -> bytes:
    """Strip leading junk (whitespace, BOM) so %PDF is at start; reduces pypdf warnings."""
    if not data:
        return data
    s = data.lstrip(b"\x00 \t\n\r\xef\xbb\xbf")
    i = s.find(b"%PDF")
    if i == -1:
        return data
    if i > 0:
        s = s[i:]
    return s


def _pdf_text_from_bytes(data: bytes, source_url: str) -> str:
    data = _normalize_pdf_bytes(data)
    try:
        rdr = PdfReader(BytesIO(data), strict=False)
    except (PdfReadError, OSError, ValueError) as ex:
        LOG.warning("pdf open: %s", ex)
        return "[no extractable text: could not read PDF]"

    parts: list[str] = []
    page_err = 0
    try:
        for p in rdr.pages:
            try:
                x = p.extract_text() or ""
            except Exception as ex:
                page_err += 1
                LOG.debug("pdf page extract: %s", ex)
                continue
            if x:
                parts.append(x)
    except Exception as ex:
        LOG.warning("pdf iterate: %s", ex)

    if page_err and source_url:
        LOG.warning("pdf: %d page(s) skipped (parse errors), partial text: %s", page_err, source_url)
    s = "\n\n".join(parts).strip()
    return s or "[no extractable text, possibly scanned]"


def _pdf_ocr_text_from_bytes(data: bytes, source_url: str) -> str:
    """OCR fallback for scanned PDFs using pdf2image + tesseract."""
    try:
        import tempfile
        from pdf2image import convert_from_path
        import pytesseract
    except Exception as ex:
        LOG.warning("pdf ocr deps missing: %s", ex)
        return ""

    lang = (os.environ.get("INTRANET_OCR_LANG") or "").strip() or "deu"
    dpi = _env_int("INTRANET_OCR_DPI", 200)
    max_pages = _env_int("INTRANET_OCR_MAX_PAGES", 0)
    with tempfile.TemporaryDirectory(prefix="intranet-rag-pdf-ocr-") as tmp:
        pdf_path = os.path.join(tmp, "input.pdf")
        with open(pdf_path, "wb") as f:
            f.write(data)
        try:
            pages = convert_from_path(pdf_path, dpi=dpi, fmt="png")
        except Exception as ex:
            LOG.warning("pdf ocr render failed for %s: %s", source_url, ex)
            return ""
        parts: list[str] = []
        for idx, page in enumerate(pages, start=1):
            if max_pages > 0 and idx > max_pages:
                break
            try:
                text = pytesseract.image_to_string(page, lang=lang).strip()
            except Exception as ex:
                LOG.warning("pdf ocr page %s failed for %s: %s", idx, source_url, ex)
                continue
            if text:
                parts.append(f"--- page {idx} ---\n{text}")
        return "\n\n".join(parts).strip()


def _get_base_href(got: str) -> str | None:
    """Extract <base href='...'> from HTML if present."""
    try:
        doc = lxml_html.fromstring(
            got.encode("utf-8", errors="replace") if isinstance(got, str) else got
        )
        for base in doc.xpath('//base/@href'):
            if base and base.strip():
                return base.strip()
    except Exception:
        pass
    return None


def _hrefs_from_html(page_url: str, got: str) -> list[str]:
    if not got:
        return []
    try:
        root = lxml_html.fromstring(
            got.encode("utf-8", errors="replace")
            if isinstance(got, str)
            else got
        )
    except Exception as ex:
        LOG.debug("parse links: %s", ex)
        return []
    base_href = None
    for b in root.xpath('//base/@href'):
        if b and b.strip():
            base_href = b.strip()
            break
    resolve_base = base_href or page_url
    out: list[str] = []
    for href in root.xpath("//a/@href"):
        s = html.unescape((href or "").strip())
        if not s or s.startswith("#") or s.lower().startswith("javascript:") or s.lower().startswith("mailto:"):
            continue
        out.append(s)
    return [urldefrag(urljoin(resolve_base, h))[0] for h in out]


def _bfs_one_parallel(
    u: str,
    base_url: str,
    out_dir: str,
    verify: bool,
    limiter: RateLimiter,
    state: CrawlState,
    max_bytes: int,
    skip_done_without_validator: bool,
) -> tuple[int, list[str]]:
    """Eine BFS-URL. Rueckgabe: (Zaehler 0/1 wie bfs, neue gleich-Host-Links fuer die Queue)."""
    session = _thread_local_session()
    u, _ = urldefrag(u)
    if not _same_host(base_url, u):
        return 0, []
    pth = urlparse(u).path or "/"
    if u.lower().split("?", 1)[0].endswith(".pdf"):
        try:
            state.enqueue(u, "pdf", refresh=True)
            fetch_pdf(session, u, out_dir, verify, limiter, state, max_bytes, skip_done_without_validator)
            return 1, []
        except Exception as ex:
            state.mark_error(u, "pdf", ex)
            LOG.warning("pdf %s: %s", u, ex)
            return 0, []
    if _is_skippable_path(pth):
        return 0, []
    got = fetch_html(
        session, base_url, u, out_dir, verify, limiter, state, max_bytes, skip_done_without_validator
    )
    if got is None:
        return 1, []
    new: list[str] = []
    for link in _hrefs_from_html(u, got):
        if not _same_host(base_url, link):
            continue
        lp, _ = urldefrag(link)
        if _is_skippable_path(urlparse(lp).path or ""):
            continue
        if lp.lower().split("?", 1)[0].endswith(".pdf"):
            try:
                state.enqueue(lp, "pdf", refresh=True)
                fetch_pdf(
                    session,
                    lp,
                    out_dir,
                    verify,
                    limiter,
                    state,
                    max_bytes,
                    skip_done_without_validator,
                )
            except Exception as ex:
                state.mark_error(lp, "pdf", ex)
                LOG.warning("pdf from page %s: %s", lp, ex)
            continue
        state.enqueue(lp, "html", refresh=True)
        new.append(lp)
    return 1, new


def fetch_pdf(
    session: requests.Session,
    url: str,
    out_dir: str,
    verify: bool,
    limiter: RateLimiter,
    state: CrawlState,
    max_bytes: int,
    skip_done_without_validator: bool,
    data: bytes | None = None,
    response_headers: requests.structures.CaseInsensitiveDict[str] | None = None,
    status_code: int = 200,
) -> None:
    if state.should_skip_done_without_validator(url, skip_done_without_validator):
        LOG.info("skip cached pdf %s", url)
        return
    h = hashlib.sha256(url.encode("utf-8")).hexdigest()[:8]
    base = _path_for_file(url) + "_pdf"
    out_path = os.path.join(out_dir, f"{base}__{h}.txt")
    if data is None:
        state.mark_fetching(url, "pdf")
        limiter.wait()
        r = session.get(
            url,
            timeout=300,
            allow_redirects=True,
            stream=True,
            verify=verify,
            headers=state.conditional_headers(url),
        )
        if r.status_code == 304:
            state.mark_not_modified(url)
            LOG.info("not modified pdf %s", url)
            return
        r.raise_for_status()
        declared = int((r.headers.get("content-length") or "0") or "0")
        if declared > max_bytes:
            raise ValueError(f"pdf too large ({declared} bytes): {url}")
        chunks: list[bytes] = []
        total = 0
        for chunk in r.iter_content(65536):
            if not chunk:
                continue
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"pdf too large (>{max_bytes} bytes): {url}")
            chunks.append(chunk)
        data = b"".join(chunks)
        response_headers = r.headers
        status_code = r.status_code
    text = _pdf_text_from_bytes(data, url)
    lm_date = _parse_http_date((response_headers or {}).get("Last-Modified"))
    if text.startswith("[no extractable text"):
        ocr_text = _pdf_ocr_text_from_bytes(data, url)
        if ocr_text:
            text = ocr_text
    _write_text(out_path, url, text, lm_date)
    state.mark_done(url, "pdf", out_path, _sha256_bytes(data), status_code, response_headers or {})
    LOG.info("wrote %s", out_path)


def fetch_html(
    session: requests.Session,
    base_url: str,
    u: str,
    out_dir: str,
    verify: bool,
    limiter: RateLimiter,
    state: CrawlState,
    max_bytes: int,
    skip_done_without_validator: bool,
) -> str | None:
    """Return raw HTML for link discovery, or None."""
    if state.should_skip_done_without_validator(u, skip_done_without_validator):
        LOG.info("skip cached html %s", u)
        return None
    h = hashlib.sha256(u.encode("utf-8")).hexdigest()[:8]
    p = _path_for_file(u)
    out_path = os.path.join(out_dir, f"{p}__{h}.txt")
    state.mark_fetching(u, "html")
    limiter.wait()
    r = session.get(
        u,
        timeout=120,
        allow_redirects=True,
        verify=verify,
        headers=state.conditional_headers(u),
    )
    if r.status_code == 304:
        state.mark_not_modified(u)
        LOG.info("not modified html %s", u)
        return None
    if r.status_code != 200:
        LOG.info("skip %s status=%s", u, r.status_code)
        state.mark_done(u, "skip", None, None, r.status_code, r.headers)
        return None
    declared = int((r.headers.get("content-length") or "0") or "0")
    if declared > max_bytes:
        raise ValueError(f"html too large ({declared} bytes): {u}")
    body: bytes = r.content or b""
    if not body:
        state.mark_done(u, "skip", None, None, r.status_code, r.headers)
        return None
    if len(body) > max_bytes:
        raise ValueError(f"html too large (>{max_bytes} bytes): {u}")
    ctype = (r.headers.get("content-type") or "").lower().split(";")[0].strip()
    if "pdf" in ctype or u.lower().split("?", 1)[0].endswith(".pdf"):
        fetch_pdf(
            session,
            u,
            out_dir,
            verify,
            limiter,
            state,
            max_bytes,
            skip_done_without_validator,
            data=body,
            response_headers=r.headers,
            status_code=r.status_code,
        )
        return None
    if _body_starts_with_pdf(body):
        fetch_pdf(
            session,
            u,
            out_dir,
            verify,
            limiter,
            state,
            max_bytes,
            skip_done_without_validator,
            data=body,
            response_headers=r.headers,
            status_code=r.status_code,
        )
        return None
    if not _body_looks_like_html(body):
        LOG.info("skip non-html/binary %s (%s)", u, ctype or "no-content-type")
        state.mark_done(u, "binary", None, _sha256_bytes(body), r.status_code, r.headers)
        return None
    try:
        got = body.decode((r.apparent_encoding or "utf-8"), errors="replace")
    except (LookupError, TypeError, ValueError, UnicodeError):
        got = body.decode("utf-8", errors="replace")
    if not (got or "").strip():
        return None
    text, page_date, meta = _extract_html_to_text(got, u)
    lm_date = _parse_http_date(r.headers.get("Last-Modified"))
    effective_date = page_date or lm_date
    if not text or len(text) < 30:
        LOG.info("no usable text for %s, writing metadata stub", u)
        stub = f"[Kein extrahierbarer Text. Titel: {meta.get('title', 'unbekannt')}]"
        _write_text(out_path, u, stub, effective_date, meta=meta)
    else:
        _write_text(out_path, u, text, effective_date, meta=meta)
    state.mark_done(u, "html", out_path, _sha256_bytes(body), r.status_code, r.headers)
    LOG.info("wrote %s", out_path)
    pdf_base = _get_base_href(got) or u
    for href in re.finditer(
        r"""href=['"]([^'"]*\.[pP][dD][fF](?:\?[^'"]*)?)['"]""", got
    ):
        uu, _ = urldefrag(urljoin(pdf_base, html.unescape(href.group(1).strip())))
        if _same_host(base_url, uu):
            try:
                state.enqueue(uu, "pdf", refresh=True)
                fetch_pdf(
                    session,
                    uu,
                    out_dir,
                    verify,
                    limiter,
                    state,
                    max_bytes,
                    skip_done_without_validator,
                )
            except Exception as ex:
                state.mark_error(uu, "pdf", ex)
                LOG.warning("link pdf %s: %s", uu, ex)
    return got


def bfs_crawl(
    session: requests.Session,
    base_url: str,
    seeds: list[str],
    out_dir: str,
    max_pages: int,
    verify: bool,
    nuser: str,
    npass: str,
    workers: int,
    limiter: RateLimiter,
    state: CrawlState,
    max_bytes: int,
    skip_done_without_validator: bool,
) -> None:
    if workers > 1:
        _bfs_crawl_parallel(
            base_url,
            seeds,
            out_dir,
            max_pages,
            verify,
            nuser,
            npass,
            workers,
            limiter,
            state,
            max_bytes,
            skip_done_without_validator,
        )
        return
    enq: set[str] = set()
    q: deque[str] = deque()
    start_urls = _unique_urls(seeds + state.pending_urls(max_pages))
    for s in start_urls:
        s0, _ = urldefrag(s)
        s_key = _canonical_url(s0)
        if _same_host(base_url, s0) and s_key not in enq:
            state.enqueue(s0, "html", refresh=True)
            enq.add(s_key)
            q.append(s0)
    n = 0
    while q and n < max_pages:
        u, _ = urldefrag(q.popleft())
        if not _same_host(base_url, u):
            continue
        pth = urlparse(u).path or "/"
        if u.lower().split("?", 1)[0].endswith(".pdf"):
            try:
                state.enqueue(u, "pdf", refresh=True)
                fetch_pdf(session, u, out_dir, verify, limiter, state, max_bytes, skip_done_without_validator)
                n += 1
            except Exception as ex:
                state.mark_error(u, "pdf", ex)
                LOG.warning("pdf %s: %s", u, ex)
            continue
        if _is_skippable_path(pth):
            continue
        try:
            got = fetch_html(
                session,
                base_url,
                u,
                out_dir,
                verify,
                limiter,
                state,
                max_bytes,
                skip_done_without_validator,
            )
        except Exception as ex:
            state.mark_error(u, "html", ex)
            LOG.warning("html %s: %s", u, ex)
            got = None
        n += 1
        if got is None:
            continue
        for link in _hrefs_from_html(u, got):
            if not _same_host(base_url, link):
                continue
            lp, _ = urldefrag(link)
            if _is_skippable_path(urlparse(lp).path or ""):
                continue
            if lp.lower().split("?", 1)[0].endswith(".pdf"):
                try:
                    state.enqueue(lp, "pdf", refresh=True)
                    fetch_pdf(
                        session,
                        lp,
                        out_dir,
                        verify,
                        limiter,
                        state,
                        max_bytes,
                        skip_done_without_validator,
                    )
                except Exception as ex:
                    state.mark_error(lp, "pdf", ex)
                    LOG.warning("pdf from page %s: %s", lp, ex)
                continue
            lp_key = _canonical_url(lp)
            if lp_key in enq:
                continue
            if len(enq) > 50000:
                LOG.warning("safety: stop bfs, too many enqueued")
                return
            state.enqueue(lp, "html", refresh=True)
            enq.add(lp_key)
            q.append(lp)


def _bfs_crawl_parallel(
    base_url: str,
    seeds: list[str],
    out_dir: str,
    max_pages: int,
    verify: bool,
    nuser: str,
    npass: str,
    workers: int,
    limiter: RateLimiter,
    state: CrawlState,
    max_bytes: int,
    skip_done_without_validator: bool,
) -> None:
    w = min(max(1, workers), 32)
    _set_ntlm_creds(nuser, npass)
    enq: set[str] = set()
    enq_l = threading.Lock()
    q: deque[str] = deque()
    for s in _unique_urls(seeds + state.pending_urls(max_pages)):
        s0, _ = urldefrag(s)
        s_key = _canonical_url(s0)
        with enq_l:
            if _same_host(base_url, s0) and s_key not in enq:
                if len(enq) >= 50000:
                    break
                state.enqueue(s0, "html", refresh=True)
                enq.add(s_key)
                q.append(s0)
    n = 0
    with ThreadPoolExecutor(max_workers=w) as ex:
        while q and n < max_pages:
            if len(enq) > 50000:
                LOG.warning("safety: stop bfs, too many enqueued")
                return
            remain = max_pages - n
            if remain <= 0:
                break
            batch: list[str] = []
            while q and len(batch) < w and len(batch) < remain:
                u = q.popleft()
                u, _ = urldefrag(u)
                batch.append(u)
            if not batch:
                break
            futs = {
                ex.submit(
                    _bfs_one_parallel,
                    b,
                    base_url,
                    out_dir,
                    verify,
                    limiter,
                    state,
                    max_bytes,
                    skip_done_without_validator,
                ): b
                for b in batch
            }
            for fut in as_completed(futs):
                try:
                    inc, new_links = fut.result()
                except Exception as exc:
                    LOG.warning("bfs task: %s", exc)
                    continue
                n += inc
                for lp in new_links:
                    lp_key = _canonical_url(lp)
                    with enq_l:
                        if len(enq) > 50000:
                            return
                        if lp_key in enq:
                            continue
                        enq.add(lp_key)
                        q.append(lp)
    LOG.info("bfs done (parallel workers=%s)", w)


def _sitemap_item(
    u: str,
    base_url: str,
    out_dir: str,
    verify: bool,
    limiter: RateLimiter,
    state: CrawlState,
    max_bytes: int,
    skip_done_without_validator: bool,
) -> None:
    session = _thread_local_session()
    u, _ = urldefrag(u)
    if not _same_host(base_url, u):
        return
    if u.lower().split("?", 1)[0].endswith(".pdf"):
        try:
            state.enqueue(u, "pdf", refresh=True)
            fetch_pdf(session, u, out_dir, verify, limiter, state, max_bytes, skip_done_without_validator)
        except Exception as ex:
            state.mark_error(u, "pdf", ex)
            LOG.warning("pdf %s: %s", u, ex)
    elif not _is_skippable_path(urlparse(u).path or ""):
        try:
            state.enqueue(u, "html", refresh=True)
            fetch_html(
                session,
                base_url,
                u,
                out_dir,
                verify,
                limiter,
                state,
                max_bytes,
                skip_done_without_validator,
            )
        except Exception as ex:
            state.mark_error(u, "html", ex)
            LOG.warning("html %s: %s", u, ex)


def run() -> int:
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stderr
    )
    logging.getLogger("pypdf").setLevel(logging.ERROR)
    logging.getLogger("pypdf._reader").setLevel(logging.ERROR)
    for _name in (
        "trafilatura",
        "trafilatura.core",
        "trafilatura.utils",
        "trafilatura.readability_lxml",
    ):
        logging.getLogger(_name).setLevel(logging.CRITICAL)
    base = _env("INTRANET_BASE_URL", "").rstrip("/")
    nuser = _env("INTRANET_NTLM_USER")
    npass = _env("INTRANET_NTLM_PASS", "")
    out_dir = _env("INTRANET_OUTPUT_DIR", "/opt/private-ai-platform/data/intranet-rag")
    raw_sitemap = (os.environ.get("INTRANET_SITEMAP_URL") or "").strip()
    if raw_sitemap:
        sitemap_candidates = [x.strip() for x in raw_sitemap.split(",") if x.strip()]
    else:
        sitemap_candidates = [f"{base}/sitemap.xml", f"{base}/sitemap_index.xml"]
    delay = float((os.environ.get("INTRANET_REQUEST_DELAY") or "0.5") or 0.5)
    max_pages = _env_int("INTRANET_MAX_PAGES", 2000)
    max_bytes = _env_int("INTRANET_MAX_BYTES", 100 * 1024 * 1024)
    state_path = _env("INTRANET_STATE_FILE", os.path.join(out_dir, ".ingest-state.sqlite3"))
    skip_done_without_validator = _env_bool01("INTRANET_SKIP_DONE_WITHOUT_VALIDATOR", False)
    discover = _env_bool01("INTRANET_DISCOVER_LINKS", False)
    verify = not _env_bool01("INTRANET_INSECURE_TLS", False)
    conc = _env_int("INTRANET_CONCURRENCY", 1)
    conc = min(max(1, conc), 32)

    if not verify:
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    os.makedirs(out_dir, exist_ok=True)
    install_debug_file(out_dir, truncate=True, job_label="ingest")
    s = requests.Session()
    s.auth = HttpNtlmAuth(nuser, npass)
    s.headers["User-Agent"] = "private-ai-platform-intranet-rag/1.0"
    limiter = RateLimiter(delay)
    state = CrawlState(state_path)
    run_id = state.start_run(f"base={base} discover={discover} workers={conc}")
    started_at = time.monotonic()

    try:
        LOG.info("sitemap candidates: %s", sitemap_candidates)
        seen: set[str] = set()
        all_u_merged: list[str] = []
        for sm in sitemap_candidates:
            part = collect_sitemap_locs(s, sm, seen, 0, verify)
            if part:
                all_u_merged.extend([u for u in part if _same_host(base, u)])
        all_u = _unique_urls(all_u_merged)
        if not all_u:
            raw = (os.environ.get("INTRANET_SEED_URLS") or "").strip()
            if raw:
                all_u = _unique_urls(
                    [x.strip() for x in raw.split(",") if x.strip()]
                )
            if not all_u:
                all_u = [f"{base}/"]
            LOG.warning("sitemap liefert keine <loc> oder 404; nutze Seeds: %s", all_u[:5])
        for u in all_u[:max_pages]:
            kind = "pdf" if u.lower().split("?", 1)[0].endswith(".pdf") else "html"
            if _same_host(base, u):
                state.enqueue(u, kind, refresh=True)
        if not discover and len(_unique_urls(all_u)) <= 1:
            LOG.warning(
                "nur(ein) Start-URL: fuer Crawl per Links INTRANET_DISCOVER_LINKS=1 setzen"
            )
        if discover:
            bfs_crawl(
                s,
                base,
                all_u,
                out_dir,
                max_pages,
                verify,
                nuser,
                npass,
                conc,
                limiter,
                state,
                max_bytes,
                skip_done_without_validator,
            )
        elif conc > 1:
            _set_ntlm_creds(nuser, npass)
            to_fetch = [urldefrag(u)[0] for u in state.pending_urls(max_pages)]
            LOG.info("sitemap: parallel fetch, workers=%s, urls=%s", conc, len(to_fetch))

            def _one_sm(u0: str) -> None:
                try:
                    _sitemap_item(
                        u0,
                        base,
                        out_dir,
                        verify,
                        limiter,
                        state,
                        max_bytes,
                        skip_done_without_validator,
                    )
                except Exception as exn:
                    state.mark_error(u0, "unknown", exn)
                    LOG.warning("sitemap item: %s", exn)

            with ThreadPoolExecutor(max_workers=conc) as ex:
                for _ in ex.map(_one_sm, to_fetch):
                    pass
        else:
            for u in state.pending_urls(max_pages):
                u, _ = urldefrag(u)
                if u.lower().split("?", 1)[0].endswith(".pdf"):
                    try:
                        fetch_pdf(
                            s,
                            u,
                            out_dir,
                            verify,
                            limiter,
                            state,
                            max_bytes,
                            skip_done_without_validator,
                        )
                    except Exception as ex:
                        state.mark_error(u, "pdf", ex)
                        LOG.warning("pdf %s: %s", u, ex)
                elif not _is_skippable_path(urlparse(u).path or ""):
                    try:
                        fetch_html(
                            s,
                            base,
                            u,
                            out_dir,
                            verify,
                            limiter,
                            state,
                            max_bytes,
                            skip_done_without_validator,
                        )
                    except Exception as ex:
                        state.mark_error(u, "html", ex)
                        LOG.warning("html %s: %s", u, ex)
        LOG.info("state summary: %s", state.summary())
        LOG.info("done")
        return 0
    finally:
        elapsed = time.monotonic() - started_at
        try:
            summary = state.summary()
        except Exception:
            summary = {}
        LOG.warning(
            "ingest done elapsed=%.1fs (%dm%02ds) state=%s",
            elapsed,
            int(elapsed) // 60,
            int(elapsed) % 60,
            summary,
        )
        state.finish_run(run_id)
        state.close()


if __name__ == "__main__":
    raise SystemExit(run())
