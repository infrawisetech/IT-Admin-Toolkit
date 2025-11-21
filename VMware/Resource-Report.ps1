<#
.SYNOPSIS
    VMware vCenter Resource Utilization Report
    
.DESCRIPTION
    Generates comprehensive resource utilization reports for vCenter environment
    including CPU, Memory, Storage, and VM performance metrics.
    
.PARAMETER vCenter
    vCenter server address
    
.PARAMETER ReportType
    Type of report: Summary, Detailed, Capacity, Performance
    
.EXAMPLE
    .\Resource-Report.ps1 -vCenter "vcenter.local" -ReportType "Detailed"
    
.NOTES
    Author: Aykut Yıldız
    Version: 2.1
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$vCenter,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Summary", "Detailed", "Capacity", "Performance")]
    [string]$ReportType = "Summary",
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\VMReports",
    
    [Parameter(Mandatory=$false)]
    [bool]$IncludeVMs = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$ExportCSV = $true
)

#region Functions
function Get-ClusterResources {
    Write-Host "📊 Analyzing cluster resources..." -ForegroundColor Cyan
    
    $clusters = Get-Cluster
    $clusterData = @()
    
    foreach ($cluster in $clusters) {
        $hosts = Get-VMHost -Location $cluster
        $vms = Get-VM -Location $cluster
        
        $clusterInfo = [PSCustomObject]@{
            ClusterName = $cluster.Name
            TotalHosts = $hosts.Count
            TotalVMs = $vms.Count
            TotalCPU = [math]::Round(($hosts | Measure-Object -Property NumCpu -Sum).Sum, 0)
            TotalMemoryGB = [math]::Round(($hosts | Measure-Object -Property MemoryTotalGB -Sum).Sum, 2)
            UsedMemoryGB = [math]::Round(($hosts | Measure-Object -Property MemoryUsageGB -Sum).Sum, 2)
            MemoryUsagePercent = 0
            TotalVMCPU = ($vms | Measure-Object -Property NumCpu -Sum).Sum
            TotalVMMemoryGB = [math]::Round(($vms | Measure-Object -Property MemoryGB -Sum).Sum, 2)
            PoweredOnVMs = ($vms | Where-Object {$_.PowerState -eq 'PoweredOn'}).Count
            HAEnabled = $cluster.HAEnabled
            DRSEnabled = $cluster.DrsEnabled
            DRSAutomationLevel = $cluster.DrsAutomationLevel
        }
        
        if ($clusterInfo.TotalMemoryGB -gt 0) {
            $clusterInfo.MemoryUsagePercent = [math]::Round(($clusterInfo.UsedMemoryGB / $clusterInfo.TotalMemoryGB) * 100, 2)
        }
        
        $clusterData += $clusterInfo
        
        Write-Host "   • $($cluster.Name): $($clusterInfo.TotalVMs) VMs, $($clusterInfo.MemoryUsagePercent)% Memory Used" -ForegroundColor Gray
    }
    
    return $clusterData
}

function Get-DatastoreUsage {
    Write-Host "💾 Analyzing datastore usage..." -ForegroundColor Cyan
    
    $datastores = Get-Datastore
    $datastoreData = @()
    
    foreach ($ds in $datastores) {
        $usage = [PSCustomObject]@{
            DatastoreName = $ds.Name
            Type = $ds.Type
            State = $ds.State
            CapacityGB = [math]::Round($ds.CapacityGB, 2)
            FreeSpaceGB = [math]::Round($ds.FreeSpaceGB, 2)
            UsedSpaceGB = [math]::Round($ds.CapacityGB - $ds.FreeSpaceGB, 2)
            UsagePercent = [math]::Round((($ds.CapacityGB - $ds.FreeSpaceGB) / $ds.CapacityGB) * 100, 2)
            VMCount = (Get-VM -Datastore $ds).Count
            Status = "OK"
        }
        
        # Set status based on usage
        if ($usage.UsagePercent -ge 90) {
            $usage.Status = "Critical"
        } elseif ($usage.UsagePercent -ge 80) {
            $usage.Status = "Warning"
        }
        
        $datastoreData += $usage
        
        Write-Host "   • $($ds.Name): $($usage.UsagePercent)% used ($($usage.FreeSpaceGB)GB free)" -ForegroundColor Gray
    }
    
    return $datastoreData
}

