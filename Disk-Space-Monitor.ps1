<#
.SYNOPSIS
    Disk Space Monitoring and Cleanup Script
    
.DESCRIPTION
    Monitors disk space usage across local and remote servers, generates reports,
    sends alerts when thresholds are exceeded, and provides cleanup recommendations.
    
.PARAMETER ComputerName
    Single computer or array of computers to monitor (Default: localhost)
    
.PARAMETER ThresholdPercent
    Disk usage percentage that triggers warnings (Default: 85)
    
.PARAMETER CriticalPercent
    Disk usage percentage that triggers critical alerts (Default: 95)
    
.PARAMETER CleanupOldFiles
    Automatically cleanup temp files older than specified days
    
.PARAMETER GenerateReport
    Generate HTML report of disk usage
    
.EXAMPLE
    .\Disk-Space-Monitor.ps1 -ComputerName "SERVER01","SERVER02" -ThresholdPercent 80
    
.EXAMPLE
    .\Disk-Space-Monitor.ps1 -CleanupOldFiles 30 -GenerateReport $true
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.5
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    
    [Parameter(Mandatory=$false)]
    [int]$ThresholdPercent = 85,
    
    [Parameter(Mandatory=$false)]
    [int]$CriticalPercent = 95,
    
    [Parameter(Mandatory=$false)]
    [int]$CleanupOldFiles = 0,
    
    [Parameter(Mandatory=$false)]
    [bool]$GenerateReport = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\DiskReports",
    
    [Parameter(Mandatory=$false)]
    [bool]$SendEmail = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpServer = "smtp.company.local",
    
    [Parameter(Mandatory=$false)]
    [string]$EmailTo = "it-team@company.com"
)

#region Functions
function Write-ColorLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    switch ($Level) {
        "Critical" { 
            Write-Host $logMessage -ForegroundColor Red -BackgroundColor Yellow
            $script:criticalIssues += $Message
        }
        "Warning" { 
            Write-Host $logMessage -ForegroundColor Yellow 
            $script:warnings += $Message
        }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
        "Info" { Write-Host $logMessage -ForegroundColor Cyan }
        default { Write-Host $logMessage }
    }
    
    # Log to file
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    $logFile = Join-Path $ReportPath "DiskMonitor_$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $logFile -Value $logMessage
}

function Get-DiskSpaceInfo {
    param(
        [string]$Computer
    )
    
    Write-ColorLog "Checking disk space on $Computer..." "Info"
    
    try {
        $disks = Get-WmiObject -Class Win32_LogicalDisk -ComputerName $Computer -Filter "DriveType=3" -ErrorAction Stop
        
        $diskInfo = @()
        foreach ($disk in $disks) {
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB = $totalGB - $freeGB
            $percentUsed = [math]::Round(($usedGB / $totalGB) * 100, 2)
            
            $status = if ($percentUsed -ge $CriticalPercent) { "Critical" }
                     elseif ($percentUsed -ge $ThresholdPercent) { "Warning" }
                     else { "OK" }
            
            $diskObj = [PSCustomObject]@{
                ComputerName = $Computer
                DriveLetter = $disk.DeviceID
                VolumeName = $disk.VolumeName
                TotalGB = $totalGB
                UsedGB = $usedGB
                FreeGB = $freeGB
                PercentUsed = $percentUsed
                Status = $status
            }
            
            $diskInfo += $diskObj
            
            # Log based on status
            if ($status -eq "Critical") {
                Write-ColorLog "$Computer - Drive $($disk.DeviceID): $percentUsed% used (CRITICAL)" "Critical"
            } elseif ($status -eq "Warning") {
                Write-ColorLog "$Computer - Drive $($disk.DeviceID): $percentUsed% used (WARNING)" "Warning"
            } else {
                Write-ColorLog "$Computer - Drive $($disk.DeviceID): $percentUsed% used (OK)" "Success"
            }
        }
        
        return $diskInfo
    }
    catch {
        Write-ColorLog "Failed to get disk info from $Computer : $_" "Critical"
        return $null
    }
}

function Get-FolderSizes {
    param(
        [string]$Computer,
        [string]$Drive
    )
    
    Write-ColorLog "Analyzing folder sizes on $Computer $Drive..." "Info"
    
    $folders = @(
        "\\$Computer\$($Drive.Replace(':','$'))\Windows\Temp",
        "\\$Computer\$($Drive.Replace(':','$'))\Windows\SoftwareDistribution",
        "\\$Computer\$($Drive.Replace(':','$'))\Windows\Logs",
        "\\$Computer\$($Drive.Replace(':','$'))\inetpub\logs",
        "\\$Computer\$($Drive.Replace(':','$'))\ProgramData\Microsoft\Windows\WER",
        "\\$Computer\$($Drive.Replace(':','$'))\Windows\System32\LogFiles"
    )
    
    $folderSizes = @()
    foreach ($folder in $folders) {
        if (Test-Path $folder -ErrorAction SilentlyContinue) {
            try {
                $size = (Get-ChildItem $folder -Recurse -ErrorAction SilentlyContinue | 
                        Measure-Object -Property Length -Sum).Sum / 1GB
                
                $folderSizes += [PSCustomObject]@{
                    Path = $folder
                    SizeGB = [math]::Round($size, 2)
                    CanClean = $true
                }
            }
            catch {
                # Skip folders we can't access
            }
        }
    }
    
    return $folderSizes | Sort-Object SizeGB -Descending | Select-Object -First 10
}

