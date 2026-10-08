function Test-NetworkDiagnostics {
    <#
    .SYNOPSIS
        Performs comprehensive local network, DNS, gateway, and listening port diagnostics.
    .DESCRIPTION
        Tests active network adapters, default gateway reachability, public IP resolution,
        DNS queries, and local TCP listening endpoints.
    #>
    [CmdletBinding()]
    param(
        [string[]]$DnsTargets = @("1.1.1.1", "google.com"),
        [switch]$PassThru
    )

    $activeAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq "Up"
    $primary = $activeAdapters | Select-Object -First 1

    $localIP = if ($primary) {
        (Get-NetIPAddress -InterfaceIndex $primary.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    } else { $null }

    $gw = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
    $gwPing = if ($gw) { Test-Connection -ComputerName $gw -Count 1 -Quiet } else { $false }

    $dnsResults = @()
    foreach ($target in $DnsTargets) {
        $test = Test-NetConnection -ComputerName $target -Port 53 -WarningAction SilentlyContinue
        $dnsResults += [PSCustomObject]@{
            Target    = $target
            Succeeded = $test.TcpTestSucceeded
        }
    }

    $pubIP = try {
        (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 3 -ErrorAction Stop)
    } catch {
        "Resolution Timed Out"
    }

    $listeningPorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Sort-Object LocalPort | Select-Object -First 15 | ForEach-Object {
            $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Port        = $_.LocalPort
                Address     = $_.LocalAddress
                PID         = $_.OwningProcess
                ProcessName = if ($proc) { $proc.ProcessName } else { "N/A" }
            }
        }

    $diag = [PSCustomObject]@{
        PrimaryAdapter = if ($primary) { $primary.Name } else { "None" }
        LocalIPv4      = $localIP
        DefaultGateway = $gw
        GatewayPing    = $gwPing
        PublicIP       = $pubIP
        DnsTests       = $dnsResults
        ListeningPorts = $listeningPorts
    }

    if ($PassThru) {
        return $diag
    }

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "               NETWORK & PORT DIAGNOSTICS                   " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    Write-Host "`n[Active Network Adapters]" -ForegroundColor Yellow
    if ($activeAdapters) {
        $activeAdapters | Select-Object Name, InterfaceDescription, LinkSpeed, Status | Format-Table -AutoSize
    } else {
        Write-Host "  No active network adapters found." -ForegroundColor Red
    }

    Write-Host "Primary Interface IP:    $($diag.LocalIPv4)"
    Write-Host "Default Gateway ($($diag.DefaultGateway)): " -NoNewline
    $gwColor = if ($diag.GatewayPing) { "Green" } else { "Red" }
    Write-Host ($diag.GatewayPing ? "Reachable" : "Unreachable") -ForegroundColor $gwColor
    Write-Host "Public IP Address:       $($diag.PublicIP)" -ForegroundColor Cyan

    Write-Host "`n[DNS Resolution & Port 53 Connectivity]" -ForegroundColor Yellow
    foreach ($dt in $diag.DnsTests) {
        $color = if ($dt.Succeeded) { "Green" } else { "Red" }
        Write-Host ("  DNS Probe to {0,-15} : " -f $dt.Target) -NoNewline
        Write-Host ($dt.Succeeded ? "SUCCESS" : "FAILED") -ForegroundColor $color
    }

    Write-Host "`n[Active Local Listening TCP Ports]" -ForegroundColor Yellow
    $diag.ListeningPorts | Format-Table -AutoSize
}