function Get-VMPerformance {
    Write-Host "⚡ Analyzing VM performance..." -ForegroundColor Cyan
    
    $vms = Get-VM | Where-Object {$_.PowerState -eq 'PoweredOn'}
    $vmData = @()
    
    foreach ($vm in $vms | Select-Object -First 50) {  # Limit to 50 VMs for performance
        $stats = Get-Stat -Entity $vm -Stat cpu.usage.average,mem.usage.average -Realtime -MaxSamples 1 -ErrorAction SilentlyContinue
        
        $cpuUsage = ($stats | Where-Object {$_.MetricId -eq 'cpu.usage.average'} | Select-Object -First 1).Value
        $memUsage = ($stats | Where-Object {$_.MetricId -eq 'mem.usage.average'} | Select-Object -First 1).Value
        
        $vmInfo = [PSCustomObject]@{
            VMName = $vm.Name
            PowerState = $vm.PowerState
            Host = $vm.VMHost.Name
            Cluster = (Get-Cluster -VM $vm -ErrorAction SilentlyContinue).Name
            NumCPU = $vm.NumCpu
            MemoryGB = $vm.MemoryGB
            CPUUsagePercent = [math]::Round($cpuUsage, 2)
            MemUsagePercent = [math]::Round($memUsage, 2)
            ProvisionedGB = [math]::Round($vm.ProvisionedSpaceGB, 2)
            UsedGB = [math]::Round($vm.UsedSpaceGB, 2)
            GuestOS = $vm.GuestId
            ToolsStatus = $vm.ExtensionData.Guest.ToolsStatus
            Notes = $vm.Notes
        }
        
        $vmData += $vmInfo
    }
    
    return $vmData
}

function Get-HostPerformance {
    Write-Host "🖥️ Analyzing host performance..." -ForegroundColor Cyan
    
    $hosts = Get-VMHost
    $hostData = @()
    
    foreach ($esxHost in $hosts) {
        $hostInfo = [PSCustomObject]@{
            HostName = $esxHost.Name
            State = $esxHost.ConnectionState
            PowerState = $esxHost.PowerState
            Model = $esxHost.Model
            NumCPU = $esxHost.NumCpu
            CPUMhz = $esxHost.CpuTotalMhz
            CPUUsageMhz = $esxHost.CpuUsageMhz
            CPUUsagePercent = [math]::Round(($esxHost.CpuUsageMhz / $esxHost.CpuTotalMhz) * 100, 2)
            MemoryTotalGB = [math]::Round($esxHost.MemoryTotalGB, 2)
            MemoryUsageGB = [math]::Round($esxHost.MemoryUsageGB, 2)
            MemoryUsagePercent = [math]::Round(($esxHost.MemoryUsageGB / $esxHost.MemoryTotalGB) * 100, 2)
            VMCount = (Get-VM -Location $esxHost).Count
            Version = $esxHost.Version
            Build = $esxHost.Build
            Uptime = (New-TimeSpan -Start $esxHost.ExtensionData.Runtime.BootTime -End (Get-Date)).Days
        }
        
        $hostData += $hostInfo
        
        Write-Host "   • $($esxHost.Name): CPU $($hostInfo.CPUUsagePercent)%, Memory $($hostInfo.MemoryUsagePercent)%" -ForegroundColor Gray
    }
    
    return $hostData
}