function Invoke-DiskCleanup {
    param(
        [string]$Computer,
        [string]$Drive,
        [int]$DaysOld
    )
    
    if ($DaysOld -eq 0) { return }
    
    Write-ColorLog "Starting cleanup on $Computer $Drive (files older than $DaysOld days)..." "Info"
    
    $cleanupPaths = @(
        "\\$Computer\$($Drive.Replace(':','$'))\Windows\Temp",
        "\\$Computer\$($Drive.Replace(':','$'))\Temp",
        "\\$Computer\$($Drive.Replace(':','$'))\Windows\Prefetch"
    )
    
    $totalCleaned = 0
    $dateLimit = (Get-Date).AddDays(-$DaysOld)
    
    foreach ($path in $cleanupPaths) {
        if (Test-Path $path -ErrorAction SilentlyContinue) {
            try {
                $filesToDelete = Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
                                Where-Object { $_.LastWriteTime -lt $dateLimit }
                
                $sizeToClean = ($filesToDelete | Measure-Object -Property Length -Sum).Sum / 1MB
                
                $filesToDelete | Remove-Item -Force -ErrorAction SilentlyContinue
                
                $totalCleaned += $sizeToClean
                Write-ColorLog "Cleaned $([math]::Round($sizeToClean, 2)) MB from $path" "Success"
            }
            catch {
                Write-ColorLog "Could not clean $path : $_" "Warning"
            }
        }
    }
    
    Write-ColorLog "Total cleaned: $([math]::Round($totalCleaned, 2)) MB" "Success"
    return $totalCleaned
}

