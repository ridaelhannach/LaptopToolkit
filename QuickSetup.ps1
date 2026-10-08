<#
.SYNOPSIS
    QuickSetup.ps1 - Automated Installer & Bootstrapper for LaptopToolkit
.DESCRIPTION
    Installs LaptopToolkit as a user PowerShell module, sets execution policy,
    creates a desktop shortcut, and registers the 'toolkit' command.
    Fully compatible with one-line web installation (irm ... | iex) and local cloning.
.AUTHOR
    Rida El Hannach / LaptopToolkit
#>

[CmdletBinding()]
param(
    [switch]$SkipShortcut,
    [switch]$AutoRegisterTask
)

Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "         LAPTOP TOOLKIT - OPEN SOURCE INSTALLER             " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Determine Module Install Directory using active PSModulePath
$userModuleRoot = ($env:PSModulePath -split [System.IO.Path]::PathSeparator) | Where-Object {
    $_ -and ($_ -like "*$HOME*" -or $_ -like "*$env:USERPROFILE*")
} | Select-Object -First 1

if (-not $userModuleRoot) {
    $docFolder = [Environment]::GetFolderPath("MyDocuments")
    $userModuleRoot = if ($PSVersionTable.PSEdition -eq "Core") {
        Join-Path $docFolder "PowerShell\Modules"
    } else {
        Join-Path $docFolder "WindowsPowerShell\Modules"
    }
}

$userModulePath = Join-Path $userModuleRoot "LaptopToolkit"
Write-Host "`n[1/5] Target Module Path: $userModulePath" -ForegroundColor Yellow

if (-not (Test-Path $userModulePath)) {
    New-Item -ItemType Directory -Path $userModulePath -Force | Out-Null
}

# Ensure Reports directory exists
$reportsDir = Join-Path $HOME "LaptopToolkit\Reports"
if (-not (Test-Path $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
}

# 2. Execution Policy Check
Write-Host "`n[2/5] Configuring Execution Policy..." -ForegroundColor Yellow
$currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentPolicy -ne "RemoteSigned" -and $currentPolicy -ne "Unrestricted" -and $currentPolicy -ne "Bypass") {
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host "      Execution policy set to RemoteSigned for CurrentUser." -ForegroundColor Green
    } catch {
        Write-Host "      Unable to update execution policy automatically. Run as Administrator if restricted." -ForegroundColor DarkGray
    }
} else {
    Write-Host "      Execution policy already permits local scripts ($currentPolicy)." -ForegroundColor Green
}

# 3. Locate or Download Module Files
Write-Host "`n[3/5] Deploying LaptopToolkit Module..." -ForegroundColor Yellow

$sourceSrc = $null
$tempCleanups = @()

# Case A: Local execution (script was run from a local folder or git clone)
if ($PSScriptRoot) {
    if (Test-Path (Join-Path $PSScriptRoot "src\LaptopToolkit.psd1")) {
        $sourceSrc = Join-Path $PSScriptRoot "src"
    } elseif (Test-Path (Join-Path $PSScriptRoot "LaptopToolkit.psd1")) {
        $sourceSrc = $PSScriptRoot
    }
}

# Case B: Web execution via `irm ... | iex` (PSScriptRoot is empty)
if (-not $sourceSrc -or -not (Test-Path $sourceSrc)) {
    Write-Host "      Web installer detected. Downloading latest repository from GitHub..." -ForegroundColor Cyan
    $repoZipUrl = "https://github.com/ridaelhannach/LaptopToolkit/archive/refs/heads/main.zip"
    $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) "LaptopToolkit-install-$([guid]::NewGuid().ToString('N')).zip"
    $tempExtract = Join-Path ([System.IO.Path]::GetTempPath()) "LaptopToolkit-extract-$([guid]::NewGuid().ToString('N'))"

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $repoZipUrl -OutFile $tempZip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        $extractedRoot = Join-Path $tempExtract "LaptopToolkit-main"
        if (Test-Path (Join-Path $extractedRoot "src\LaptopToolkit.psd1")) {
            $sourceSrc = Join-Path $extractedRoot "src"
        } elseif (Test-Path (Join-Path $extractedRoot "LaptopToolkit.psd1")) {
            $sourceSrc = $extractedRoot
        } else {
            throw "Could not locate LaptopToolkit.psd1 in downloaded archive."
        }

        $tempCleanups += $tempZip
        $tempCleanups += $tempExtract
    } catch {
        Write-Host "      Download failed: $_" -ForegroundColor Red
        Write-Host "      Tip: If the repo is brand new, verify that the files are pushed to the 'main' branch on GitHub." -ForegroundColor Yellow
        return
    }
}

