# Skript f�r silent Ausf�hrung ohne Benutzereingaben

# Pfad zur ISO-Datei
$isoPath = "C:\edv\upgrade\windows11.iso"

# Pfad zur Hash-Datei
$hashFilePath = "C:\edv\upgrade\ISOHASH.txt"

# Pfad zur Logdatei
$logPath = "C:\edv\upgradelogs\IsoCheck.log"

# Funktion zum Schreiben in die Logdatei
function Write-Log {
    param (
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logMessage -ErrorAction Stop
    }
    catch {
        # Keine Konsolenausgabe, da silent
        # Fehler wird nur in Logdatei geschrieben, falls m�glich
    }
}

# Sicherstellen, dass der Log-Ordner existiert
$logDir = Split-Path -Path $logPath -Parent
try {
    if (-not (Test-Path -Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Log "Log-Verzeichnis erstellt: $logDir"
    }
}
catch {
    Write-Log "FEHLER: Konnte Log-Verzeichnis nicht erstellen ($logDir): $_"
    exit 0
}

# Pr�fen, ob die Hash-Datei existiert
if (-not (Test-Path -Path $hashFilePath)) {
    Write-Log "FEHLER: Hash-Datei $hashFilePath nicht gefunden. Lade ISO und HASH...."
    exit 0
}

# Erwarteten SHA-256-Hash aus Datei lesen
try {
    $expectedHash = (Get-Content -Path $hashFilePath -Raw -ErrorAction Stop).Trim()
    Write-Log "Gelesener Hash: $expectedHash"
    if (-not $expectedHash -or $expectedHash -notmatch '^[0-9A-Fa-f]{64}$') {
        Write-Log "FEHLER: Ung�ltiger oder leerer Hash in $hashFilePath."
        exit 0
    }
}
catch {
    Write-Log "FEHLER: Konnte Hash-Datei nicht lesen ($hashFilePath): $_"
    exit 0
}

# Pr�fen, ob die ISO-Datei existiert
if (Test-Path -Path $isoPath) {
    Write-Log "ISO-Datei gefunden: $isoPath. Pr�fe SHA-256-Hash..."
    try {
        # SHA-256-Hash der Datei berechnen
        $hash = Get-FileHash -Path $isoPath -Algorithm SHA256 -ErrorAction Stop
        $calculatedHash = $hash.Hash
        Write-Log "Berechneter Hash: $calculatedHash"

        # Vergleiche berechneten Hash mit erwartetem Hash
        if ($calculatedHash -eq $expectedHash) {
            Write-Log "SHA-256-Hash stimmt �berein ($calculatedHash). ISO-Datei ist intakt."
            exit 0
        }
        else {
            Write-Log "SHA-256-Hash stimmt nicht �berein (erwartet: $expectedHash, berechnet: $calculatedHash). ISO-Datei ist fehlerhaft. L�sche Datei..."
            Remove-Item -Path $isoPath -Force -ErrorAction Stop
            Write-Log "ISO-Datei wurde erfolgreich gel�scht."
            Write-Log "Lade ISO...."
            exit 0
        }
    }
    catch {
        Write-Log "FEHLER: Fehler beim Pr�fen oder L�schen der ISO-Datei ($isoPath): $_"
        exit 0
    }
}
else {
    Write-Log "Keine ISO-Datei unter $isoPath gefunden. Lade ISO und HASH...."
    exit 0
}
