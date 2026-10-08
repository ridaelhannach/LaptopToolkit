function Invoke-SafeDiskCleanup {
    <#
    .SYNOPSIS
        Safely identifies and purges temporary files and system caches with safety guardrails.
    .DESCRIPTION
        Implements discovery-first analysis, path safety guards against protected roots,
        locked file exception handling, and audit logging.
    .PARAMETER Clean
        When specified, executes deletion. Without this switch, runs in read-only Discovery Mode.
    .PARAMETER DaysOld
        Minimum age of files to clean in days. Default is 2.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [switch]$Clean,
        [int]$DaysOld = 2,
        [switch]$EmptyRecycleBin
    )

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "             SMART DISK CLEANER (DISCOVERY & PURGE)         " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $targets = @(
        @{ Name = "User Temp"; Path = "$env:TEMP" }
    )

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if ($isAdmin) {
        $targets += @{ Name = "Windows System Temp"; Path = "C:\Windows\Temp" }
    } else {
        Write-Host "[Note] Run as Administrator to include C:\Windows\Temp." -ForegroundColor DarkGray
    }

    $cutoffDate = (Get-Date).AddDays(-$DaysOld)
    $summary = @()
    $totalCleanableBytes = 0

    foreach ($target in $targets) {
        if (Test-Path $target.Path) {
            Assert-SafePath $target.Path
            $files = Get-ChildItem -Path $target.Path -File -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoffDate }
            $bytes = ($files | Measure-Object -Property Length -Sum).Sum
            if (-not $bytes) { $bytes = 0 }
            $totalCleanableBytes += $bytes
            $summary += [PSCustomObject]@{
                Target     = $target.Name
                Path       = $target.Path
                FileCount  = $files.Count
                SizeMB     = [math]::Round($bytes / 1MB, 2)
            }
        }
    }

    Write-Host "`n[Discovery Analysis (Files older than $DaysOld days)]" -ForegroundColor Yellow
    $summary | Format-Table -AutoSize

    $totalMB = [math]::Round($totalCleanableBytes / 1MB, 2)
    Write-Host ("Total Reclaimable Space: {0} MB" -f $totalMB) -ForegroundColor Cyan

    if (-not $Clean) {
        $confirm = Read-Host "`nDo you want to safely purge these temporary files now? (Y/N)"
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Host "Clean cancelled. Discovery mode completed without changes." -ForegroundColor DarkGray
            return
        }
    }

    $deletedCount = 0
    $skippedCount = 0
    $reclaimedBytes = 0

    foreach ($target in $targets) {
        Write-Host ("Cleaning {0}..." -f $target.Name) -ForegroundColor Yellow
        $files = Get-ChildItem -Path $target.Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoffDate }

        foreach ($f in $files) {
            if ($PSCmdlet.ShouldProcess($f.FullName, "Delete Temp File")) {
                try {
                    $sz = $f.Length
                    Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                    $deletedCount++
                    $reclaimedBytes += $sz
                } catch [System.IO.IOException] {
                    $skippedCount++
                } catch {
                    $skippedCount++
                }
            }
        }
    }

    if ($EmptyRecycleBin -or $Clean) {
        try {
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            Write-Host "Recycle Bin purged." -ForegroundColor Green
        } catch {}
    }

    $actualReclaimedMB = [math]::Round($reclaimedBytes / 1MB, 2)
    Write-Host "`n[Cleanup Results]" -ForegroundColor Green
    Write-Host ("Deleted Files: {0} ({1} MB)" -f $deletedCount, $actualReclaimedMB)
    Write-Host ("Skipped Files (In-use/Locked): {0}" -f $skippedCount) -ForegroundColor DarkGray
    Write-ToolkitLog "Cleaned $deletedCount files ($actualReclaimedMB MB). Skipped $skippedCount locked files." "INFO"
}
