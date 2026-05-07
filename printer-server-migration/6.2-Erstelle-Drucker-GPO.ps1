param(
    [Parameter(Mandatory=$false)]
    [string]$ComputerName = "<PRINT-SERVER-1>-01",
    
    [Parameter(Mandatory=$false)]
    [string]$GPOName = "Drucker - <PRINT-SERVER-1>-01 - Alle Drucker",
    
    [Parameter(Mandatory=$false)]
    [string]$OUPath = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$LinkGPO = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckSecurityGroups = $false
)

Write-Host "=== Erstelle GPO für Drucker mit Item Level Targeting ===" -ForegroundColor Cyan
Write-Host "Server: $ComputerName" -ForegroundColor Yellow
Write-Host "GPO-Name: $GPOName" -ForegroundColor Yellow
Write-Host ""

# Prüfe ob Module verfügbar sind
if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
    Write-Host "FEHLER: GroupPolicy-Modul nicht gefunden." -ForegroundColor Red
    Write-Host "Bitte installieren Sie es mit: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Host "FEHLER: ActiveDirectory-Modul nicht gefunden." -ForegroundColor Red
    Write-Host "Bitte installieren Sie es mit: Install-WindowsFeature RSAT-AD-PowerShell" -ForegroundColor Yellow
    exit 1
}

Import-Module GroupPolicy -ErrorAction Stop
Import-Module ActiveDirectory -ErrorAction Stop

# Funktion zum Bereinigen von Gruppennamen (entfernt ungültige Zeichen)
function Remove-InvalidGroupCharacters {
    param([string]$GroupName)
    
    if ([string]::IsNullOrEmpty($GroupName)) {
        return $GroupName
    }
    
    # Ersetze ungültige Zeichen für AD-Gruppennamen
    # Ungültige Zeichen: / \ [ ] : ; | = , + * ? < > ( )
    $cleaned = $GroupName -replace '[\/\\\[\]:;\|=,\+\*\?<>\(\)]', '-'
    
    # Entferne mehrfache Bindestriche
    $cleaned = $cleaned -replace '-+', '-'
    
    # Entferne führende/abschließende Bindestriche
    $cleaned = $cleaned.Trim('-')
    
    # Kürze auf max. 64 Zeichen (AD-Limit)
    if ($cleaned.Length -gt 64) {
        $cleaned = $cleaned.Substring(0, 64).TrimEnd('-')
    }
    
    return $cleaned
}

# Hole alle Drucker vom Server
Write-Host "Lade Drucker vom Server..." -ForegroundColor Yellow
try {
    $printers = Get-Printer -ComputerName $ComputerName -ErrorAction Stop
    Write-Host "Gefunden: $($printers.Count) Drucker" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "FEHLER: Konnte Drucker nicht laden: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($printers.Count -eq 0) {
    Write-Host "FEHLER: Keine Drucker gefunden!" -ForegroundColor Red
    exit 1
}

# Funktion zum Abrufen der Sicherheitsgruppen eines einzelnen Druckers (einzeln für bessere Performance)
function Get-PrinterSecurityGroups {
    param(
        [string]$ComputerName,
        [string]$PrinterName
    )
    
    $groups = @()
    try {
        $wmiPrinter = Get-WmiObject -Class Win32_Printer -ComputerName $ComputerName -Filter "Name='$($PrinterName.Replace("'", "''"))'" -ErrorAction SilentlyContinue
        
        if (-not $wmiPrinter) {
            return $groups
        }
        
        $sd = $wmiPrinter.GetSecurityDescriptor()
        if ($sd.ReturnValue -ne 0) {
            return $groups
        }
        
        $dacl = $sd.Descriptor.DACL
        
        foreach ($ace in $dacl) {
            $trustee = $ace.Trustee
            $identity = $trustee.Name
            $domain = $trustee.Domain
            $sidString = $trustee.SIDString
            
            # Nur Gruppen berücksichtigen (nicht einzelne Benutzer)
            if ($sidString -and $identity) {
                try {
                    # Prüfe ob es eine Gruppe ist (nicht ein Benutzer)
                    $adObject = Get-ADObject -Filter "SID -eq '$sidString'" -Properties ObjectClass -ErrorAction SilentlyContinue
                    if ($adObject -and $adObject.ObjectClass -eq 'group') {
                        $fullName = if ($domain) { "$domain\$identity" } else { $identity }
                        $groups += [PSCustomObject]@{
                            Name = $identity
                            FullName = $fullName
                            SID = $sidString
                            Domain = $domain
                        }
                    }
                } catch {
                    # Überspringen wenn Objekt nicht gefunden
                }
            }
        }
    } catch {
        # Fehler beim Abrufen der Berechtigungen
    }
    
    return $groups
}

