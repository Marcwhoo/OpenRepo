# Directory-RAG

Exportiert Eintraege aus einem AD-/LDAP-Verzeichnis als `.txt` (eine Datei pro Person), damit sie in eine Open-WebUI-Knowledge-Base gepusht werden koennen.

## Was es macht

`export_ldap_directory.py` filtert auf `objectClass=user` und `objectCategory=person`, ueberspringt deaktivierte Konten (`userAccountControl`-Bit) und filtert optional auf Mitgliedschaft in einer Sicherheitsgruppe (`LDAP_GROUP_DN`). Pro Eintrag wird ein `### DIRECTORY_ENTRY`-Block geschrieben mit Loginname, UPN, Vorname, Nachname, Anzeigename, EMail, Telefon, Mobil, Buero, Adresse, Organisation, Abteilung, Funktion und Vorgesetztem.

## Aufbau

```bash
python3 -m venv venv
./venv/bin/pip install -r requirements.txt
cp env.example .env           # LDAP_URI, BindDN, BindPW, BaseDN
chmod 600 .env

# DN der Zielgruppe einmalig ermitteln
./venv/bin/python export_ldap_directory.py discover-group

# Ersten Lauf testen
./venv/bin/python export_ldap_directory.py export --limit 10

# Vollexport
./venv/bin/python export_ldap_directory.py export
```

## Push in Open WebUI

Die erzeugten `.txt` werden mit dem Push-Skript aus `intranet_rag/` in eine zweite Knowledge Base hochgeladen:

```bash
../intranet_rag/push_to_openwebui_kb.py \
  --knowledge-id $OPENWEBUI_KNOWLEDGE_ID_DIRECTORY \
  --sync-dir $DIRECTORY_OUTPUT_DIR \
  --state-file $DIRECTORY_OUTPUT_DIR/.openwebui-state.json
```

Bei Nutzung der systemd-Timer aus `provision/` liegen alle Variablen in `/opt/private-ai-platform/scripts/intranet_rag/.env`.
