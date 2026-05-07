# ==================================================================
# Phase 1: Erstellt LÃ¶schliste fÃ¼r alte GPOs und Sicherheitsgruppen
# ==================================================================

$ErrorActionPreference = "Continue"

# Konfiguration
$OutputDir = $PSScriptRoot
$LogFile = "$OutputDir\Logs\1.4-Erstelle-Loeschliste_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').log"

# Erstelle Verzeichnisse
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
if (-not (Test-Path "$OutputDir\Logs")) { New-Item -ItemType Directory -Path "$OutputDir\Logs" -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage -Encoding UTF8
}

Write-Log "=== Erstelle LÃ¶schliste gestartet ===" "INFO"

# Lade GPO-Liste
$gpoFile = Join-Path $OutputDir "1.2-GPOs-Bestandsaufnahme.csv"
$groupFile = Join-Path $OutputDir "1.3-Sicherheitsgruppen-Bestandsaufnahme.csv"

$loeschlisteContent = @"
# LÃ¶schliste fÃ¼r alte GPOs und Sicherheitsgruppen (NACH erfolgreichem Test!)
# ============================================================================
# WICHTIG: Diese GPOs und Sicherheitsgruppen erst lÃ¶schen, nachdem die neue 
# Druckerumgebung erfolgreich getestet wurde und mindestens 2-4 Wochen stabil lÃ¤uft!
#
# Erstellt am: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#

"@

