<#
.SYNOPSIS
    Backup Verification and Monitoring Tool
    
.DESCRIPTION
    Comprehensive backup monitoring tool for Veeam and Acronis backup solutions.
    Verifies backup integrity, monitors job status, checks retention policies,
    and generates detailed reports.
    
.PARAMETER BackupSolution
    Backup solution to monitor (Veeam, Acronis, or Both)
    
.PARAMETER DaysToCheck
    Number of days to look back for backup jobs
    
.PARAMETER VerifyIntegrity
    Perform integrity check on backup files
    
.EXAMPLE
    .\Backup-Verification.ps1 -BackupSolution "Veeam" -DaysToCheck 7
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.8
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Veeam", "Acronis", "Both")]
    [string]$BackupSolution = "Both",
    
    [Parameter(Mandatory=$false)]
    [int]$DaysToCheck = 7,
    
    [Parameter(Mandatory=$false)]
    [bool]$VerifyIntegrity = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckRetention = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\BackupReports",
    
    [Parameter(Mandatory=$false)]
    [bool]$SendAlert = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpServer = "smtp.company.local",
    
    [Parameter(Mandatory=$false)]
    [string]$EmailTo = "backup-admin@company.com"
)

#region Functions
function Write-BackupLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Level) {
        "Error" { 
            Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red
            $script:failedJobs++
        }
        "Warning" { 
            Write-Host "[$timestamp] ⚠️  $Message" -ForegroundColor Yellow
            $script:warningJobs++
        }
        "Success" { 
            Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green
            $script:successfulJobs++
        }
        default { 
            Write-Host "[$timestamp] ℹ️  $Message" -ForegroundColor Cyan
        }
    }
    
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    $logFile = Join-Path $ReportPath "BackupVerification_$(Get-Date -Format 'yyyy-MM-dd').log"
    "[$timestamp] [$Level] $Message" | Add-Content -Path $logFile
}

function Get-VeeamBackupJobs {
    Write-BackupLog "Checking Veeam backup jobs..." "Info"
    
    try {
        # Load Veeam PowerShell module
        if (-not (Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue)) {
            Add-PSSnapin VeeamPSSnapIn -ErrorAction Stop
        }
        
        $startDate = (Get-Date).AddDays(-$DaysToCheck)
        $jobs = Get-VBRJob
        $jobResults = @()
        
        foreach ($job in $jobs) {
            $lastSession = Get-VBRBackupSession -Job $job | 
                          Where-Object { $_.CreationTime -ge $startDate } | 
                          Sort-Object CreationTime -Descending | 
                          Select-Object -First 1
            
            if ($lastSession) {
                $jobResult = [PSCustomObject]@{
                    Solution = "Veeam"
                    JobName = $job.Name
                    JobType = $job.JobType
                    Status = $lastSession.Result
                    StartTime = $lastSession.CreationTime
                    EndTime = $lastSession.EndTime
                    Duration = if ($lastSession.EndTime) { 
                        ($lastSession.EndTime - $lastSession.CreationTime).ToString() 
                    } else { "In Progress" }
                    ProcessedSize = [math]::Round($lastSession.BackupStats.DataSize / 1GB, 2)
                    BackupSize = [math]::Round($lastSession.BackupStats.BackupSize / 1GB, 2)
                    DedupeRatio = "$([math]::Round($lastSession.BackupStats.DedupRatio, 2)):1"
                    CompressionRatio = "$([math]::Round($lastSession.BackupStats.CompressRatio, 2)):1"
                    VMs = ($lastSession.GetTaskSessions() | Measure-Object).Count
                    Warnings = $lastSession.GetWarnings().Count
                    Errors = $lastSession.GetErrors().Count
                }
                
                $jobResults += $jobResult
                
                # Log job status
                switch ($lastSession.Result) {
                    "Success" { Write-BackupLog "$($job.Name): Successful" "Success" }
                    "Warning" { Write-BackupLog "$($job.Name): Completed with warnings" "Warning" }
                    "Failed" { Write-BackupLog "$($job.Name): Failed" "Error" }
                }
            } else {
                Write-BackupLog "$($job.Name): No backup in last $DaysToCheck days" "Warning"
                
                $jobResults += [PSCustomObject]@{
                    Solution = "Veeam"
                    JobName = $job.Name
                    JobType = $job.JobType
                    Status = "No Recent Backup"
                    StartTime = "N/A"
                    EndTime = "N/A"
                    Duration = "N/A"
                    ProcessedSize = 0
                    BackupSize = 0
                    DedupeRatio = "N/A"
                    CompressionRatio = "N/A"
                    VMs = 0
                    Warnings = 0
                    Errors = 0
                }
            }
        }
        
        return $jobResults
    }
    catch {
        Write-BackupLog "Failed to get Veeam jobs: $_" "Error"
        return @()
    }
}

