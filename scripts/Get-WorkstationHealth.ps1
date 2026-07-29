<#
.SYNOPSIS
Collects a read-only Windows workstation health snapshot.

.DESCRIPTION
Gathers operating-system, uptime, memory, disk, network, service and optional
recent event-log information. The result is written as structured JSON so it
can be attached to a support ticket or compared between troubleshooting steps.

The script does not change system configuration. Some event-log fields may be
unavailable when the current user lacks permission.

.PARAMETER OutputPath
Destination JSON path. Defaults to a timestamped file in the current directory.

.PARAMETER IncludeEventSummary
Adds counts of critical and error events from the System log during the last
24 hours.

.EXAMPLE
.\Get-WorkstationHealth.ps1 -OutputPath .\output\PC-014.diagnostics.json

.EXAMPLE
.\Get-WorkstationHealth.ps1 -IncludeEventSummary
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PWD ("workstation-health-{0}.diagnostics.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))),

    [Parameter()]
    [switch]$IncludeEventSummary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-SafeQuery {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        & $Action
    }
    catch {
        [pscustomobject]@{
            Query = $Name
            Status = "Unavailable"
            Error = $_.Exception.Message
        }
    }
}

$computerSystem = Invoke-SafeQuery -Name "ComputerSystem" -Action {
    Get-CimInstance -ClassName Win32_ComputerSystem
}

$operatingSystem = Invoke-SafeQuery -Name "OperatingSystem" -Action {
    Get-CimInstance -ClassName Win32_OperatingSystem
}

$logicalDisks = Invoke-SafeQuery -Name "LogicalDisks" -Action {
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" |
        ForEach-Object {
            $freePercent = if ($_.Size -gt 0) {
                [math]::Round(($_.FreeSpace / $_.Size) * 100, 1)
            }
            else {
                0
            }

            [pscustomobject]@{
                DeviceId = $_.DeviceID
                VolumeName = $_.VolumeName
                SizeGB = [math]::Round($_.Size / 1GB, 2)
                FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                FreePercent = $freePercent
                Status = if ($freePercent -lt 10) { "Attention" } else { "OK" }
            }
        }
}

$networkAdapters = Invoke-SafeQuery -Name "NetworkAdapters" -Action {
    Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq "Up" } |
        ForEach-Object {
            [pscustomobject]@{
                InterfaceAlias = $_.InterfaceAlias
                InterfaceDescription = $_.InterfaceDescription
                IPv4Address = @($_.IPv4Address.IPAddress)
                DefaultGateway = @($_.IPv4DefaultGateway.NextHop)
                DnsServers = @($_.DNSServer.ServerAddresses)
            }
        }
}

$serviceHealth = Invoke-SafeQuery -Name "ServiceHealth" -Action {
    @("Dnscache", "Spooler", "wuauserv") |
        ForEach-Object {
            $service = Get-Service -Name $_ -ErrorAction SilentlyContinue
            if ($null -eq $service) {
                [pscustomobject]@{ Name = $_; Status = "NotFound"; StartType = $null }
            }
            else {
                $serviceDetails = Get-CimInstance Win32_Service -Filter "Name='$($_)'"
                [pscustomobject]@{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    Status = [string]$service.Status
                    StartType = $serviceDetails.StartMode
                }
            }
        }
}

$pendingRebootChecks = [ordered]@{
    ComponentBasedServicing = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
    WindowsUpdate = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    PendingFileRename = $null -ne (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue)
}

$eventSummary = $null
if ($IncludeEventSummary) {
    $eventSummary = Invoke-SafeQuery -Name "SystemEventSummary" -Action {
        $startTime = (Get-Date).AddHours(-24)
        $events = Get-WinEvent -FilterHashtable @{
            LogName = "System"
            Level = 1, 2
            StartTime = $startTime
        } -ErrorAction Stop

        [pscustomobject]@{
            WindowHours = 24
            CriticalCount = @($events | Where-Object Level -eq 1).Count
            ErrorCount = @($events | Where-Object Level -eq 2).Count
            RecentEvents = @(
                $events |
                    Select-Object -First 10 TimeCreated, Id, ProviderName, LevelDisplayName, Message
            )
        }
    }
}

$memory = if ($operatingSystem.PSObject.Properties.Name -contains "TotalVisibleMemorySize") {
    $totalMemoryGB = [math]::Round($operatingSystem.TotalVisibleMemorySize / 1MB, 2)
    $freeMemoryGB = [math]::Round($operatingSystem.FreePhysicalMemory / 1MB, 2)
    [pscustomobject]@{
        TotalGB = $totalMemoryGB
        FreeGB = $freeMemoryGB
        UsedPercent = if ($totalMemoryGB -gt 0) {
            [math]::Round((($totalMemoryGB - $freeMemoryGB) / $totalMemoryGB) * 100, 1)
        }
        else {
            $null
        }
    }
}
else {
    $operatingSystem
}

$lastBoot = if ($operatingSystem.PSObject.Properties.Name -contains "LastBootUpTime") {
    $operatingSystem.LastBootUpTime
}
else {
    $null
}

$report = [ordered]@{
    SchemaVersion = "1.0"
    CollectedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    ComputerName = $env:COMPUTERNAME
    UserContext = "$env:USERDOMAIN\$env:USERNAME"
    OperatingSystem = if ($operatingSystem.PSObject.Properties.Name -contains "Caption") {
        [pscustomobject]@{
            Caption = $operatingSystem.Caption
            Version = $operatingSystem.Version
            BuildNumber = $operatingSystem.BuildNumber
            Architecture = $operatingSystem.OSArchitecture
            LastBootUpTime = $lastBoot
            UptimeHours = if ($lastBoot) {
                [math]::Round(((Get-Date) - $lastBoot).TotalHours, 1)
            }
            else {
                $null
            }
        }
    }
    else {
        $operatingSystem
    }
    Hardware = if ($computerSystem.PSObject.Properties.Name -contains "Manufacturer") {
        [pscustomobject]@{
            Manufacturer = $computerSystem.Manufacturer
            Model = $computerSystem.Model
            Domain = $computerSystem.Domain
            TotalPhysicalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
        }
    }
    else {
        $computerSystem
    }
    Memory = $memory
    Disks = @($logicalDisks)
    ActiveNetworkAdapters = @($networkAdapters)
    Services = @($serviceHealth)
    PendingReboot = [pscustomobject]@{
        Required = $pendingRebootChecks.Values -contains $true
        Checks = [pscustomobject]$pendingRebootChecks
    }
    SystemEventSummary = $eventSummary
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding UTF8

Write-Host "Diagnostics written to: $OutputPath" -ForegroundColor Green
Write-Output ([pscustomobject]$report)
