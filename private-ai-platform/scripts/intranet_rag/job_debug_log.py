from __future__ import annotations

import logging
import os
from datetime import datetime


def _resolve_path(out_dir: str) -> str:
    custom = (os.environ.get("INTRANET_DEBUG_LOG") or "").strip()
    if custom and custom not in ("0", "off", "false", "no"):
        return custom
    return os.path.join(out_dir, "debug.txt")


def install_debug_file(out_dir: str, *, truncate: bool, job_label: str) -> str | None:
    if (os.environ.get("INTRANET_DEBUG_LOG") or "").strip() in (
        "0",
        "off",
        "false",
        "no",
    ):
        return None
    path = _resolve_path(out_dir)
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    mode = "w" if truncate else "a"
    ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    with open(path, mode, encoding="utf-8") as f:
        f.write(f"=== {job_label} {ts} ===\n")
    fh = logging.FileHandler(path, mode="a", encoding="utf-8")
    fh.setLevel(logging.WARNING)
    fh.setFormatter(
        logging.Formatter(
            f"%(asctime)s {job_label} %(name)s %(levelname)s %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
    )
    root = logging.getLogger()
    root.addHandler(fh)
    logging.captureWarnings(True)
    try:
        logging.getLogger("py.warnings").setLevel(logging.WARNING)
    except (ValueError, AttributeError):
        pass
    return path