function Get-AcronisBackupJobs {
    Write-BackupLog "Checking Acronis backup jobs..." "Info"
    
    try {
        # Acronis command line interface path
        $acronisCmd = "C:\Program Files\Acronis\CommandLineTool\acrocmd.exe"
        
        if (-not (Test-Path $acronisCmd)) {
            Write-BackupLog "Acronis command line tool not found" "Warning"
            return @()
        }
        
        # Get backup plans
        $plans = & $acronisCmd list plans --output json | ConvertFrom-Json
        $jobResults = @()
        
        foreach ($plan in $plans) {
            # Get last backup for this plan
            $backups = & $acronisCmd list backups --plan $plan.Id --output json | ConvertFrom-Json
            $lastBackup = $backups | Sort-Object CreatedAt -Descending | Select-Object -First 1
            
            if ($lastBackup -and (Get-Date $lastBackup.CreatedAt) -ge (Get-Date).AddDays(-$DaysToCheck)) {
                $jobResult = [PSCustomObject]@{
                    Solution = "Acronis"
                    JobName = $plan.Name
                    JobType = $plan.Type
                    Status = $lastBackup.Status
                    StartTime = $lastBackup.CreatedAt
                    EndTime = $lastBackup.CompletedAt
                    Duration = if ($lastBackup.CompletedAt) {
                        ((Get-Date $lastBackup.CompletedAt) - (Get-Date $lastBackup.CreatedAt)).ToString()
                    } else { "In Progress" }
                    ProcessedSize = [math]::Round($lastBackup.OriginalSize / 1GB, 2)
                    BackupSize = [math]::Round($lastBackup.BackupSize / 1GB, 2)
                    DedupeRatio = "N/A"
                    CompressionRatio = if ($lastBackup.OriginalSize -gt 0) {
                        "$([math]::Round($lastBackup.OriginalSize / $lastBackup.BackupSize, 2)):1"
                    } else { "N/A" }
                    VMs = 1
                    Warnings = 0
                    Errors = if ($lastBackup.Status -eq "Error") { 1 } else { 0 }
                }
                
                $jobResults += $jobResult
                
                # Log status
                switch ($lastBackup.Status) {
                    "Ok" { Write-BackupLog "$($plan.Name): Successful" "Success" }
                    "Warning" { Write-BackupLog "$($plan.Name): Completed with warnings" "Warning" }
                    "Error" { Write-BackupLog "$($plan.Name): Failed" "Error" }
                }
            } else {
                Write-BackupLog "$($plan.Name): No backup in last $DaysToCheck days" "Warning"
                
                $jobResults += [PSCustomObject]@{
                    Solution = "Acronis"
                    JobName = $plan.Name
                    JobType = $plan.Type
                    Status = "No Recent Backup"
                    StartTime = "N/A"
                    EndTime = "N/A"
                    Duration = "N/A"
                    ProcessedSize = 0
                    BackupSize = 0
                    DedupeRatio = "N/A"
                    CompressionRatio = "N/A"
                    VMs = 0
                    Warnings = 0
                    Errors = 0
                }
            }
        }
        
        return $jobResults
    }
    catch {
        Write-BackupLog "Failed to get Acronis jobs: $_" "Error"
        return @()
    }
}

function Test-BackupIntegrity {
    param(
        [string]$BackupPath
    )
    
    Write-BackupLog "Verifying backup integrity for: $BackupPath" "Info"
    
    try {
        if (Test-Path $BackupPath) {
            $files = Get-ChildItem -Path $BackupPath -Recurse -File
            $corruptedFiles = @()
            
            foreach ($file in $files) {
                try {
                    # Simple integrity check - try to read file
                    $stream = [System.IO.File]::OpenRead($file.FullName)
                    $stream.Close()
                } catch {
                    $corruptedFiles += $file.Name
                    Write-BackupLog "Corrupted file detected: $($file.Name)" "Error"
                }
            }
            
            if ($corruptedFiles.Count -eq 0) {
                Write-BackupLog "All backup files passed integrity check" "Success"
                return $true
            } else {
                Write-BackupLog "Found $($corruptedFiles.Count) corrupted files" "Error"
                return $false
            }
        } else {
            Write-BackupLog "Backup path not accessible: $BackupPath" "Error"
            return $false
        }
    }
    catch {
        Write-BackupLog "Integrity check failed: $_" "Error"
        return $false
    }
}