# GPOs zur LÃ¶schliste hinzufÃ¼gen
if (Test-Path $gpoFile) {
    $gpos = Import-Csv -Path $gpoFile -Delimiter ";"
    
    # Filtere Standard-GPOs und allgemeine Richtlinien heraus (dÃ¼rfen nicht gelÃ¶scht werden)
    $standardGPOs = @(
        "Default Domain Policy",
        "Default Domain Controllers Policy"
    )
    
    # Exakte GPO-Namen, die ausgeschlossen werden sollen
    $excludeExactNames = @(
        "RDS 2016 Server Richtlinie fÃ¼r Thin Client Bedienung",
        "Druckertreiber Installation Point-and-Print fÃ¼r User erlauben",
        "Drucker einschrÃ¤nken (Nur fÃ¼r den Campus verwenden) FBA"
    )
    
    # Pattern fÃ¼r GPOs, die ausgeschlossen werden sollen
    $excludePatterns = @(
        "*RDS*Server*Richtlinie*",  # RDS-Richtlinien
        "*Druckertreiber Installation*",  # Allgemeine Druckertreiber-Richtlinien
        "*Drucker einschrÃ¤nken*",  # Allgemeine Drucker-EinschrÃ¤nkungsrichtlinien
        "SafeQ SW fÃ¼r Verwaltung*",  # Allgemeine SafeQ-Richtlinien
        "SafeQ Farbe fÃ¼r Verwaltung*"  # Allgemeine SafeQ-Richtlinien
    )
    
    $gposToDelete = $gpos | Where-Object { 
        $gpoName = $_.GPOName.Trim()
        
        # SOFORT ausschlieÃŸen: GPOs mit "einschrÃ¤nken", "Druckertreiber Installation" oder RDS-Richtlinien
        if ($gpoName -like "*einschrÃ¤nken*" -or $gpoName -like "*Druckertreiber Installation*" -or ($gpoName -like "*RDS*" -and $gpoName -like "*Server*" -and $gpoName -like "*Richtlinie*")) {
            Write-Log "Gefiltert (Sofort-Ausschluss): $gpoName" "INFO"
            return $false
        }
        
        # ZusÃ¤tzliche explizite PrÃ¼fung fÃ¼r bekannte problematische GPOs
        if ($gpoName -eq "Drucker einschrÃ¤nken (Nur fÃ¼r den Campus verwenden) FBA") {
            Write-Log "Gefiltert (Explizite PrÃ¼fung): $gpoName" "INFO"
            return $false
        }
        
        # Filtere Standard-GPOs
        if ($standardGPOs -contains $gpoName) { 
            Write-Log "Gefiltert (Standard-GPO): $gpoName" "INFO"
            return $false 
        }
        
        # Filtere exakte GPO-Namen
        if ($excludeExactNames -contains $gpoName) { 
            Write-Log "Gefiltert (Exakte Ãœbereinstimmung): $gpoName" "INFO"
            return $false 
        }
        
        # Filtere allgemeine Richtlinien per Pattern
        foreach ($pattern in $excludePatterns) {
            if ($gpoName -like $pattern) { 
                Write-Log "Gefiltert (Pattern '$pattern'): $gpoName" "INFO"
                return $false 
            }
        }
        
        # Nur GPOs mit "Drucker" im Namen ODER ContainsPrinterInName = True
        $hasPrinterInName = $_.ContainsPrinterInName -eq "True" -or $gpoName -like "*Drucker*"
        
        return $hasPrinterInName
    }
    
    if ($gposToDelete.Count -gt 0) {
        $loeschlisteContent += "`n# ===== ZU LÃ–SCHENDE GPOS =====`n"
        $loeschlisteContent += "# Anzahl: $($gposToDelete.Count)`n"
        
        # ZÃ¤hle gefilterte Standard-GPOs
        $filteredCount = ($gpos | Where-Object { $standardGPOs -contains $_.GPOName }).Count
        if ($filteredCount -gt 0) {
            $loeschlisteContent += "# Gefiltert (Standard-GPOs, nicht lÃ¶schen!): $filteredCount`n"
            Write-Log "Gefiltert: $filteredCount Standard-GPO(s) werden nicht gelÃ¶scht" "INFO"
        }
        $loeschlisteContent += "`n"
        
        foreach ($gpo in $gposToDelete) {
            $loeschlisteContent += "# GPO: $($gpo.GPOName)`n"
            $loeschlisteContent += "# ID: $($gpo.GPOId)`n"
            $loeschlisteContent += "# Status: $($gpo.GPOStatus)`n"
            if ($gpo.Links) {
                $loeschlisteContent += "# VerknÃ¼pfungen: $($gpo.Links)`n"
            }
            $loeschlisteContent += "`n"
        }
    }
    else {
        $loeschlisteContent += "`n# KEINE GPOS ZUM LÃ–SCHEN GEFUNDEN`n`n"
    }
}
else {
    $loeschlisteContent += "`n# WARNUNG: GPO-Liste nicht gefunden: $gpoFile`n"
    $loeschlisteContent += "# Bitte fÃ¼hren Sie zuerst 1.2-Bestandsaufnahme-GPOs.ps1 aus!`n`n"
}