function New-DiskSpaceReport {
    param(
        [array]$DiskData
    )
    
    Write-ColorLog "Generating HTML report..." "Info"
    
    $htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Disk Space Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }
        
        .header h1 {
            color: #333;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header .subtitle {
            color: #666;
            font-size: 1.1em;
        }
        
        .summary-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
        }
        
        .card .value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .card .label {
            color: #666;
            font-size: 0.9em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .card.critical { border-left: 5px solid #e74c3c; }
        .card.critical .value { color: #e74c3c; }
        
        .card.warning { border-left: 5px solid #f39c12; }
        .card.warning .value { color: #f39c12; }
        
        .card.success { border-left: 5px solid #27ae60; }
        .card.success .value { color: #27ae60; }
        
        .disk-grid {
            display: grid;
            gap: 20px;
        }
        
        .disk-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
        }
        
        .disk-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        
        .disk-title {
            font-size: 1.3em;
            font-weight: bold;
            color: #333;
        }
        
        .status-badge {
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
            text-transform: uppercase;
        }
        
        .status-ok { background: #d4edda; color: #155724; }
        .status-warning { background: #fff3cd; color: #856404; }
        .status-critical { background: #f8d7da; color: #721c24; }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #ecf0f1;
            border-radius: 15px;
            overflow: hidden;
            margin: 15px 0;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #27ae60, #2ecc71);
            transition: width 0.5s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        
        .progress-fill.warning {
            background: linear-gradient(90deg, #f39c12, #f1c40f);
        }
        
        .progress-fill.critical {
            background: linear-gradient(90deg, #e74c3c, #c0392b);
        }
        
        .disk-details {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 15px;
            margin-top: 20px;
            padding-top: 20px;
            border-top: 1px solid #ecf0f1;
        }
        
        .detail-item {
            text-align: center;
        }
        
        .detail-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #333;
        }
        
        .detail-label {
            color: #95a5a6;
            font-size: 0.9em;
            margin-top: 5px;
        }
        
        .footer {
            text-align: center;
            margin-top: 40px;
            color: white;
            font-size: 0.9em;
        }
        
        @media (max-width: 768px) {
            .summary-cards {
                grid-template-columns: 1fr;
            }
            
            .disk-details {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>💾 Disk Space Monitoring Report</h1>
            <div class="subtitle">Generated by Aykut Yıldız | $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss')</div>
        </div>
        
        <div class="summary-cards">
"@

    # Calculate summary statistics
    $totalServers = ($DiskData | Select-Object -Unique ComputerName).Count
    $criticalDisks = ($DiskData | Where-Object { $_.Status -eq "Critical" }).Count
    $warningDisks = ($DiskData | Where-Object { $_.Status -eq "Warning" }).Count
    $totalSpace = [math]::Round(($DiskData | Measure-Object -Property TotalGB -Sum).Sum, 2)
    $totalFree = [math]::Round(($DiskData | Measure-Object -Property FreeGB -Sum).Sum, 2)
    
    $htmlReport += @"
            <div class="card success">
                <div class="value">$totalServers</div>
                <div class="label">Servers Monitored</div>
            </div>
            <div class="card $(if($criticalDisks -gt 0){'critical'}else{'success'})">
                <div class="value">$criticalDisks</div>
                <div class="label">Critical Disks</div>
            </div>
            <div class="card $(if($warningDisks -gt 0){'warning'}else{'success'})">
                <div class="value">$warningDisks</div>
                <div class="label">Warning Disks</div>
            </div>
            <div class="card">
                <div class="value">$totalFree GB</div>
                <div class="label">Total Free Space</div>
            </div>
        </div>
        
        <div class="disk-grid">
"@

    foreach ($disk in $DiskData) {
        $statusClass = switch($disk.Status) {
            "Critical" { "critical" }
            "Warning" { "warning" }
            default { "ok" }
        }
        
        $progressClass = if ($disk.PercentUsed -ge $CriticalPercent) { "critical" }
                        elseif ($disk.PercentUsed -ge $ThresholdPercent) { "warning" }
                        else { "" }
        
        $htmlReport += @"
            <div class="disk-card">
                <div class="disk-header">
                    <div class="disk-title">$($disk.ComputerName) - $($disk.DriveLetter)</div>
                    <div class="status-badge status-$statusClass">$($disk.Status)</div>
                </div>
                
                <div class="progress-bar">
                    <div class="progress-fill $progressClass" style="width: $($disk.PercentUsed)%;">
                        $($disk.PercentUsed)%
                    </div>
                </div>
                
                <div class="disk-details">
                    <div class="detail-item">
                        <div class="detail-value">$($disk.TotalGB) GB</div>
                        <div class="detail-label">Total Space</div>
                    </div>
                    <div class="detail-item">
                        <div class="detail-value">$($disk.UsedGB) GB</div>
                        <div class="detail-label">Used Space</div>
                    </div>
                    <div class="detail-item">
                        <div class="detail-value">$($disk.FreeGB) GB</div>
                        <div class="detail-label">Free Space</div>
                    </div>
                </div>
            </div>
"@
    }

    $htmlReport += @"
        </div>
        
        <div class="footer">
            PowerShell Disk Monitoring Tool v1.5 | IT Admin Toolkit
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "DiskReport_$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-ColorLog "Report saved to: $reportFile" "Success"
    return $reportFile
}
#endregion

#region Main Script
function Main {
    Write-Host @"
╔════════════════════════════════════════════════════════════╗
║           Disk Space Monitoring Tool v1.5                  ║
║           PowerShell Automation by Aykut Yıldız           ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    # Initialize collections
    $script:criticalIssues = @()
    $script:warnings = @()
    $allDiskData = @()
    
    # Check each computer
    foreach ($computer in $ComputerName) {
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        Write-Host "  Checking: $computer" -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        
        $diskInfo = Get-DiskSpaceInfo -Computer $computer
        
        if ($diskInfo) {
            $allDiskData += $diskInfo
            
            # Check for critical disks and analyze
            $criticalDisks = $diskInfo | Where-Object { $_.Status -in @("Critical", "Warning") }
            
            foreach ($disk in $criticalDisks) {
                Write-Host ""
                Write-ColorLog "Analyzing $($disk.DriveLetter) on $computer..." "Info"
                
                # Get folder sizes for problem disks
                $folderSizes = Get-FolderSizes -Computer $computer -Drive $disk.DriveLetter
                
                if ($folderSizes) {
                    Write-Host ""
                    Write-Host "  Top Space Consumers:" -ForegroundColor Yellow
                    foreach ($folder in $folderSizes | Select-Object -First 5) {
                        Write-Host "    • $($folder.Path): $($folder.SizeGB) GB" -ForegroundColor Gray
                    }
                }
                
                # Perform cleanup if requested
                if ($CleanupOldFiles -gt 0 -and $disk.Status -eq "Critical") {
                    Invoke-DiskCleanup -Computer $computer -Drive $disk.DriveLetter -DaysOld $CleanupOldFiles
                }
            }
        }
    }
    
    # Generate report
    if ($GenerateReport -and $allDiskData.Count -gt 0) {
        $reportFile = New-DiskSpaceReport -DiskData $allDiskData
        Start-Process $reportFile
    }
    
    # Summary
    Write-Host ""
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "           MONITORING COMPLETE" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    
    if ($script:criticalIssues.Count -gt 0) {
        Write-Host "⚠️  Critical Issues Found: $($script:criticalIssues.Count)" -ForegroundColor Red
    }
    
    if ($script:warnings.Count -gt 0) {
        Write-Host "⚠️  Warnings: $($script:warnings.Count)" -ForegroundColor Yellow
    }
    
    Write-Host "📊 Total Disks Monitored: $($allDiskData.Count)" -ForegroundColor Cyan
    Write-Host "📁 Report Location: $ReportPath" -ForegroundColor Cyan
}

# Run the script
Main
#endregion