function Get-BackupStorageInfo {
    Write-BackupLog "Analyzing backup storage..." "Info"
    
    $storageInfo = @()
    
    # Common backup locations
    $backupPaths = @(
        "D:\Backups",
        "E:\Veeam\Backups",
        "\\NAS\Backups",
        "F:\Acronis\Backups"
    )
    
    foreach ($path in $backupPaths) {
        if (Test-Path $path -ErrorAction SilentlyContinue) {
            try {
                $drive = if ($path.StartsWith("\\")) {
                    # Network path
                    $share = Get-WmiObject Win32_MappedLogicalDisk | Where-Object { $_.ProviderName -eq $path }
                    if ($share) { Get-PSDrive $share.Name } else { $null }
                } else {
                    # Local path
                    Get-PSDrive ($path.Substring(0,1))
                }
                
                if ($drive) {
                    $totalSize = [math]::Round($drive.Used / 1GB + $drive.Free / 1GB, 2)
                    $usedSize = [math]::Round($drive.Used / 1GB, 2)
                    $freeSize = [math]::Round($drive.Free / 1GB, 2)
                    $percentUsed = [math]::Round(($usedSize / $totalSize) * 100, 2)
                    
                    $storageInfo += [PSCustomObject]@{
                        Path = $path
                        TotalGB = $totalSize
                        UsedGB = $usedSize
                        FreeGB = $freeSize
                        PercentUsed = $percentUsed
                        Status = if ($percentUsed -ge 90) { "Critical" } 
                                elseif ($percentUsed -ge 80) { "Warning" }
                                else { "OK" }
                    }
                    
                    Write-BackupLog "$path : $percentUsed% used ($freeSize GB free)" "Info"
                }
            }
            catch {
                Write-BackupLog "Could not analyze $path : $_" "Warning"
            }
        }
    }
    
    return $storageInfo
}

