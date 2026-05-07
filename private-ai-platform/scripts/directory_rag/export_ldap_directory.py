#!/usr/bin/env python3
"""
Export directory entries from LDAP/LDAPS to UTF-8 .txt for an Open WebUI knowledge base.

- Optional filter by security group (memberOf).
- Only enabled user accounts (no ACCOUNTDISABLE bit in userAccountControl).
- Output blocks use a compact, readable text format for later RAG chunking.

Requires: ldap3 (see requirements.txt in this folder or intranet_rag/requirements.txt).
"""
from __future__ import annotations

import argparse
import os
import ssl
from typing import Any

try:
    from ldap3 import ALL, SUBTREE, Connection, Server, Tls
    from ldap3.core.exceptions import LDAPException
    from ldap3.utils.conv import escape_filter_chars
except ImportError as e:
    raise SystemExit("missing dependency ldap3; pip install ldap3") from e


def _env(name: str, default: str | None = None) -> str:
    v = os.environ.get(name, "").strip()
    if v:
        return v
    if default is not None:
        return default
    raise SystemExit(f"missing required env: {name}")


def _env_bool01(name: str, default: bool) -> bool:
    raw = (os.environ.get(name) or "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "y", "on")


def _parse_uri(uri: str) -> tuple[str, int, bool]:
    u = uri.strip()
    if u.startswith("ldaps://"):
        rest = u[len("ldaps://") :]
        use_ssl = True
        default_port = 636
    elif u.startswith("ldap://"):
        rest = u[len("ldap://") :]
        use_ssl = False
        default_port = 389
    else:
        raise SystemExit("LDAP_URI must start with ldap:// or ldaps://")

    if "/" in rest:
        rest = rest.split("/", 1)[0]
    if ":" in rest:
        host, port_s = rest.rsplit(":", 1)
        port = int(port_s, 10)
    else:
        host, port = rest, default_port
    if not host:
        raise SystemExit("LDAP_URI host is empty")
    return host, port, use_ssl


def _connect() -> Connection:
    uri = _env("LDAP_URI")
    bind_dn = _env("LDAP_BIND_DN")
    bind_pw = _env("LDAP_BIND_PW", "")
    insecure = _env_bool01("LDAP_INSECURE_TLS", False)
    ca = (os.environ.get("LDAP_CA_BUNDLE") or "").strip()
    seclevel = (os.environ.get("LDAP_TLS_SECLEVEL") or "").strip()

    host, port, use_ssl = _parse_uri(uri)
    ciphers_str = f"DEFAULT:@SECLEVEL={seclevel}" if seclevel else None
    tls = Tls(
        ca_certs_file=ca if ca else None,
        validate=ssl.CERT_NONE if insecure else ssl.CERT_REQUIRED,
        ciphers=ciphers_str,
    )
    server = Server(host, port=port, use_ssl=use_ssl, get_info=ALL, tls=tls)
    return Connection(server, user=bind_dn, password=bind_pw, auto_bind=True)


def _discover_group_dn(conn: Connection, base: str, group_name: str) -> str:
    esc = escape_filter_chars(group_name)
    filt = f"(&(objectClass=group)(|(cn={esc})(name={esc})))"
    conn.search(base, filt, SUBTREE, attributes=["distinguishedName", "cn", "name"])
    if not conn.entries:
        raise SystemExit(f"no group found for name/cn={group_name!r} under {base!r}")
    if len(conn.entries) > 1:
        dns = [str(e.entry_dn) for e in conn.entries]
        raise SystemExit(f"multiple groups matched; refine LDAP_GROUP_NAME. Found: {dns[:10]}")
    return str(conn.entries[0].entry_dn)


def _manager_display(conn: Connection, base: str, dn: str, cache: dict[str, str]) -> str:
    if not dn:
        return ""
    if dn in cache:
        return cache[dn]
    esc_dn = escape_filter_chars(dn)
    filt = f"(distinguishedName={esc_dn})"
    conn.search(base, filt, SUBTREE, attributes=["displayName", "cn"])
    if conn.entries:
        e = conn.entries[0]
        disp = str(e.displayName.value) if e.displayName else ""
        cn = str(e.cn.value) if e.cn else ""
        out = disp or cn or dn
    else:
        out = dn
    cache[dn] = out
    return out


def _user_filter(group_dn: str, sam: str | None, upn: str | None) -> str:
    esc_g = escape_filter_chars(group_dn)
    core_inner = "".join(
        [
            "(&(objectClass=user)(objectCategory=person))",
            "(!(userAccountControl:1.2.840.113556.1.4.803:=2))",
            f"(memberOf={esc_g})",
        ]
    )
    if sam and upn:
        esc_s = escape_filter_chars(sam)
        esc_u = escape_filter_chars(upn)
        return f"(&{core_inner}(|(sAMAccountName={esc_s})(userPrincipalName={esc_u})))"
    if sam:
        return f"(&{core_inner}(sAMAccountName={escape_filter_chars(sam)}))"
    if upn:
        return f"(&{core_inner}(userPrincipalName={escape_filter_chars(upn)}))"
    return f"(&{core_inner})"


def _attrs() -> list[str]:
    return [
        "sAMAccountName",
        "userPrincipalName",
        "displayName",
        "givenName",
        "sn",
        "mail",
        "department",
        "title",
        "company",
        "physicalDeliveryOfficeName",
        "telephoneNumber",
        "mobile",
        "streetAddress",
        "l",
        "st",
        "postalCode",
        "manager",
        "userAccountControl",
    ]


def _first_str(raw: dict[str, Any], key: str) -> str:
    v = raw.get(key)
    if v is None:
        return ""
    if isinstance(v, (list, tuple)):
        if not v:
            return ""
        v = v[0]
    return str(v).strip()


def _lines_from_raw(
    raw: dict[str, Any],
    manager_cache: dict[str, str],
    conn: Connection,
    base: str,
) -> list[str]:
    sam = _first_str(raw, "sAMAccountName")
    upn = _first_str(raw, "userPrincipalName")
    disp = _first_str(raw, "displayName")
    gn = _first_str(raw, "givenName")
    sn = _first_str(raw, "sn")
    mail = _first_str(raw, "mail")
    dept = _first_str(raw, "department")
    title = _first_str(raw, "title")
    company = _first_str(raw, "company")
    office = _first_str(raw, "physicalDeliveryOfficeName")
    tel = _first_str(raw, "telephoneNumber")
    mob = _first_str(raw, "mobile")
    street = _first_str(raw, "streetAddress")
    city = _first_str(raw, "l")
    region = _first_str(raw, "st")
    plz = _first_str(raw, "postalCode")
    mgr_dn = _first_str(raw, "manager")
    uac = _first_str(raw, "userAccountControl")

    mgr_txt = _manager_display(conn, base, mgr_dn, manager_cache) if mgr_dn else ""

    return [
        "### DIRECTORY_ENTRY",
        f"Loginname: {sam}",
        f"UPN: {upn}",
        f"Vorname: {gn}",
        f"Nachname: {sn}",
        f"Anzeigename: {disp}",
        f"EMail: {mail}",
        f"Telefon_Buero: {tel}",
        f"Mobil_Handy: {mob}",
        f"Buero: {office}",
        f"Strasse: {street}",
        f"Ort: {city}",
        f"PLZ: {plz}",
        f"Bundesland_Region: {region}",
        f"Organisation: {company}",
        f"Abteilung: {dept}",
        f"Funktion: {title}",
        f"Vorgesetzter: {mgr_txt}",
        f"userAccountControl: {uac}",
        "---",
    ]


def cmd_discover_group() -> int:
    base = _env("LDAP_BASE_DN")
    gname = os.environ.get("LDAP_GROUP_NAME", "AI Platform Users").strip() or "AI Platform Users"
    try:
        conn = _connect()
        dn = _discover_group_dn(conn, base, gname)
        print(dn)
        return 0
    except LDAPException as e:
        raise SystemExit(f"LDAP error: {e}") from e


def cmd_export(limit: int | None, sam: str | None, upn: str | None, *, single_file: bool = False) -> int:
    base = _env("LDAP_BASE_DN")
    group_dn = (os.environ.get("LDAP_GROUP_DN") or "").strip()
    if not group_dn:
        raise SystemExit("set LDAP_GROUP_DN or run discover-group first")
    out_dir = _env("DIRECTORY_OUTPUT_DIR", "/opt/private-ai-platform/data/directory-rag")
    os.makedirs(out_dir, exist_ok=True)

    filt = _user_filter(group_dn, sam, upn)
    attrs = _attrs()

    try:
        conn = _connect()
    except LDAPException as e:
        raise SystemExit(f"LDAP bind error: {e}") from e

    search_kw: dict[str, Any] = {}
    if limit is not None and not sam and not upn:
        search_kw["size_limit"] = limit

    if not conn.search(base, filt, SUBTREE, attributes=attrs, **search_kw):
        raise SystemExit(f"LDAP search failed: {conn.result}")

    manager_cache: dict[str, str] = {}
    records: list[tuple[str, str, str, str, list[str]]] = []

    for entry in conn.entries:
        raw = entry.entry_attributes_as_dict
        sam_val = _first_str(raw, "sAMAccountName")
        sn = _first_str(raw, "sn").lower()
        gn = _first_str(raw, "givenName").lower()
        upn_s = _first_str(raw, "userPrincipalName").lower()
        lines = _lines_from_raw(raw, manager_cache, conn, base)
        records.append((sn, gn, upn_s, sam_val, lines))

    records.sort(key=lambda t: (t[0], t[1], t[2]))
    if limit is not None and (sam or upn):
        records = records[: max(0, limit)]

    if single_file:
        out_name = (
            os.environ.get("DIRECTORY_EXPORT_FILENAME", "directory-export.txt").strip()
            or "directory-export.txt"
        )
        out_path = os.path.join(out_dir, out_name)
        with open(out_path, "w", encoding="utf-8", newline="\n") as f:
            f.write("# LDAP-Verzeichnisexport fuer RAG. Filter: aktivierte Benutzer und optional Gruppenfilter.\n\n")
            for _, _, _, _, lines in records:
                f.write("\n".join(lines))
                f.write("\n\n")
        print(f"wrote {out_path} records={len(records)}")
    else:
        written = 0
        for _, _, _, sam_val, lines in records:
            fname = f"{sam_val}.txt" if sam_val else None
            if not fname:
                continue
            fpath = os.path.join(out_dir, fname)
            with open(fpath, "w", encoding="utf-8", newline="\n") as f:
                f.write("\n".join(lines))
                f.write("\n")
            written += 1
        print(f"wrote {written} files to {out_dir}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="LDAP-Verzeichnis -> DIRECTORY_ENTRY TXT fuer Open WebUI.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("discover-group", help="Print distinguishedName of LDAP_GROUP_NAME under LDAP_BASE_DN.")

    p_exp = sub.add_parser("export", help="Export users to DIRECTORY_OUTPUT_DIR (one .txt per entry, default).")
    p_exp.add_argument("--limit", type=int, default=None, help="Max number of users after sort (dry-run).")
    p_exp.add_argument("--sam", default=None, help="Restrict to sAMAccountName.")
    p_exp.add_argument("--upn", default=None, help="Restrict to userPrincipalName.")
    p_exp.add_argument("--single-file", action="store_true", help="Write all records into one file (legacy; worse for RAG chunking).")

    args = ap.parse_args()
    if args.cmd == "discover-group":
        return cmd_discover_group()
    if args.cmd == "export":
        return cmd_export(args.limit, args.sam, args.upn, single_file=args.single_file)
    raise SystemExit(f"unknown cmd: {args.cmd}")


if __name__ == "__main__":
    raise SystemExit(main())
