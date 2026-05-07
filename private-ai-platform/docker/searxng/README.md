# SearXNG fuer Open WebUI

Open WebUI erwartet bei SearXNG eine JSON-faehige Antwort. Nach dem ersten Start erzeugt der Container unter `docker/searxng/` seine Konfigurationsdateien. Anschliessend sollte in `settings.yml` das Ausgabeformat ergaenzt werden:

```yaml
search:
  formats:
    - html
    - json
```

Danach den Dienst neu starten oder den Stack erneut anwenden.

In Open WebUI wird als Such-URL eingetragen:

`http://searxng:8080/search`

Wichtig: kein `?q=` anhaengen.
