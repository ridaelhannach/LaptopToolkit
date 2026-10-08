# LaptopToolkit.psm1 - Module Root Loader

$PublicDir  = Join-Path $PSScriptRoot "Public"
$PrivateDir = Join-Path $PSScriptRoot "Private"

# 1. Load Private Helpers
if (Test-Path $PrivateDir) {
    Get-ChildItem -Path $PrivateDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# 2. Load Public Cmdlets
if (Test-Path $PublicDir) {
    Get-ChildItem -Path $PublicDir -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# 3. Export Specific Cmdlets
Export-ModuleMember -Function @(
    "Get-LaptopHealth",
    "Test-SecurityStatus",
    "Test-NetworkDiagnostics",
    "Test-DeveloperEnvironment",
    "Invoke-SafeDiskCleanup",
    "Get-StartupPrograms",
    "New-HealthReport",
    "New-BatteryReport",
    "Register-ToolkitScheduledTask",
    "Start-ToolkitDashboard"
) -Alias @("toolkit")

Set-Alias -Name toolkit -Value Start-ToolkitDashboard