# Liste für Drucker, bei denen die Sicherheitsgruppe nicht gefunden wurde
$printersWithoutGroup = @()

# Erstelle oder hole GPO
Write-Host "Erstelle/Prüfe GPO: $GPOName" -ForegroundColor Yellow
try {
    $gpo = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
    
    if ($gpo) {
        Write-Host "GPO bereits vorhanden: $GPOName" -ForegroundColor Yellow
        $gpoCreated = $false
    } else {
        $description = "Automatisch erstellt: Enthält alle Drucker von $ComputerName mit Item Level Targeting basierend auf Sicherheitsgruppen"
        $gpo = New-GPO -Name $GPOName -Comment $description -ErrorAction Stop
        Write-Host "GPO erstellt: $GPOName" -ForegroundColor Green
        $gpoCreated = $true
    }
} catch {
    Write-Host "FEHLER: Konnte GPO nicht erstellen: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Hole GPO-Pfad für Registry-Einstellungen
$gpoPath = "\\$((Get-ADDomain).DNSRoot)\SYSVOL\$((Get-ADDomain).DNSRoot)\Policies\{$($gpo.Id)}\"

# Konfiguriere Drucker-Einstellungen
Write-Host ""
Write-Host "Konfiguriere Drucker in GPO..." -ForegroundColor Yellow

# Hole GPO-Pfad für Registry-Einstellungen (wird später verwendet)
$gpoPath = "\\$((Get-ADDomain).DNSRoot)\SYSVOL\$((Get-ADDomain).DNSRoot)\Policies\{$($gpo.Id)}\"
$preferencesPath = Join-Path $gpoPath "User\Preferences\Printers"
$printersXmlPath = Join-Path $preferencesPath "Printers.xml"

# Erstelle Verzeichnis falls nicht vorhanden
if (-not (Test-Path $preferencesPath)) {
    New-Item -ItemType Directory -Path $preferencesPath -Force | Out-Null
}

# Lade XML-Datei EINMAL am Anfang (nicht in jeder Iteration!)
Write-Host "Lade GPO-XML-Datei..." -ForegroundColor Yellow
if (Test-Path $printersXmlPath) {
    try {
        [xml]$printersXml = Get-Content $printersXmlPath -Encoding UTF8
        # Prüfe ob Root-Element existiert
        if (-not $printersXml.DocumentElement) {
            throw "XML-Datei hat kein Root-Element"
        }
        Write-Host "  XML-Datei erfolgreich geladen" -ForegroundColor Green
    } catch {
        Write-Host "  [WARNUNG] Konnte XML nicht laden, erstelle neue: $($_.Exception.Message)" -ForegroundColor Yellow
        # Erstelle neue GPP XML-Struktur
        $printersXml = New-Object System.Xml.XmlDocument
        $xmlDeclaration = $printersXml.CreateXmlDeclaration("1.0", "UTF-8", "yes")
        $printersXml.AppendChild($xmlDeclaration) | Out-Null
        
        $root = $printersXml.CreateElement("Printers")
        $root.SetAttribute("clsid", "{1F577D12-3D1B-471e-A1B7-060317597B9C}")
        $printersXml.AppendChild($root) | Out-Null
        Write-Host "  Neue XML-Struktur erstellt" -ForegroundColor Yellow
    }
} else {
    # Erstelle neue GPP XML-Struktur
    $printersXml = New-Object System.Xml.XmlDocument
    $xmlDeclaration = $printersXml.CreateXmlDeclaration("1.0", "UTF-8", "yes")
    $printersXml.AppendChild($xmlDeclaration) | Out-Null
    
    $root = $printersXml.CreateElement("Printers")
    $root.SetAttribute("clsid", "{1F577D12-3D1B-471e-A1B7-060317597B9C}")
    $printersXml.AppendChild($root) | Out-Null
    Write-Host "  Neue XML-Struktur erstellt" -ForegroundColor Yellow
}

# Hole Domain-Name EINMAL vor der Schleife
$domainName = (Get-ADDomain).DNSRoot

$configuredCount = 0
$errorCount = 0
$skippedCount = 0

$printerIndex = 0
foreach ($printer in $printers) {
    $printerIndex++
    $printerName = $printer.Name
    $printerShareName = $printer.ShareName
    
    Write-Host "[$printerIndex/$($printers.Count)] $printerName" -ForegroundColor Cyan
    
    # Prüfe ob Drucker geteilt ist
    if (-not $printerShareName) {
        Write-Host "  [ÜBERSPRUNGEN] Drucker ist nicht geteilt" -ForegroundColor Yellow
        $skippedCount++
        continue
    }
    
    # Prüfe ob Sicherheitsgruppe existiert
    $groupName = $printerName
    $group = $null
    
    # Versuche mit Druckernamen zu suchen (Server-Abfrage wird später für problematische Drucker gemacht)
    if (-not $group) {
        try {
            # 1. Versuche exakt mit Druckernamen
            $group = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
            
            # 2. Falls nicht gefunden, versuche mit bereinigtem Namen
            if (-not $group) {
                $cleanedGroupName = Remove-InvalidGroupCharacters -GroupName $groupName
                if ($cleanedGroupName -ne $groupName) {
                    $group = Get-ADGroup -Filter "Name -eq '$cleanedGroupName'" -ErrorAction SilentlyContinue
                    if ($group) {
                        Write-Host "  [INFO] Gruppe gefunden mit bereinigtem Namen: $cleanedGroupName" -ForegroundColor Yellow
                        $groupName = $cleanedGroupName
                    }
                }
            }
            
        } catch {
            Write-Host "  [FEHLER] Konnte Sicherheitsgruppe nicht prüfen: $($_.Exception.Message)" -ForegroundColor Red
            $errorCount++
            continue
        }
    }
    
    if (-not $group) {
        Write-Host "  [FEHLER] Sicherheitsgruppe nicht gefunden: $groupName" -ForegroundColor Red
        # Speichere diesen Drucker für spätere Server-Abfrage
        $printersWithoutGroup += [PSCustomObject]@{
            PrinterName = $printerName
            PrinterShareName = $printerShareName
            ExpectedGroupName = $groupName
        }
        $errorCount++
        continue
    }
    
    # Erstelle UNC-Pfad zum Drucker
    $printerUNC = "\\$ComputerName\$printerShareName"
    
    try {
        # Prüfe ob Drucker bereits vorhanden ist (anhand des UNC-Pfads in Properties)
        $existingPrinter = $printersXml.SelectSingleNode("//Properties[@path='$printerUNC']")
        $existingSharedPrinter = if ($existingPrinter) { $existingPrinter.ParentNode } else { $null }
        
        if (-not $existingSharedPrinter) {
            # Erstelle SharedPrinter-Element im GPP-Format
            $printerElement = $printersXml.CreateElement("SharedPrinter")
            $printerElement.SetAttribute("clsid", "{9A5E9697-9095-436d-A0EE-4D128FDFBCE5}")  # Korrekte CLSID für SharedPrinter
            $printerElement.SetAttribute("name", $printerName)
            $printerElement.SetAttribute("status", $printerName)
            $printerElement.SetAttribute("image", "2")
            $printerElement.SetAttribute("changed", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
            $newGuid = [guid]::NewGuid().ToString().ToUpper()
            $printerElement.SetAttribute("uid", "{$newGuid}")
            $printerElement.SetAttribute("userContext", "1")
            $printerElement.SetAttribute("removePolicy", "1")  # 1 = Drucker entfernen wenn nicht mehr angewendet
            $printerElement.SetAttribute("bypassErrors", "1")  # Wichtig für GPP
            
            # Properties-Element (angepasst an funktionierende GPOs)
            $propertiesElement = $printersXml.CreateElement("Properties")
            $propertiesElement.SetAttribute("action", "C")  # C = Create (wie in funktionierenden GPOs)
            $propertiesElement.SetAttribute("path", $printerUNC)
            $propertiesElement.SetAttribute("default", "0")
            $propertiesElement.SetAttribute("location", "")
            $propertiesElement.SetAttribute("comment", "")
            $propertiesElement.SetAttribute("skipLocal", "0")  # Wie in funktionierenden GPOs
            $propertiesElement.SetAttribute("deleteAll", "0")
            $propertiesElement.SetAttribute("persistent", "0")  # Wie in funktionierenden GPOs
            $propertiesElement.SetAttribute("deleteMaps", "1")  # 1 = Druckerzuordnungen löschen wenn Drucker entfernt wird
            $propertiesElement.SetAttribute("port", "")
            $printerElement.AppendChild($propertiesElement) | Out-Null
            
            # Filters-Element für Item Level Targeting (korrekte Struktur)
            $filtersElement = $printersXml.CreateElement("Filters")
            
            # FilterGroup mit Attributen direkt am Element (nicht als Child-Elemente!)
            $filterGroupElement = $printersXml.CreateElement("FilterGroup")
            $filterGroupElement.SetAttribute("bool", "AND")
            $filterGroupElement.SetAttribute("not", "0")
            $filterGroupElement.SetAttribute("name", "$domainName\$groupName")  # Format: DOMAIN\GroupName
            $filterGroupElement.SetAttribute("sid", $group.SID.Value)  # SID als Attribut
            $filterGroupElement.SetAttribute("userContext", "1")  # 1 = Benutzer, 0 = Computer
            $filterGroupElement.SetAttribute("primaryGroup", "0")  # 0 = nicht primäre Gruppe
            $filterGroupElement.SetAttribute("localGroup", "0")  # FEHLTE: Wie in funktionierenden GPOs
            
            # KEINE Child-Elemente! Alle Werte sind Attribute
            
            # Füge FilterGroup zu Filters hinzu
            $filtersElement.AppendChild($filterGroupElement) | Out-Null
            
            # Füge Filters-Element zum SharedPrinter hinzu
            $printerElement.AppendChild($filtersElement) | Out-Null
            
            # Füge PrinterConnection-Element zum Root-Element hinzu
            if (-not $printersXml.DocumentElement) {
                Write-Host "  [FEHLER] XML-Struktur fehlerhaft: Kein Root-Element gefunden" -ForegroundColor Red
                $errorCount++
                continue
            }
            
            $printersXml.DocumentElement.AppendChild($printerElement) | Out-Null
            
            Write-Host "  [OK] Drucker-Einstellung erstellt mit Item Level Targeting (Sicherheitsgruppe: $groupName)" -ForegroundColor Green
            $configuredCount++
        } else {
            # Drucker existiert bereits - aktualisiere die Attribute
            Write-Host "  [INFO] Drucker bereits vorhanden - aktualisiere Attribute..." -ForegroundColor Yellow
            
            # Aktualisiere Properties
            $existingProperties = $existingSharedPrinter.SelectSingleNode("Properties[@path='$printerUNC']")
            if ($existingProperties) {
                $existingProperties.SetAttribute("action", "C")  # C = Create
                if (-not $existingProperties.GetAttribute("skipLocal")) { $existingProperties.SetAttribute("skipLocal", "0") }
                if (-not $existingProperties.GetAttribute("persistent")) { $existingProperties.SetAttribute("persistent", "0") }
                # WICHTIG: deleteMaps auf "1" setzen, damit Druckerzuordnungen gelöscht werden
                $existingProperties.SetAttribute("deleteMaps", "1")
                # Entferne deleteAllShared falls vorhanden
                if ($existingProperties.GetAttribute("deleteAllShared")) { $existingProperties.RemoveAttribute("deleteAllShared") }
            }
            
            # Aktualisiere FilterGroup und füge Admin-Ausschluss-Filter hinzu
            $existingFilters = $existingSharedPrinter.SelectSingleNode("Filters")
            if ($existingFilters) {
                $existingFilterGroup = $existingFilters.SelectSingleNode("FilterGroup[@not='0']")  # Haupt-FilterGroup (not=0)
                if ($existingFilterGroup) {
                    # Aktualisiere SID falls sich geändert hat
                    $existingFilterGroup.SetAttribute("sid", $group.SID.Value)
                    $existingFilterGroup.SetAttribute("name", "$domainName\$groupName")
                    # Füge localGroup hinzu falls fehlt
                    if (-not $existingFilterGroup.GetAttribute("localGroup")) {
                        $existingFilterGroup.SetAttribute("localGroup", "0")
                    }
                } else {
                    # FilterGroup fehlt - erstelle es
                    $filterGroupElement = $printersXml.CreateElement("FilterGroup")
                    $filterGroupElement.SetAttribute("bool", "AND")
                    $filterGroupElement.SetAttribute("not", "0")
                    $filterGroupElement.SetAttribute("name", "$domainName\$groupName")
                    $filterGroupElement.SetAttribute("sid", $group.SID.Value)
                    $filterGroupElement.SetAttribute("userContext", "1")
                    $filterGroupElement.SetAttribute("primaryGroup", "0")
                    $filterGroupElement.SetAttribute("localGroup", "0")
                    $existingFilters.AppendChild($filterGroupElement) | Out-Null
                }
                
            } else {
                # Filters fehlt komplett - erstelle es mit allen Filtern
                $filtersElement = $printersXml.CreateElement("Filters")
                
                # Haupt-FilterGroup: Benutzer muss in Drucker-Gruppe sein
                $filterGroupElement = $printersXml.CreateElement("FilterGroup")
                $filterGroupElement.SetAttribute("bool", "AND")
                $filterGroupElement.SetAttribute("not", "0")
                $filterGroupElement.SetAttribute("name", "$domainName\$groupName")
                $filterGroupElement.SetAttribute("sid", $group.SID.Value)
                $filterGroupElement.SetAttribute("userContext", "1")
                $filterGroupElement.SetAttribute("primaryGroup", "0")
                $filterGroupElement.SetAttribute("localGroup", "0")
                $filtersElement.AppendChild($filterGroupElement) | Out-Null
                
                
                $existingSharedPrinter.AppendChild($filtersElement) | Out-Null
            }
            
            Write-Host "  [OK] Drucker-Einstellung aktualisiert mit korrekten Attributen" -ForegroundColor Green
            $configuredCount++
        }
        
    } catch {
        $errorMsg = if ($_.Exception.Message) { $_.Exception.Message } else { $_.Exception.ToString() }
        Write-Host "  [FEHLER] $errorMsg" -ForegroundColor Red
        $errorCount++
    }
}

# Prüfe jetzt die problematischen Drucker vom Server (nur wenn welche gefunden wurden)
if ($printersWithoutGroup.Count -gt 0) {
    Write-Host ""
    Write-Host "=== Prüfe problematische Drucker vom Server ===" -ForegroundColor Cyan
    Write-Host "Gefunden: $($printersWithoutGroup.Count) Drucker ohne Sicherheitsgruppe" -ForegroundColor Yellow
    Write-Host "Führe Server-Abfrage für diese Drucker aus..." -ForegroundColor Yellow
    
    try {
        $fixedCount = 0
        $checkIndex = 0
        foreach ($problemPrinter in $printersWithoutGroup) {
            $checkIndex++
            Write-Host "  [$checkIndex/$($printersWithoutGroup.Count)] Prüfe: $($problemPrinter.PrinterName)" -ForegroundColor Cyan
            
            # Hole Sicherheitsgruppen für diesen einzelnen Drucker
            $securityGroups = Get-PrinterSecurityGroups -ComputerName $ComputerName -PrinterName $problemPrinter.PrinterName
            $printerName = $problemPrinter.PrinterName
            $printerShareName = $problemPrinter.PrinterShareName
            $expectedGroupName = $problemPrinter.ExpectedGroupName
            if ($securityGroups -and $securityGroups.Count -gt 0) {
                $groupNames = ($securityGroups | ForEach-Object { $_.Name }) -join ", "
                Write-Host "    Am Server zugewiesene Gruppen: $groupNames" -ForegroundColor Gray
                
                # Versuche, eine passende Gruppe zu finden
                $foundGroup = $null
                foreach ($serverGroup in $securityGroups) {
                    # Prüfe ob der Gruppenname ähnlich zum Druckernamen ist
                    if ($serverGroup.Name -eq $printerName -or 
                        $serverGroup.Name -like "*$printerName*" -or
                        $printerName -like "*$($serverGroup.Name)*") {
                        try {
                            $foundGroup = Get-ADGroup -Filter "SID -eq '$($serverGroup.SID)'" -ErrorAction SilentlyContinue
                            if ($foundGroup) {
                                Write-Host "    [GEFUNDEN] Passende Gruppe: $($foundGroup.Name)" -ForegroundColor Green
                                break
                            }
                        } catch {
                            # Weiter suchen
                        }
                    }
                }
                
                # Falls keine passende Gruppe gefunden, nimm die erste Gruppe
                if (-not $foundGroup -and $securityGroups.Count -gt 0) {
                    try {
                        $firstGroup = $securityGroups[0]
                        $foundGroup = Get-ADGroup -Filter "SID -eq '$($firstGroup.SID)'" -ErrorAction SilentlyContinue
                        if ($foundGroup) {
                            Write-Host "    [INFO] Verwende erste zugewiesene Gruppe: $($foundGroup.Name)" -ForegroundColor Yellow
                        }
                    } catch {
                        # Keine Gruppe gefunden
                    }
                }
                
                if ($foundGroup) {
                    # Erstelle/aktualisiere GPO-Eintrag mit der gefundenen Gruppe
                    $printerUNC = "\\$ComputerName\$printerShareName"
                    $groupName = $foundGroup.Name
                    
                    # Prüfe ob Eintrag bereits existiert
                    $existingSharedPrinter = $printersXml.SelectSingleNode("//SharedPrinter[Properties[@path='$printerUNC']]")
                    
                    if ($existingSharedPrinter) {
                        # Aktualisiere bestehenden Eintrag
                        $existingProperties = $existingSharedPrinter.SelectSingleNode("Properties[@path='$printerUNC']")
                        if ($existingProperties) {
                            $existingProperties.SetAttribute("action", "C")
                            $existingProperties.SetAttribute("deleteMaps", "1")
                        }
                        
                        $existingFilters = $existingSharedPrinter.SelectSingleNode("Filters")
                        if ($existingFilters) {
                            $existingFilterGroup = $existingFilters.SelectSingleNode("FilterGroup[@not='0']")
                            if ($existingFilterGroup) {
                                $existingFilterGroup.SetAttribute("sid", $foundGroup.SID.Value)
                                $existingFilterGroup.SetAttribute("name", "$domainName\$groupName")
                            }
                        }
                        Write-Host "    [OK] GPO-Eintrag aktualisiert mit Gruppe: $groupName" -ForegroundColor Green
                    } else {
                        # Erstelle neuen Eintrag
                        $printerElement = $printersXml.CreateElement("SharedPrinter")
                        $printerElement.SetAttribute("clsid", "{9A5E9697-9095-436d-A0EE-4D128FDFBCE5}")
                        $printerElement.SetAttribute("name", $printerName)
                        $printerElement.SetAttribute("status", $printerName)
                        $printerElement.SetAttribute("image", "2")
                        $printerElement.SetAttribute("changed", (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
                        $printerGuid = [guid]::NewGuid().ToString().ToUpper()
                        $printerElement.SetAttribute("uid", "{$printerGuid}")
                        $printerElement.SetAttribute("userContext", "1")
                        $printerElement.SetAttribute("removePolicy", "1")
                        $printerElement.SetAttribute("bypassErrors", "1")
                        
                        $propertiesElement = $printersXml.CreateElement("Properties")
                        $propertiesElement.SetAttribute("action", "C")
                        $propertiesElement.SetAttribute("path", $printerUNC)
                        $propertiesElement.SetAttribute("default", "0")
                        $propertiesElement.SetAttribute("location", "")
                        $propertiesElement.SetAttribute("comment", "")
                        $propertiesElement.SetAttribute("skipLocal", "0")
                        $propertiesElement.SetAttribute("deleteAll", "0")
                        $propertiesElement.SetAttribute("persistent", "0")
                        $propertiesElement.SetAttribute("deleteMaps", "1")
                        $propertiesElement.SetAttribute("port", "")
                        $printerElement.AppendChild($propertiesElement) | Out-Null
                        
                        $filtersElement = $printersXml.CreateElement("Filters")
                        $filterGroupElement = $printersXml.CreateElement("FilterGroup")
                        $filterGroupElement.SetAttribute("bool", "AND")
                        $filterGroupElement.SetAttribute("not", "0")
                        $filterGroupElement.SetAttribute("name", "$domainName\$groupName")
                        $filterGroupElement.SetAttribute("sid", $foundGroup.SID.Value)
                        $filterGroupElement.SetAttribute("userContext", "1")
                        $filterGroupElement.SetAttribute("primaryGroup", "0")
                        $filterGroupElement.SetAttribute("localGroup", "0")
                        $filtersElement.AppendChild($filterGroupElement) | Out-Null
                        $printerElement.AppendChild($filtersElement) | Out-Null
                        
                        $printersXml.DocumentElement.AppendChild($printerElement) | Out-Null
                        Write-Host "    [OK] GPO-Eintrag erstellt mit Gruppe: $groupName" -ForegroundColor Green
                    }
                    
                    $fixedCount++
                    $configuredCount++
                    $errorCount-- # Reduziere Fehleranzahl da jetzt behoben
                } else {
                    Write-Host "    [WARNUNG] Keine passende AD-Gruppe gefunden" -ForegroundColor Yellow
                }
            } else {
                Write-Host "    [WARNUNG] Keine Sicherheitsgruppen am Server zugewiesen" -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
        Write-Host "Behoben: $fixedCount von $($printersWithoutGroup.Count) Druckern" -ForegroundColor $(if ($fixedCount -gt 0) { "Green" } else { "Yellow" })
    } catch {
        Write-Host "  [WARNUNG] Konnte Sicherheitsgruppen nicht abrufen: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Speichere XML-Datei EINMAL am Ende (nach allen Änderungen)
Write-Host ""
Write-Host "Speichere GPO-XML-Datei..." -ForegroundColor Yellow
try {
    # Verwende XmlWriterSettings für korrektes UTF-8 ohne BOM (wie GPO es erwartet)
    $xmlWriterSettings = New-Object System.Xml.XmlWriterSettings
    $xmlWriterSettings.Encoding = New-Object System.Text.UTF8Encoding $false  # UTF-8 ohne BOM
    $xmlWriterSettings.Indent = $true
    $xmlWriterSettings.IndentChars = "    "
    $xmlWriterSettings.NewLineChars = "`r`n"
    $xmlWriterSettings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
    
    $xmlWriter = [System.Xml.XmlWriter]::Create($printersXmlPath, $xmlWriterSettings)
    $printersXml.Save($xmlWriter)
    $xmlWriter.Close()
    Write-Host "  XML-Datei erfolgreich gespeichert" -ForegroundColor Green
} catch {
    Write-Host "  [FEHLER] Konnte XML-Datei nicht speichern: $($_.Exception.Message)" -ForegroundColor Red
    # Fallback: Versuche direkte Speicherung
    try {
        $printersXml.Save($printersXmlPath)
        Write-Host "  [INFO] XML-Datei mit Fallback-Methode gespeichert" -ForegroundColor Yellow
    } catch {
        Write-Host "  [FEHLER] Auch Fallback-Methode fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Verknüpfe GPO mit OU, falls angegeben
if ($LinkGPO -and $OUPath) {
    Write-Host ""
    Write-Host "Verknüpfe GPO mit OU: $OUPath" -ForegroundColor Yellow
    try {
        $null = Get-ADOrganizationalUnit -Identity $OUPath -ErrorAction Stop
        
        # Prüfe ob Verknüpfung bereits existiert
        $existingLinks = Get-GPInheritance -Target $OUPath -ErrorAction SilentlyContinue
        $linkExists = $existingLinks | Where-Object { $_.GpoId -eq $gpo.Id }
        
        if (-not $linkExists) {
            New-GPLink -Guid $gpo.Id -Target $OUPath -ErrorAction Stop | Out-Null
            Write-Host "GPO erfolgreich mit OU verknüpft" -ForegroundColor Green
        } else {
            Write-Host "GPO bereits mit OU verknüpft" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "FEHLER: Konnte GPO nicht mit OU verknüpfen: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
Write-Host "GPO-Name: $GPOName" -ForegroundColor White
Write-Host "GPO-GUID: $($gpo.Id)" -ForegroundColor White
Write-Host "Drucker konfiguriert: $configuredCount" -ForegroundColor Green
Write-Host "Übersprungen (nicht geteilt): $skippedCount" -ForegroundColor Yellow
Write-Host "Fehler: $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Gesamt Drucker: $($printers.Count)" -ForegroundColor White
Write-Host ""
Write-Host "HINWEIS: Item Level Targeting wurde über XML konfiguriert." -ForegroundColor Yellow
Write-Host "Bitte prüfen Sie die GPO im Group Policy Management Editor." -ForegroundColor Yellow