# Sicherheitsgruppen zur LÃ¶schliste hinzufÃ¼gen
if (Test-Path $groupFile) {
    $groups = Import-Csv -Path $groupFile -Delimiter ";"
    
    if ($groups.Count -gt 0) {
        # Erstelle eindeutige Liste der Sicherheitsgruppen (basierend auf DN)
        # Die CSV hat mehrere EintrÃ¤ge pro Gruppe (verschiedene AccessMask), daher eindeutig machen
        $uniqueGroups = @{}
        foreach ($group in $groups) {
            $dn = $group.SecurityGroupDN
            if (-not [string]::IsNullOrWhiteSpace($dn) -and -not $uniqueGroups.ContainsKey($dn)) {
                $uniqueGroups[$dn] = $group
            }
        }
        
        $groupsToDelete = $uniqueGroups.Values | Sort-Object SecurityGroup
        
        if ($groupsToDelete.Count -gt 0) {
            $loeschlisteContent += "`n# ===== ZU LÃ–SCHENDE SICHERHEITSGRUPPEN =====`n"
            $loeschlisteContent += "# Anzahl: $($groupsToDelete.Count)`n"
            $loeschlisteContent += "# (Aus $($groups.Count) EintrÃ¤gen in CSV, eindeutige Gruppen)`n`n"
            
            foreach ($group in $groupsToDelete) {
                $groupName = $group.SecurityGroup
                $groupDN = $group.SecurityGroupDN
                $memberCount = $group.MemberCount
                
                if (-not [string]::IsNullOrWhiteSpace($groupName) -and -not [string]::IsNullOrWhiteSpace($groupDN)) {
                    $loeschlisteContent += "# Sicherheitsgruppe: $groupName`n"
                    $loeschlisteContent += "# DN: $groupDN`n"
                    $loeschlisteContent += "# Mitglieder: $memberCount`n"
                    $loeschlisteContent += "`n"
                }
            }
        }
        else {
            $loeschlisteContent += "`n# KEINE SICHERHEITSGRUPPEN ZUM LÃ–SCHEN GEFUNDEN`n`n"
        }
    }
    else {
        $loeschlisteContent += "`n# KEINE SICHERHEITSGRUPPEN ZUM LÃ–SCHEN GEFUNDEN`n`n"
    }
}
else {
    $loeschlisteContent += "`n# WARNUNG: Sicherheitsgruppen-Liste nicht gefunden: $groupFile`n"
    $loeschlisteContent += "# Bitte fÃ¼hren Sie zuerst 1.3-Bestandsaufnahme-Sicherheitsgruppen.ps1 aus!`n`n"
}

# PowerShell-Befehle hinzufÃ¼gen
$loeschlisteContent += @"

# ===== POWERShell-BEFEHLE ZUM LÃ–SCHEN =====
# WICHTIG: Nur ausfÃ¼hren, nachdem die neue Umgebung 2-4 Wochen stabil lÃ¤uft!
# Backup vor dem LÃ¶schen erstellen!

# GPOs lÃ¶schen:
# Import-Module GroupPolicy
# `$gposToDelete = Import-Csv -Path "$gpoFile" -Delimiter ";"
# `$standardGPOs = @("Default Domain Policy", "Default Domain Controllers Policy")
# `$gposToDelete = `$gposToDelete | Where-Object { `$standardGPOs -notcontains `$_.GPOName }
# foreach (`$gpo in `$gposToDelete) {
#     Remove-GPO -Guid `$gpo.GPOId -Confirm:`$false
#     Write-Host "GPO gelÃ¶scht: `$(`$gpo.GPOName)"
# }

# Sicherheitsgruppen lÃ¶schen:
# Import-Module ActiveDirectory
# `$groups = Import-Csv -Path "$groupFile" -Delimiter ";"
# `$uniqueGroups = @{}
# foreach (`$group in `$groups) {
#     `$dn = `$group.SecurityGroupDN
#     if (-not [string]::IsNullOrWhiteSpace(`$dn) -and -not `$uniqueGroups.ContainsKey(`$dn)) {
#         `$uniqueGroups[`$dn] = `$group
#     }
# }
# foreach (`$group in `$uniqueGroups.Values) {
#     Remove-ADGroup -Identity `$group.SecurityGroupDN -Confirm:`$false
#     Write-Host "Sicherheitsgruppe gelÃ¶scht: `$(`$group.SecurityGroup)"
# }

"@

# Speichere LÃ¶schliste
$loeschlisteFile = Join-Path $OutputDir "Loeschliste-GPOs-und-Gruppen.txt"
$loeschlisteContent | Out-File -FilePath $loeschlisteFile -Encoding UTF8
Write-Log "LÃ¶schliste erstellt: $loeschlisteFile" "SUCCESS"

Write-Host ""
Write-Host "=== LÃ¶schliste erstellt ===" -ForegroundColor Green
Write-Host "Datei: $loeschlisteFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "WICHTIG: LÃ¶schen Sie diese GPOs und Gruppen erst nach erfolgreichem Test!" -ForegroundColor Yellow

Write-Log "=== Erstelle LÃ¶schliste abgeschlossen ===" "INFO"

