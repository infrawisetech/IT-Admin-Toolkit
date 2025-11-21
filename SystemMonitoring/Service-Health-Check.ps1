<#
.SYNOPSIS
    Windows Service Health Monitoring Script
    
.DESCRIPTION
    Monitors critical Windows services, automatically restarts failed services,
    generates health reports, and sends alerts for service failures.
    
.PARAMETER ServiceList
    Array of service names to monitor
    
.PARAMETER AutoRestart
    Automatically attempt to restart failed services
    
.PARAMETER MaxRestartAttempts
    Maximum number of restart attempts before alerting
    
.EXAMPLE
    .\Service-Health-Check.ps1 -ServiceList "Spooler","W32Time" -AutoRestart $true
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.0
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$ServiceList = @(
        "W32Time",           # Windows Time
        "Spooler",          # Print Spooler
        "EventLog",         # Windows Event Log
        "Winmgmt",          # Windows Management Instrumentation
        "RemoteRegistry",   # Remote Registry
        "BITS",             # Background Intelligent Transfer
        "WinRM",            # Windows Remote Management
        "Schedule",         # Task Scheduler
        "Themes",           # Windows Themes
        "AudioSrv"          # Windows Audio
    ),
    
    [Parameter(Mandatory=$false)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    
    [Parameter(Mandatory=$false)]
    [bool]$AutoRestart = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxRestartAttempts = 3,
    
    [Parameter(Mandatory=$false)]
    [bool]$GenerateReport = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\ServiceReports"
)

#region Functions
function Write-ServiceLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Level) {
        "Error" { Write-Host "[$timestamp] $Message" -ForegroundColor Red }
        "Warning" { Write-Host "[$timestamp] $Message" -ForegroundColor Yellow }
        "Success" { Write-Host "[$timestamp] $Message" -ForegroundColor Green }
        default { Write-Host "[$timestamp] $Message" -ForegroundColor Cyan }
    }
    
    # Ensure report path exists
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    # Log to file
    $logFile = Join-Path $ReportPath "ServiceHealth_$(Get-Date -Format 'yyyy-MM-dd').log"
    "[$timestamp] [$Level] $Message" | Add-Content -Path $logFile
}

function Test-ServiceHealth {
    param(
        [string]$Computer,
        [string]$ServiceName
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ComputerName $Computer -ErrorAction Stop
        
        $health = [PSCustomObject]@{
            ComputerName = $Computer
            ServiceName = $service.Name
            DisplayName = $service.DisplayName
            Status = $service.Status
            StartType = $service.StartType
            IsHealthy = $service.Status -eq 'Running'
            CanRestart = $service.Status -eq 'Stopped' -and $service.StartType -ne 'Disabled'
            ErrorMessage = $null
            CheckTime = Get-Date
        }
        
        return $health
    }
    catch {
        return [PSCustomObject]@{
            ComputerName = $Computer
            ServiceName = $ServiceName
            DisplayName = "Unknown"
            Status = "Error"
            StartType = "Unknown"
            IsHealthy = $false
            CanRestart = $false
            ErrorMessage = $_.Exception.Message
            CheckTime = Get-Date
        }
    }
}

function Restart-FailedService {
    param(
        [string]$Computer,
        [string]$ServiceName,
        [int]$MaxAttempts
    )
    
    Write-ServiceLog "Attempting to restart $ServiceName on $Computer..." "Warning"
    
    $attempts = 0
    $success = $false
    
    while ($attempts -lt $MaxAttempts -and -not $success) {
        $attempts++
        
        try {
            Write-ServiceLog "Restart attempt $attempts of $MaxAttempts..." "Info"
            
            # Start the service
            Get-Service -Name $ServiceName -ComputerName $Computer | Start-Service -ErrorAction Stop
            
            # Wait for service to start
            Start-Sleep -Seconds 5
            
            # Verify service is running
            $service = Get-Service -Name $ServiceName -ComputerName $Computer
            if ($service.Status -eq 'Running') {
                $success = $true
                Write-ServiceLog "$ServiceName successfully restarted on $Computer" "Success"
            }
        }
        catch {
            Write-ServiceLog "Restart attempt $attempts failed: $_" "Error"
            Start-Sleep -Seconds 10
        }
    }
    
    if (-not $success) {
        Write-ServiceLog "Failed to restart $ServiceName after $MaxAttempts attempts" "Error"
    }
    
    return $success
}