Write-Host "      Copying module components into $userModulePath..." -ForegroundColor Green
Copy-Item -Path (Join-Path $sourceSrc "*") -Destination $userModulePath -Recurse -Force

# Clean up temporary downloads
foreach ($tmp in $tempCleanups) {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$manifestPath = Join-Path $userModulePath "LaptopToolkit.psd1"
if (Test-Path $manifestPath) {
    Write-Host "      Module files successfully installed!" -ForegroundColor Green
} else {
    Write-Host "      Warning: Manifest file not found in $userModulePath." -ForegroundColor Red
}

# 4. Create Desktop Shortcut
if (-not $SkipShortcut) {
    Write-Host "`n[4/5] Creating Desktop Shortcut..." -ForegroundColor Yellow
    try {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $shortcutPath = Join-Path $desktopPath "Laptop Toolkit.lnk"
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = "-NoExit -ExecutionPolicy Bypass -Command `"Import-Module '$manifestPath'; Start-ToolkitDashboard`""
        $shortcut.WorkingDirectory = $HOME
        $shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
        $shortcut.Description = "Launch LaptopToolkit Automation Dashboard"
        $shortcut.Save()
        Write-Host "      Desktop shortcut created: 'Laptop Toolkit'" -ForegroundColor Green
    } catch {
        Write-Host "      Could not generate desktop shortcut: $_" -ForegroundColor DarkGray
    }
}

# 5. PowerShell Profile Integration
Write-Host "`n[5/5] Registering 'toolkit' Command in `$PROFILE..." -ForegroundColor Yellow
try {
    if (-not (Test-Path $PROFILE)) {
        $pDir = Split-Path $PROFILE -Parent
        if (-not (Test-Path $pDir)) { New-Item -ItemType Directory -Path $pDir -Force | Out-Null }
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }

    $profileContent = Get-Content -Path $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($profileContent -notmatch "Import-Module.*LaptopToolkit") {
        $profileBlock = @"

# --- LaptopToolkit Autoload ---
Import-Module '$manifestPath' -ErrorAction SilentlyContinue
"@
        Add-Content -Path $PROFILE -Value $profileBlock
        Write-Host "      Added module autoload to `$PROFILE." -ForegroundColor Green
        Write-Host "      (Type 'toolkit' anytime in PowerShell to open the dashboard)" -ForegroundColor Cyan
    } else {
        Write-Host "      LaptopToolkit autoload is already present in `$PROFILE." -ForegroundColor Green
    }
} catch {
    Write-Host "      Could not update PowerShell Profile: $_" -ForegroundColor DarkGray
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "                INSTALLATION COMPLETE!                      " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Usage:"
Write-Host "  * Type 'toolkit' in any PowerShell terminal."
Write-Host "  * Or run individual cmdlets: Get-LaptopHealth, Test-SecurityStatus, Invoke-SafeDiskCleanup"
Write-Host "  * Or double-click the 'Laptop Toolkit' shortcut on your Desktop.`n"

$launch = Read-Host "Launch LaptopToolkit now? (Y/N)"
if ($launch -eq 'Y' -or $launch -eq 'y') {
    Import-Module $manifestPath -Force
    Start-ToolkitDashboard
}
