# Install Wireshark on Remote Server via winget
# Requires winget to be available on the remote server

param(
    [string]$ServerName = "<INTERNAL-SERVER>-rds01"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Wireshark Installation (Remote)" -ForegroundColor Cyan
Write-Host "Server: $ServerName" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nChecking if Wireshark is already installed..." -NoNewline
try {
    $alreadyInstalled = Invoke-Command -ComputerName $ServerName -ScriptBlock {
        Test-Path "C:\Program Files\Wireshark\tshark.exe"
    }
    
    if ($alreadyInstalled) {
        Write-Host " ALREADY INSTALLED" -ForegroundColor Green
        Write-Host "Wireshark is already installed on $ServerName" -ForegroundColor Green
        exit 0
    }
    else {
        Write-Host " NOT INSTALLED" -ForegroundColor Yellow
    }
}
catch {
    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`nChecking if winget is available..." -NoNewline
try {
    $wingetAvailable = Invoke-Command -ComputerName $ServerName -ScriptBlock {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            return $true
        }
        return $false
    }
    
    if (-not $wingetAvailable) {
        Write-Host " NOT AVAILABLE" -ForegroundColor Yellow
        Write-Host "Winget not available, will use manual download and install" -ForegroundColor Cyan
    }
    else {
        Write-Host " AVAILABLE" -ForegroundColor Green
    }
}
catch {
    Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($wingetAvailable) {
    Write-Host "`nInstalling Wireshark via winget..." -ForegroundColor Cyan
    Write-Host "This may take a few minutes..." -ForegroundColor Yellow
    
    try {
        $installResult = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            $output = @{
                Success = $false
                Output = ""
                Error = ""
            }
            
            try {
                $result = winget install -e --id WiresharkFoundation.Wireshark --accept-package-agreements --accept-source-agreements 2>&1
                $output.Output = $result | Out-String
                
                if ($LASTEXITCODE -eq 0) {
                    $output.Success = $true
                }
                else {
                    $output.Error = "Exit code: $LASTEXITCODE"
                }
            }
            catch {
                $output.Error = $_.Exception.Message
            }
            
            return $output
        }
    }
    catch {
        Write-Host "`n[ERROR] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "`nInstalling Wireshark via manual download..." -ForegroundColor Cyan
    Write-Host "This may take a few minutes..." -ForegroundColor Yellow
    
    try {
        $installResult = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            $output = @{
                Success = $false
                Output = ""
                Error = ""
            }
            
            try {
                $tempDir = "C:\Temp"
                if (-not (Test-Path $tempDir)) {
                    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
                }
                
                $installerPath = Join-Path $tempDir "Wireshark-installer.exe"
                $wiresharkUrl = "https://2.na.dl.wireshark.org/win64/Wireshark-4.6.2-x64.exe"
                
                Write-Host "  Downloading Wireshark installer..." -ForegroundColor Cyan
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri $wiresharkUrl -OutFile $installerPath -UseBasicParsing
                
                if (-not (Test-Path $installerPath)) {
                    $output.Error = "Download failed - file not found"
                    return $output
                }
                
                Write-Host "  Running silent installation..." -ForegroundColor Cyan
                $process = Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait -PassThru -NoNewWindow
                
                if ($process.ExitCode -eq 0) {
                    $output.Success = $true
                    $output.Output = "Silent installation completed with exit code: $($process.ExitCode)"
                }
                else {
                    $output.Error = "Installation failed with exit code: $($process.ExitCode)"
                }
                
                Start-Sleep -Seconds 2
                Remove-Item $installerPath -ErrorAction SilentlyContinue
            }
            catch {
                $output.Error = $_.Exception.Message
            }
            
            return $output
        }
    }
    catch {
        Write-Host "`n[ERROR] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

if ($installResult) {
    
    if ($installResult.Success) {
        Write-Host "`n[OK] Wireshark installed successfully!" -ForegroundColor Green
        Write-Host "`nInstallation output:" -ForegroundColor Cyan
        Write-Host $installResult.Output -ForegroundColor White
        
        Write-Host "`nVerifying installation..." -NoNewline
        Start-Sleep -Seconds 5
        
        $verified = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            Test-Path "C:\Program Files\Wireshark\tshark.exe"
        }
        
        if ($verified) {
            Write-Host " OK" -ForegroundColor Green
            Write-Host "`nWireshark is ready to use on $ServerName" -ForegroundColor Green
        }
        else {
            Write-Host " WARNING" -ForegroundColor Yellow
            Write-Host "Installation completed but tshark.exe not found yet." -ForegroundColor Yellow
            Write-Host "Please wait a few seconds and verify manually." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "`n[ERROR] Installation failed!" -ForegroundColor Red
        Write-Host "Error: $($installResult.Error)" -ForegroundColor Red
        Write-Host "`nOutput:" -ForegroundColor Yellow
        Write-Host $installResult.Output -ForegroundColor White
        exit 1
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
