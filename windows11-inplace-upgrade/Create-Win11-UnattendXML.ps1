# Skript zum Erstellen der unattend.xml mit dynamischen Werten
# Silent-Modus, Protokollierung in C:\EDV\upgradelogs\unattend.log, kein Abbruch außer bei kritischen Fehlern
param (
    [string]$extractDir = "C:\Win11Upgrade",
    [string]$answerFilePath = "C:\Win11Upgrade\unattend.xml"
)

$logFile = "C:\EDV\upgradelogs\unattend.log"
$logDir = Split-Path -Path $logFile -Parent

# Versuch, den Log-Ordner zu erstellen und erste Nachricht zu schreiben
try {
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Skriptstart - Log-Datei initialisiert"
} catch {
    # Falls die Log-Datei nicht geschrieben werden kann, versuche eine temporäre Datei
    $tempLogFile = "$env:TEMP\unattend_error.log"
    try {
        Add-Content -Path $tempLogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): FEHLER: Haupt-Log-Datei ($logFile) konnte nicht erstellt werden: $_"
        Add-Content -Path $tempLogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Verwende temporäre Log-Datei: $tempLogFile"
        $logFile = $tempLogFile
    } catch {
        # Letzter Ausweg: Fehler an die Konsole ausgeben (nur als Fallback)
        Write-Host "Kritischer Fehler: Konnte keine Log-Datei erstellen. Details: $_"
        exit 1
    }
}

# Admin-Check
try {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): FEHLER: Skript erfordert Administratorrechte"
        exit 1
    }
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Admin-Check erfolgreich"
} catch {
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): FEHLER: Admin-Check fehlgeschlagen: $_"
    exit 1
}

# 1. Alle Datenträger und Partitionen auslesen, Windows-Partition basierend auf C:\Windows identifizieren
$diskId = $null
$partitionId = $null
try {
    $allDisks = Get-Disk -ErrorAction Stop
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Gefundene Datenträger: $($allDisks | ForEach-Object { 'DiskID = ' + $_.Number + ', Größe = ' + ($_.Size / 1GB) + ' GB' })"

    foreach ($disk in $allDisks) {
        $partitions = Get-Partition -DiskNumber $disk.Number -ErrorAction Stop
        $partitionDetails = $partitions | ForEach-Object { "$($_.PartitionNumber): $($_.Type) ($($_.Size / 1GB) GB), Laufwerksbuchstabe = $($_.DriveLetter)" }
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Partitionen auf DiskID $($disk.Number): $partitionDetails"

        foreach ($partition in $partitions) {
            $driveLetter = $partition.DriveLetter
            if ($driveLetter) {
                $windowsPath = "$($driveLetter):\Windows"
                try {
                    if (Test-Path $windowsPath -ErrorAction Stop) {
                        $diskId = $disk.Number
                        $partitionId = $partition.PartitionNumber
                        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Windows-Partition gefunden: DiskID = $diskId, PartitionID = $partitionId (Größe: $($partition.Size / 1GB) GB, Laufwerksbuchstabe = $driveLetter)"
                        break
                    }
                } catch {
                    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): WARNUNG: Test-Path für $windowsPath fehlgeschlagen: $_"
                }
            }
        }
        if ($diskId -ne $null) { break }
    }

    if ($diskId -eq $null -or $partitionId -eq $null) {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): FEHLER: Keine Partition mit C:\Windows gefunden"
        exit 1
    }
} catch {
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): FEHLER: Datenträger- oder Partitionsauswahl fehlgeschlagen: $_"
    exit 1
}
# 2. Image-Index aus install.wim auslesen, basierend auf der aktuellen Windows-Edition
$imageIndex = 5  # Standardwert
try {
    $wimPath = "$extractDir\sources\install.wim"
    if (-not (Test-Path $wimPath)) {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): FEHLER: install.wim nicht gefunden unter $wimPath"
        exit 1
    }

    # Aktuelle Windows-Edition ermitteln
    $currentEdition = (Get-WmiObject -Class Win32_OperatingSystem).Caption
    $targetEdition = if ($currentEdition -like "*Home*") {
        "Windows 11 Home"
    } elseif ($currentEdition -like "*Pro*") {
        "Windows 11 Pro"
    } elseif ($currentEdition -like "*Enterprise*") {
        "Windows 11 Enterprise"
    } elseif ($currentEdition -like "*Education*") {
        "Windows 11 Education"
    } else {
        "Windows 11 Pro"  # Fallback auf Pro, wenn die Edition unklar ist
    }
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Aktuelle Edition: $currentEdition, Ziel-Edition: $targetEdition"

    # Images aus der WIM-Datei durchsuchen
    $images = Get-WindowsImage -ImagePath $wimPath
    foreach ($image in $images) {
        if ($image.ImageName -like "*$targetEdition*") {
            $imageIndex = $image.ImageIndex
            Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Edition gefunden: $($image.ImageName) mit ImageIndex = $imageIndex"
            break
        }
    }

    if ($imageIndex -eq 1) {
        Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): WARNUNG: Kein $targetEdition Image gefunden, verwende Standard-ImageIndex 1"
    }
} catch {
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): WARNUNG: Image-Index-Ermittlung fehlgeschlagen, verwende Standard-ImageIndex 1: $_"
    # Skript fährt fort
}

# 3. unattend.xml erstellen
$answerFileContent = @"
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ComplianceCheck>
        <DisplayReport>Never</DisplayReport>
      </ComplianceCheck>
      <Diagnostics>
        <OptIn>false</OptIn>
      </Diagnostics>
      <DynamicUpdate>
        <Enable>true</Enable>
        <WillShowUI>OnError</WillShowUI>
      </DynamicUpdate>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData>
              <Key>/IMAGE/INDEX</Key>
              <Value>$imageIndex</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>$diskId</DiskID>
            <PartitionID>$partitionId</PartitionID>
          </InstallTo>
          <WillShowUI>OnError</WillShowUI>
          <InstallToAvailablePartition>true</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
      </UserData>
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>2</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>3</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>4</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassCPUCheck /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>5</Order>
          <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassStorageCheck /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>6</Order>
          <Path>reg add HKLM\SYSTEM\Setup\MoSetup /v AllowUpgradesWithUnsupportedTPMorCPU /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>7</Order>
          <Path>reg add HKLM\SYSTEM\Setup\MoSetup /v SkipMigrationPlugins /d 1 /t reg_dword /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
</unattend>
"@

# 4. Datei speichern
try {
    Set-Content -Path $answerFilePath -Value $answerFileContent -Force -ErrorAction Stop
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): unattend.xml erfolgreich erstellt unter $answerFilePath"
} catch {
    Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): WARNUNG: Erstellung von unattend.xml fehlgeschlagen: $_"
    # Skript fährt fort
}

# Skriptende
Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Skript erfolgreich abgeschlossen"