function Get-ServiceDependencies {
    param(
        [string]$Computer,
        [string]$ServiceName
    )
    
    try {
        $service = Get-WmiObject -Class Win32_Service -ComputerName $Computer -Filter "Name='$ServiceName'"
        $dependencies = @()
        
        # Get services that depend on this service
        $dependentServices = Get-WmiObject -Class Win32_DependentService -ComputerName $Computer |
                            Where-Object { $_.Antecedent -like "*$ServiceName*" }
        
        foreach ($dep in $dependentServices) {
            $depServiceName = ($dep.Dependent -split '"')[1]
            $depService = Get-Service -Name $depServiceName -ComputerName $Computer -ErrorAction SilentlyContinue
            if ($depService) {
                $dependencies += $depService.DisplayName
            }
        }
        
        return $dependencies
    }
    catch {
        return @()
    }
}

function New-ServiceHealthReport {
    param(
        [array]$HealthData
    )
    
    Write-ServiceLog "Generating HTML health report..." "Info"
    
    # Calculate statistics
    $totalServices = $HealthData.Count
    $runningServices = ($HealthData | Where-Object { $_.Status -eq 'Running' }).Count
    $stoppedServices = ($HealthData | Where-Object { $_.Status -eq 'Stopped' }).Count
    $errorServices = ($HealthData | Where-Object { $_.Status -eq 'Error' }).Count
    $healthPercentage = [math]::Round(($runningServices / $totalServices) * 100, 2)
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Service Health Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
    <meta charset="UTF-8">
    <style>
        body {
            font-family: 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            margin: 0;
            padding: 20px;
            color: #333;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            margin: 0;
            font-size: 2.5em;
        }
        
        .stats {
            display: flex;
            justify-content: space-around;
            padding: 30px;
            background: #f8f9fa;
        }
        
        .stat-card {
            text-align: center;
            padding: 20px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            min-width: 150px;
        }
        
        .stat-number {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .running { color: #28a745; }
        .stopped { color: #ffc107; }
        .error { color: #dc3545; }
        
        .health-meter {
            width: 200px;
            height: 200px;
            margin: 20px auto;
            position: relative;
        }
        
        .health-circle {
            width: 100%;
            height: 100%;
            border-radius: 50%;
            background: conic-gradient(
                #28a745 0deg $([int]($healthPercentage * 3.6))deg,
                #e9ecef $([int]($healthPercentage * 3.6))deg 360deg
            );
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .health-inner {
            width: 160px;
            height: 160px;
            background: white;
            border-radius: 50%;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        
        .health-percentage {
            font-size: 3em;
            font-weight: bold;
            color: #333;
        }
        
        .health-label {
            color: #666;
            font-size: 0.9em;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        th {
            background: #f8f9fa;
            padding: 15px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #dee2e6;
        }
        
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #e9ecef;
        }
        
        tr:hover {
            background: #f8f9fa;
        }
        
        .status-badge {
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
            display: inline-block;
        }
        
        .status-running {
            background: #d4edda;
            color: #155724;
        }
        
        .status-stopped {
            background: #fff3cd;
            color: #856404;
        }
        
        .status-error {
            background: #f8d7da;
            color: #721c24;
        }
        
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔧 Service Health Monitor</h1>
            <p>Report Generated: $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss')</p>
            <p>by Aykut Yıldız | IT Admin Toolkit</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-number">$totalServices</div>
                <div>Total Services</div>
            </div>
            <div class="stat-card">
                <div class="stat-number running">$runningServices</div>
                <div>Running</div>
            </div>
            <div class="stat-card">
                <div class="stat-number stopped">$stoppedServices</div>
                <div>Stopped</div>
            </div>
            <div class="stat-card">
                <div class="stat-number error">$errorServices</div>
                <div>Errors</div>
            </div>
        </div>
        
        <div class="health-meter">
            <div class="health-circle">
                <div class="health-inner">
                    <div class="health-percentage">$healthPercentage%</div>
                    <div class="health-label">Service Health</div>
                </div>
            </div>
        </div>
        
        <table>
            <thead>
                <tr>
                    <th>Computer</th>
                    <th>Service</th>
                    <th>Display Name</th>
                    <th>Status</th>
                    <th>Start Type</th>
                    <th>Last Check</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($service in $HealthData | Sort-Object ComputerName, ServiceName) {
        $statusClass = switch($service.Status) {
            'Running' { 'running' }
            'Stopped' { 'stopped' }
            default { 'error' }
        }
        
        $htmlReport += @"
                <tr>
                    <td>$($service.ComputerName)</td>
                    <td>$($service.ServiceName)</td>
                    <td>$($service.DisplayName)</td>
                    <td><span class="status-badge status-$statusClass">$($service.Status)</span></td>
                    <td>$($service.StartType)</td>
                    <td>$($service.CheckTime.ToString('HH:mm:ss'))</td>
                </tr>
"@
    }

    $htmlReport += @"
            </tbody>
        </table>
        
        <div class="footer">
            <p>PowerShell Service Health Monitor v1.0</p>
            <p>Automated monitoring and restart capabilities enabled</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "ServiceHealth_$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-ServiceLog "Report saved to: $reportFile" "Success"
    return $reportFile
}
#endregion

#region Main Script
function Main {
    Write-Host @"
╔════════════════════════════════════════════════════════════╗
║         Windows Service Health Monitor v1.0                ║
║         PowerShell Automation by Aykut Yıldız             ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    $allHealthData = @()
    $failedServices = @()
    
    foreach ($computer in $ComputerName) {
        Write-Host ""
        Write-Host "Checking services on $computer..." -ForegroundColor Yellow
        Write-Host "─────────────────────────────────" -ForegroundColor Gray
        
        foreach ($serviceName in $ServiceList) {
            $health = Test-ServiceHealth -Computer $computer -ServiceName $serviceName
            $allHealthData += $health
            
            if ($health.IsHealthy) {
                Write-ServiceLog "$($health.ServiceName) is running on $computer" "Success"
            } else {
                Write-ServiceLog "$($health.ServiceName) is $($health.Status) on $computer" "Warning"
                
                if ($AutoRestart -and $health.CanRestart) {
                    $restartSuccess = Restart-FailedService -Computer $computer `
                                                            -ServiceName $serviceName `
                                                            -MaxAttempts $MaxRestartAttempts
                    
                    if (-not $restartSuccess) {
                        $failedServices += $health
                    }
                } else {
                    $failedServices += $health
                }
            }
        }
    }
    
    # Generate report
    if ($GenerateReport) {
        $reportFile = New-ServiceHealthReport -HealthData $allHealthData
        Start-Process $reportFile
    }
    
    # Summary
    Write-Host ""
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "        SERVICE HEALTH CHECK COMPLETE" -ForegroundColor Green  
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    $healthyCount = ($allHealthData | Where-Object { $_.IsHealthy }).Count
    Write-Host "✅ Healthy Services: $healthyCount / $($allHealthData.Count)" -ForegroundColor Green
    
    if ($failedServices.Count -gt 0) {
        Write-Host "❌ Failed Services: $($failedServices.Count)" -ForegroundColor Red
        foreach ($failed in $failedServices) {
            Write-Host "   - $($failed.ComputerName): $($failed.ServiceName)" -ForegroundColor Red
        }
    }
}

# Run the script
Main
#endregion
