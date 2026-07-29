<#
.SYNOPSIS
Runs a read-only network path check for common service-desk troubleshooting.

.DESCRIPTION
Checks local IP configuration, default-gateway reachability, DNS resolution and
TCP connectivity to a specified target. Results can be displayed or exported
as JSON for a ticket record.

.PARAMETER Target
DNS name or IP address to test.

.PARAMETER Port
TCP port to test. Defaults to 443.

.PARAMETER OutputPath
Optional JSON output path.

.EXAMPLE
.\Test-NetworkPath.ps1 -Target login.microsoftonline.com -Port 443

.EXAMPLE
.\Test-NetworkPath.ps1 -Target fileserver.contoso.local -Port 445 -OutputPath .\output\network-test.diagnostics.json
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Target,

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$Port = 443,

    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$activeConfigurations = @(
    Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq "Up" }
)

$gateways = @(
    $activeConfigurations |
        ForEach-Object { $_.IPv4DefaultGateway.NextHop } |
        Where-Object { $_ } |
        Select-Object -Unique
)

$gatewayResults = @(
    foreach ($gateway in $gateways) {
        [pscustomobject]@{
            Gateway = $gateway
            Reachable = Test-Connection -ComputerName $gateway -Count 1 -Quiet -ErrorAction SilentlyContinue
        }
    }
)

$dnsResult = try {
    $records = Resolve-DnsName -Name $Target -ErrorAction Stop |
        Where-Object { $_.IPAddress }

    [pscustomobject]@{
        Success = $true
        Addresses = @($records.IPAddress | Select-Object -Unique)
        Error = $null
    }
}
catch {
    [pscustomobject]@{
        Success = $false
        Addresses = @()
        Error = $_.Exception.Message
    }
}

$tcpResult = Test-NetConnection -ComputerName $Target -Port $Port -WarningAction SilentlyContinue

$report = [ordered]@{
    SchemaVersion = "1.0"
    TestedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    ComputerName = $env:COMPUTERNAME
    Target = $Target
    Port = $Port
    ActiveInterfaces = @(
        $activeConfigurations |
            ForEach-Object {
                [pscustomobject]@{
                    InterfaceAlias = $_.InterfaceAlias
                    IPv4Address = @($_.IPv4Address.IPAddress)
                    DnsServers = @($_.DNSServer.ServerAddresses)
                }
            }
    )
    DefaultGateways = $gatewayResults
    DnsResolution = $dnsResult
    TcpTest = [pscustomobject]@{
        RemoteAddress = [string]$tcpResult.RemoteAddress
        SourceAddress = [string]$tcpResult.SourceAddress
        TcpTestSucceeded = $tcpResult.TcpTestSucceeded
    }
    SuggestedFocus = if (-not $dnsResult.Success) {
        "DNS resolution"
    }
    elseif ($gatewayResults.Count -gt 0 -and $gatewayResults.Reachable -contains $false) {
        "Local network or default gateway"
    }
    elseif (-not $tcpResult.TcpTestSucceeded) {
        "Firewall, routing or target service"
    }
    else {
        "Connectivity test passed"
    }
}

$resultObject = [pscustomobject]$report

if ($OutputPath) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $resultObject | ConvertTo-Json -Depth 7 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Network diagnostics written to: $OutputPath" -ForegroundColor Green
}

Write-Output $resultObject