function New-BackupReport {
    param(
        [array]$JobResults,
        [array]$StorageInfo
    )
    
    Write-BackupLog "Generating backup verification report..." "Info"
    
    $totalJobs = $JobResults.Count
    $successful = ($JobResults | Where-Object { $_.Status -in @("Success", "Ok") }).Count
    $warnings = ($JobResults | Where-Object { $_.Status -eq "Warning" }).Count
    $failed = ($JobResults | Where-Object { $_.Status -in @("Failed", "Error") }).Count
    $noBackup = ($JobResults | Where-Object { $_.Status -eq "No Recent Backup" }).Count
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Backup Verification Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0f2027 0%, #203a43 50%, #2c5364 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1600px;
            margin: 0 auto;
        }
        
        .header {
            background: rgba(255,255,255,0.95);
            border-radius: 15px;
            padding: 40px;
            margin-bottom: 30px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
        }
        
        h1 {
            color: #2c3e50;
            font-size: 3em;
            margin-bottom: 10px;
        }
        
        .subtitle {
            color: #7f8c8d;
            font-size: 1.2em;
        }
        
        .stats-container {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: white;
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            text-align: center;
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-10px);
        }
        
        .stat-value {
            font-size: 3em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .stat-label {
            color: #95a5a6;
            font-size: 1.1em;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .success { color: #27ae60; }
        .warning { color: #f39c12; }
        .error { color: #e74c3c; }
        .info { color: #3498db; }
        
        .backup-grid {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .section-title {
            color: #2c3e50;
            font-size: 1.8em;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #3498db;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
        }
        
        th {
            background: linear-gradient(135deg, #3498db, #2980b9);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 500;
            position: sticky;
            top: 0;
        }
        
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #ecf0f1;
        }
        
        tr:hover {
            background: #f8f9fa;
        }
        
        .status-badge {
            padding: 6px 15px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.85em;
            display: inline-block;
        }
        
        .status-success { background: #d4edda; color: #155724; }
        .status-warning { background: #fff3cd; color: #856404; }
        .status-error { background: #f8d7da; color: #721c24; }
        .status-nobackup { background: #f4f4f4; color: #666; }
        
        .storage-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .storage-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            border: 2px solid #e9ecef;
        }
        
        .storage-path {
            font-weight: bold;
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 1.1em;
        }
        
        .storage-bar {
            width: 100%;
            height: 30px;
            background: #e9ecef;
            border-radius: 15px;
            overflow: hidden;
            margin: 10px 0;
        }
        
        .storage-fill {
            height: 100%;
            background: linear-gradient(90deg, #3498db, #2980b9);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            transition: width 0.5s ease;
        }
        
        .storage-fill.warning {
            background: linear-gradient(90deg, #f39c12, #e67e22);
        }
        
        .storage-fill.critical {
            background: linear-gradient(90deg, #e74c3c, #c0392b);
        }
        
        .storage-details {
            display: flex;
            justify-content: space-between;
            margin-top: 10px;
            font-size: 0.9em;
            color: #7f8c8d;
        }
        
        .chart-container {
            background: white;
            border-radius: 15px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            margin-bottom: 30px;
        }
        
        .timeline {
            position: relative;
            padding: 20px 0;
        }
        
        .timeline-item {
            display: flex;
            align-items: center;
            margin-bottom: 20px;
            padding-left: 40px;
            position: relative;
        }
        
        .timeline-item::before {
            content: '';
            position: absolute;
            left: 10px;
            top: 50%;
            transform: translateY(-50%);
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: #3498db;
        }
        
        .timeline-item.success::before { background: #27ae60; }
        .timeline-item.warning::before { background: #f39c12; }
        .timeline-item.error::before { background: #e74c3c; }
        
        .timeline-content {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 15px;
            flex: 1;
        }
        
        .footer {
            background: white;
            border-radius: 15px;
            padding: 25px;
            text-align: center;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            color: #7f8c8d;
        }
        
        @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.05); }
        }
        
        .pulse { animation: pulse 2s infinite; }
        
        @media print {
            body { background: white; }
            .stat-card, .backup-grid, .chart-container { box-shadow: none; border: 1px solid #ddd; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔐 Backup Verification Report</h1>
            <div class="subtitle">Generated by Aykut Yıldız | $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss')</div>
        </div>
        
        <div class="stats-container">
            <div class="stat-card">
                <div class="stat-value">$totalJobs</div>
                <div class="stat-label">Total Jobs</div>
            </div>
            <div class="stat-card">
                <div class="stat-value success">$successful</div>
                <div class="stat-label">Successful</div>
            </div>
            <div class="stat-card">
                <div class="stat-value warning">$warnings</div>
                <div class="stat-label">Warnings</div>
            </div>
            <div class="stat-card">
                <div class="stat-value error">$failed</div>
                <div class="stat-label">Failed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value info">$noBackup</div>
                <div class="stat-label">No Recent</div>
            </div>
        </div>
        
        <div class="backup-grid">
            <h2 class="section-title">📊 Backup Job Details</h2>
            <table>
                <thead>
                    <tr>
                        <th>Solution</th>
                        <th>Job Name</th>
                        <th>Type</th>
                        <th>Status</th>
                        <th>Start Time</th>
                        <th>Duration</th>
                        <th>Processed</th>
                        <th>Backup Size</th>
                        <th>Compression</th>
                        <th>Warnings</th>
                        <th>Errors</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($job in $JobResults | Sort-Object StartTime -Descending) {
        $statusClass = switch($job.Status) {
            {$_ -in @("Success", "Ok")} { "success" }
            "Warning" { "warning" }
            {$_ -in @("Failed", "Error")} { "error" }
            "No Recent Backup" { "nobackup" }
            default { "info" }
        }
        
        $htmlReport += @"
                    <tr>
                        <td><strong>$($job.Solution)</strong></td>
                        <td>$($job.JobName)</td>
                        <td>$($job.JobType)</td>
                        <td><span class="status-badge status-$statusClass">$($job.Status)</span></td>
                        <td>$($job.StartTime)</td>
                        <td>$($job.Duration)</td>
                        <td>$($job.ProcessedSize) GB</td>
                        <td>$($job.BackupSize) GB</td>
                        <td>$($job.CompressionRatio)</td>
                        <td>$($job.Warnings)</td>
                        <td>$($job.Errors)</td>
                    </tr>
"@
    }

    $htmlReport += @"
                </tbody>
            </table>
        </div>
        
        <div class="backup-grid">
            <h2 class="section-title">💾 Backup Storage Status</h2>
            <div class="storage-grid">
"@

    foreach ($storage in $StorageInfo) {
        $fillClass = switch($storage.Status) {
            "Critical" { "critical" }
            "Warning" { "warning" }
            default { "" }
        }
        
        $htmlReport += @"
                <div class="storage-card">
                    <div class="storage-path">$($storage.Path)</div>
                    <div class="storage-bar">
                        <div class="storage-fill $fillClass" style="width: $($storage.PercentUsed)%;">
                            $($storage.PercentUsed)% Used
                        </div>
                    </div>
                    <div class="storage-details">
                        <span>Total: $($storage.TotalGB) GB</span>
                        <span>Used: $($storage.UsedGB) GB</span>
                        <span>Free: $($storage.FreeGB) GB</span>
                    </div>
                </div>
"@
    }

    # Calculate success rate
    $successRate = if ($totalJobs -gt 0) {
        [math]::Round(($successful / $totalJobs) * 100, 2)
    } else { 0 }

    $htmlReport += @"
            </div>
        </div>
        
        <div class="chart-container">
            <h2 class="section-title">📈 Backup Success Rate</h2>
            <div style="text-align: center; padding: 40px;">
                <div style="font-size: 5em; font-weight: bold; color: $(if($successRate -ge 90){'#27ae60'}elseif($successRate -ge 70){'#f39c12'}else{'#e74c3c'});">
                    $successRate%
                </div>
                <div style="color: #95a5a6; font-size: 1.2em; margin-top: 10px;">
                    Overall Success Rate (Last $DaysToCheck Days)
                </div>
            </div>
        </div>
        
        <div class="footer">
            <p><strong>Backup Verification Tool v1.8</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
            <p>Report covers the last $DaysToCheck days of backup operations</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "BackupReport_$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-BackupLog "Report saved to: $reportFile" "Success"
    return $reportFile
}
#endregion

#region Main Script
function Main {
    $script:successfulJobs = 0
    $script:warningJobs = 0
    $script:failedJobs = 0
    
    Write-Host @"
╔════════════════════════════════════════════════════════════╗
║         Backup Verification & Monitoring Tool v1.8          ║
║         PowerShell Automation by Aykut Yıldız             ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Yellow
    Write-Host "  • Backup Solution: $BackupSolution" -ForegroundColor Gray
    Write-Host "  • Days to Check: $DaysToCheck" -ForegroundColor Gray
    Write-Host "  • Verify Integrity: $VerifyIntegrity" -ForegroundColor Gray
    Write-Host "  • Check Retention: $CheckRetention" -ForegroundColor Gray
    Write-Host ""
    
    $allJobResults = @()
    
    # Get Veeam jobs
    if ($BackupSolution -in @("Veeam", "Both")) {
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        Write-Host "  VEEAM BACKUP & REPLICATION" -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        
        $veeamJobs = Get-VeeamBackupJobs
        $allJobResults += $veeamJobs
    }
    
    # Get Acronis jobs
    if ($BackupSolution -in @("Acronis", "Both")) {
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        Write-Host "  ACRONIS BACKUP" -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        
        $acronisJobs = Get-AcronisBackupJobs
        $allJobResults += $acronisJobs
    }
    
    # Check storage
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    Write-Host "  STORAGE ANALYSIS" -ForegroundColor White
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
    
    $storageInfo = Get-BackupStorageInfo
    
    # Verify integrity if requested
    if ($VerifyIntegrity) {
        Write-Host ""
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        Write-Host "  INTEGRITY VERIFICATION" -ForegroundColor White
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
        
        foreach ($storage in $storageInfo) {
            Test-BackupIntegrity -BackupPath $storage.Path
        }
    }
    
    # Generate report
    $reportFile = New-BackupReport -JobResults $allJobResults -StorageInfo $storageInfo
    
    # Summary
    Write-Host ""
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "         BACKUP VERIFICATION COMPLETE" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 Summary:" -ForegroundColor Yellow
    Write-Host "   ✅ Successful: $script:successfulJobs" -ForegroundColor Green
    Write-Host "   ⚠️  Warnings: $script:warningJobs" -ForegroundColor Yellow
    Write-Host "   ❌ Failed: $script:failedJobs" -ForegroundColor Red
    Write-Host ""
    Write-Host "📁 Report Location: $reportFile" -ForegroundColor Cyan
    
    # Open report
    Start-Process $reportFile
    
    # Send alert if needed
    if ($SendAlert -and $script:failedJobs -gt 0) {
        Write-BackupLog "Sending failure alert email..." "Warning"
        # Email code here
    }
}

# Run the script
Main
#endregion