function New-ResourceReport {
    param(
        $ClusterData,
        $DatastoreData,
        $HostData,
        $VMData
    )
    
    Write-Host "📝 Generating resource report..." -ForegroundColor Yellow
    
    # Calculate totals
    $totalCPU = ($HostData | Measure-Object -Property NumCPU -Sum).Sum
    $totalMemoryGB = [math]::Round(($HostData | Measure-Object -Property MemoryTotalGB -Sum).Sum, 2)
    $totalStorageGB = [math]::Round(($DatastoreData | Measure-Object -Property CapacityGB -Sum).Sum, 2)
    $totalVMs = ($VMData).Count
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>vCenter Resource Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #43cea2 0%, #185a9d 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1600px;
            margin: 0 auto;
        }
        .header {
            background: white;
            border-radius: 15px;
            padding: 40px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            text-align: center;
        }
        h1 {
            color: #2c3e50;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .overview {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .metric-card {
            background: white;
            border-radius: 15px;
            padding: 30px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        .metric-card:hover {
            transform: translateY(-5px);
        }
        .metric-value {
            font-size: 3em;
            font-weight: bold;
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .metric-label {
            color: #7f8c8d;
            text-transform: uppercase;
            letter-spacing: 1px;
            font-size: 0.9em;
        }
        .section {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        h2 {
            color: #2c3e50;
            margin-bottom: 25px;
            padding-bottom: 15px;
            border-bottom: 3px solid #3498db;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th {
            background: linear-gradient(135deg, #43cea2 0%, #185a9d 100%);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 500;
        }
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #ecf0f1;
        }
        tr:hover {
            background: #f8f9fa;
        }
        .status-ok { color: #27ae60; font-weight: bold; }
        .status-warning { color: #f39c12; font-weight: bold; }
        .status-critical { color: #e74c3c; font-weight: bold; }
        .progress-bar {
            width: 100%;
            height: 25px;
            background: #ecf0f1;
            border-radius: 12px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #27ae60, #2ecc71);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 0.85em;
        }
        .progress-fill.warning {
            background: linear-gradient(90deg, #f39c12, #f1c40f);
        }
        .progress-fill.critical {
            background: linear-gradient(90deg, #e74c3c, #c0392b);
        }
        .footer {
            background: white;
            border-radius: 15px;
            padding: 25px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            color: #7f8c8d;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 vCenter Resource Utilization Report</h1>
            <p><strong>vCenter Server:</strong> $vCenter</p>
            <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p><strong>Report Type:</strong> $ReportType | <strong>By:</strong> Aykut Yıldız</p>
        </div>
        
        <div class="overview">
            <div class="metric-card">
                <div class="metric-value">$($HostData.Count)</div>
                <div class="metric-label">ESXi Hosts</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$totalVMs</div>
                <div class="metric-label">Virtual Machines</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$totalCPU</div>
                <div class="metric-label">Total vCPUs</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$totalMemoryGB GB</div>
                <div class="metric-label">Total Memory</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">$([math]::Round($totalStorageGB/1024, 2)) TB</div>
                <div class="metric-label">Total Storage</div>
            </div>
        </div>
"@

    # Cluster Section
    if ($ClusterData) {
        $htmlReport += @"
        <div class="section">
            <h2>🏢 Cluster Resources</h2>
            <table>
                <thead>
                    <tr>
                        <th>Cluster Name</th>
                        <th>Hosts</th>
                        <th>VMs</th>
                        <th>Total CPU</th>
                        <th>Memory (GB)</th>
                        <th>Memory Usage</th>
                        <th>HA</th>
                        <th>DRS</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($cluster in $ClusterData) {
            $memClass = if ($cluster.MemoryUsagePercent -ge 80) { "critical" } 
                       elseif ($cluster.MemoryUsagePercent -ge 70) { "warning" }
                       else { "" }
            
            $htmlReport += @"
                    <tr>
                        <td><strong>$($cluster.ClusterName)</strong></td>
                        <td>$($cluster.TotalHosts)</td>
                        <td>$($cluster.TotalVMs)</td>
                        <td>$($cluster.TotalCPU)</td>
                        <td>$($cluster.TotalMemoryGB)</td>
                        <td>
                            <div class="progress-bar">
                                <div class="progress-fill $memClass" style="width: $($cluster.MemoryUsagePercent)%;">
                                    $($cluster.MemoryUsagePercent)%
                                </div>
                            </div>
                        </td>
                        <td>$(if($cluster.HAEnabled){'✅'}else{'❌'})</td>
                        <td>$(if($cluster.DRSEnabled){'✅'}else{'❌'})</td>
                    </tr>
"@
        }
        $htmlReport += @"
                </tbody>
            </table>
        </div>
"@
    }

    # Datastore Section
    if ($DatastoreData) {
        $htmlReport += @"
        <div class="section">
            <h2>💾 Datastore Usage</h2>
            <table>
                <thead>
                    <tr>
                        <th>Datastore Name</th>
                        <th>Type</th>
                        <th>Capacity (GB)</th>
                        <th>Used (GB)</th>
                        <th>Free (GB)</th>
                        <th>Usage</th>
                        <th>VMs</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($ds in $DatastoreData | Sort-Object UsagePercent -Descending) {
            $usageClass = if ($ds.UsagePercent -ge 90) { "critical" }
                         elseif ($ds.UsagePercent -ge 80) { "warning" }
                         else { "" }
            
            $statusClass = switch($ds.Status) {
                "Critical" { "status-critical" }
                "Warning" { "status-warning" }
                default { "status-ok" }
            }
            
            $htmlReport += @"
                    <tr>
                        <td><strong>$($ds.DatastoreName)</strong></td>
                        <td>$($ds.Type)</td>
                        <td>$($ds.CapacityGB)</td>
                        <td>$($ds.UsedSpaceGB)</td>
                        <td>$($ds.FreeSpaceGB)</td>
                        <td>
                            <div class="progress-bar">
                                <div class="progress-fill $usageClass" style="width: $($ds.UsagePercent)%;">
                                    $($ds.UsagePercent)%
                                </div>
                            </div>
                        </td>
                        <td>$($ds.VMCount)</td>
                        <td class="$statusClass">$($ds.Status)</td>
                    </tr>
"@
        }
        $htmlReport += @"
                </tbody>
            </table>
        </div>
"@
    }

    # Host Performance Section
    if ($HostData) {
        $htmlReport += @"
        <div class="section">
            <h2>🖥️ ESXi Host Performance</h2>
            <table>
                <thead>
                    <tr>
                        <th>Host Name</th>
                        <th>State</th>
                        <th>Model</th>
                        <th>CPU Usage</th>
                        <th>Memory Usage</th>
                        <th>VMs</th>
                        <th>Version</th>
                        <th>Uptime (Days)</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($host in $HostData) {
            $cpuClass = if ($host.CPUUsagePercent -ge 80) { "critical" }
                       elseif ($host.CPUUsagePercent -ge 70) { "warning" }
                       else { "" }
            
            $memClass = if ($host.MemoryUsagePercent -ge 80) { "critical" }
                       elseif ($host.MemoryUsagePercent -ge 70) { "warning" }
                       else { "" }
            
            $htmlReport += @"
                    <tr>
                        <td><strong>$($host.HostName)</strong></td>
                        <td>$($host.State)</td>
                        <td>$($host.Model)</td>
                        <td>
                            <div class="progress-bar">
                                <div class="progress-fill $cpuClass" style="width: $($host.CPUUsagePercent)%;">
                                    $($host.CPUUsagePercent)%
                                </div>
                            </div>
                        </td>
                        <td>
                            <div class="progress-bar">
                                <div class="progress-fill $memClass" style="width: $($host.MemoryUsagePercent)%;">
                                    $($host.MemoryUsagePercent)%
                                </div>
                            </div>
                        </td>
                        <td>$($host.VMCount)</td>
                        <td>$($host.Version)</td>
                        <td>$($host.Uptime)</td>
                    </tr>
"@
        }
        $htmlReport += @"
                </tbody>
            </table>
        </div>
"@
    }

    $htmlReport += @"
        <div class="footer">
            <p><strong>VMware Resource Report v2.1</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "ResourceReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    return $reportFile
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║       vCenter Resource Utilization Report v2.1             ║
║       PowerShell Automation by Aykut Yıldız               ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Check PowerCLI
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "Installing VMware PowerCLI..." -ForegroundColor Yellow
    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
}
Import-Module VMware.PowerCLI -ErrorAction SilentlyContinue

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

# Connect to vCenter
Write-Host ""
Write-Host "🔌 Connecting to vCenter: $vCenter" -ForegroundColor Cyan
try {
    if ($Credential) {
        Connect-VIServer -Server $vCenter -Credential $Credential -ErrorAction Stop | Out-Null
    } else {
        Connect-VIServer -Server $vCenter -ErrorAction Stop | Out-Null
    }
    Write-Host "✅ Connected successfully" -ForegroundColor Green
}
catch {
    Write-Host "❌ Connection failed: $_" -ForegroundColor Red
    return
}

Write-Host ""

# Collect data based on report type
$clusterData = $null
$datastoreData = $null
$hostData = $null
$vmData = $null

switch ($ReportType) {
    "Summary" {
        $clusterData = Get-ClusterResources
        $datastoreData = Get-DatastoreUsage
        $hostData = Get-HostPerformance
    }
    "Detailed" {
        $clusterData = Get-ClusterResources
        $datastoreData = Get-DatastoreUsage
        $hostData = Get-HostPerformance
        if ($IncludeVMs) {
            $vmData = Get-VMPerformance
        }
    }
    "Capacity" {
        $clusterData = Get-ClusterResources
        $datastoreData = Get-DatastoreUsage
    }
    "Performance" {
        $hostData = Get-HostPerformance
        if ($IncludeVMs) {
            $vmData = Get-VMPerformance
        }
    }
}

# Generate report
Write-Host ""
$reportFile = New-ResourceReport -ClusterData $clusterData `
                                 -DatastoreData $datastoreData `
                                 -HostData $hostData `
                                 -VMData $vmData

# Export to CSV if requested
if ($ExportCSV) {
    if ($clusterData) {
        $clusterData | Export-Csv -Path (Join-Path $ReportPath "Clusters_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
    if ($datastoreData) {
        $datastoreData | Export-Csv -Path (Join-Path $ReportPath "Datastores_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
    if ($hostData) {
        $hostData | Export-Csv -Path (Join-Path $ReportPath "Hosts_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
    if ($vmData) {
        $vmData | Export-Csv -Path (Join-Path $ReportPath "VMs_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
}

# Disconnect from vCenter
Write-Host ""
Write-Host "🔌 Disconnecting from vCenter..." -ForegroundColor Cyan
Disconnect-VIServer -Confirm:$false

Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "         RESOURCE REPORT COMPLETE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Report saved: $reportFile" -ForegroundColor Cyan

# Open report
Start-Process $reportFile
#endregion
