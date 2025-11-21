<#
.SYNOPSIS
    Windows Event Log Analyzer Tool
    
.DESCRIPTION
    Analyzes Windows event logs for errors, warnings, security events,
    and provides detailed reports with trend analysis.
    
.PARAMETER LogName
    Event log to analyze (System, Application, Security, etc.)
    
.PARAMETER DaysBack
    Number of days to analyze
    
.PARAMETER EventLevel
    Filter by event level (Error, Warning, Information, All)
    
.EXAMPLE
    .\Event-Log-Analyzer.ps1 -LogName System -DaysBack 7 -EventLevel Error
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.5
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$LogName = @("System", "Application", "Security"),
    
    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 7,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Error", "Warning", "Information", "All")]
    [string]$EventLevel = "All",
    
    [Parameter(Mandatory=$false)]
    [int]$TopEvents = 20,
    
    [Parameter(Mandatory=$false)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    
    [Parameter(Mandatory=$false)]
    [bool]$IncludeSecurityEvents = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\EventLogReports"
)

#region Functions
function Get-EventLogData {
    param(
        [string]$Computer,
        [string]$Log,
        [datetime]$StartTime
    )
    
    Write-Host "   📊 Analyzing $Log on $Computer..." -ForegroundColor Cyan
    
    try {
        $filterHashTable = @{
            LogName = $Log
            StartTime = $StartTime
        }
        
        if ($EventLevel -ne "All") {
            $levelMap = @{
                "Error" = 1,2
                "Warning" = 3
                "Information" = 4
            }
            $filterHashTable.Level = $levelMap[$EventLevel]
        }
        
        $events = Get-WinEvent -ComputerName $Computer -FilterHashtable $filterHashTable -ErrorAction SilentlyContinue
        
        return $events
    }
    catch {
        Write-Host "   ⚠️ Could not read $Log log: $_" -ForegroundColor Yellow
        return @()
    }
}

function Get-TopEventSummary {
    param($Events)
    
    $summary = $Events | Group-Object -Property Id, ProviderName | 
                        Sort-Object Count -Descending | 
                        Select-Object -First $TopEvents @{
                            Name='EventID'; Expression={($_.Name -split ',')[0]}
                        }, @{
                            Name='Source'; Expression={($_.Name -split ',')[1].Trim()}
                        }, Count, @{
                            Name='LastOccurrence'; Expression={
                                ($_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1).TimeCreated
                            }
                        }, @{
                            Name='Message'; Expression={
                                ($_.Group | Select-Object -First 1).Message -replace "`n.*", ""
                            }
                        }
    
    return $summary
}

function Get-SecurityEventAnalysis {
    param($Events)
    
    $securitySummary = @{
        SuccessfulLogons = ($Events | Where-Object {$_.Id -eq 4624}).Count
        FailedLogons = ($Events | Where-Object {$_.Id -eq 4625}).Count
        AccountLockouts = ($Events | Where-Object {$_.Id -eq 4740}).Count
        PasswordChanges = ($Events | Where-Object {$_.Id -eq 4723}).Count
        UserCreated = ($Events | Where-Object {$_.Id -eq 4720}).Count
        UserDeleted = ($Events | Where-Object {$_.Id -eq 4726}).Count
        GroupModified = ($Events | Where-Object {$_.Id -in @(4728, 4729, 4732, 4733)}).Count
        PolicyChanges = ($Events | Where-Object {$_.Id -in @(4719, 4904, 4905)}).Count
    }
    
    # Failed logon details
    $failedLogons = $Events | Where-Object {$_.Id -eq 4625} | 
                             Select-Object TimeCreated, @{
                                 Name='Account'; Expression={
                                     ([xml]$_.ToXml()).Event.EventData.Data | 
                                     Where-Object {$_.Name -eq 'TargetUserName'} | 
                                     Select-Object -ExpandProperty '#text'
                                 }
                             }, @{
                                 Name='Source'; Expression={
                                     ([xml]$_.ToXml()).Event.EventData.Data | 
                                     Where-Object {$_.Name -eq 'IpAddress'} | 
                                     Select-Object -ExpandProperty '#text'
                                 }
                             }
    
    return @{
        Summary = $securitySummary
        FailedLogons = $failedLogons
    }
}

function New-EventLogReport {
    param(
        [hashtable]$AnalysisData
    )
    
    Write-Host "📝 Generating HTML report..." -ForegroundColor Yellow
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Event Log Analysis Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
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
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            text-align: center;
        }
        h1 {
            color: #2c3e50;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .summary-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .summary-value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        .summary-label {
            color: #7f8c8d;
            text-transform: uppercase;
            font-size: 0.9em;
        }
        .error { color: #e74c3c; }
        .warning { color: #f39c12; }
        .info { color: #3498db; }
        .success { color: #27ae60; }
        .section {
            background: white;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        h2 {
            color: #2c3e50;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #ecf0f1;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th {
            background: #34495e;
            color: white;
            padding: 12px;
            text-align: left;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ecf0f1;
        }
        tr:hover {
            background: #f8f9fa;
        }
        .event-critical { background: #ffebee; }
        .event-warning { background: #fff8e1; }
        .chart {
            height: 300px;
            background: #ecf0f1;
            border-radius: 10px;
            display: flex;
            align-items: flex-end;
            justify-content: space-around;
            padding: 20px;
            margin: 20px 0;
        }
        .chart-bar {
            width: 60px;
            background: linear-gradient(to top, #3498db, #2980b9);
            border-radius: 5px 5px 0 0;
            position: relative;
        }
        .chart-label {
            position: absolute;
            bottom: -25px;
            left: 50%;
            transform: translateX(-50%);
            font-size: 0.8em;
            white-space: nowrap;
        }
        .footer {
            background: white;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            color: #7f8c8d;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 Windows Event Log Analysis Report</h1>
            <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | By: Aykut Yıldız</p>
            <p>Analysis Period: Last $DaysBack days | Servers: $($ComputerName -join ', ')</p>
        </div>
        
        <div class="summary-grid">
            <div class="summary-card">
                <div class="summary-value">$($AnalysisData.TotalEvents)</div>
                <div class="summary-label">Total Events</div>
            </div>
            <div class="summary-card">
                <div class="summary-value error">$($AnalysisData.ErrorCount)</div>
                <div class="summary-label">Errors</div>
            </div>
            <div class="summary-card">
                <div class="summary-value warning">$($AnalysisData.WarningCount)</div>
                <div class="summary-label">Warnings</div>
            </div>
            <div class="summary-card">
                <div class="summary-value info">$($AnalysisData.InfoCount)</div>
                <div class="summary-label">Information</div>
            </div>
"@

    # Add security summary if available
    if ($AnalysisData.SecurityAnalysis) {
        $sec = $AnalysisData.SecurityAnalysis.Summary
        $htmlReport += @"
            <div class="summary-card">
                <div class="summary-value success">$($sec.SuccessfulLogons)</div>
                <div class="summary-label">Successful Logons</div>
            </div>
            <div class="summary-card">
                <div class="summary-value error">$($sec.FailedLogons)</div>
                <div class="summary-label">Failed Logons</div>
            </div>
            <div class="summary-card">
                <div class="summary-value warning">$($sec.AccountLockouts)</div>
                <div class="summary-label">Account Lockouts</div>
            </div>
"@
    }

    $htmlReport += @"
        </div>
        
        <div class="section">
            <h2>🔝 Top Events by Frequency</h2>
            <table>
                <thead>
                    <tr>
                        <th>Event ID</th>
                        <th>Source</th>
                        <th>Count</th>
                        <th>Last Occurrence</th>
                        <th>Description</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($event in $AnalysisData.TopEvents) {
        $rowClass = if ($event.Count -gt 100) { 'class="event-critical"' }
                   elseif ($event.Count -gt 50) { 'class="event-warning"' }
                   else { '' }
        
        $htmlReport += @"
                    <tr $rowClass>
                        <td><strong>$($event.EventID)</strong></td>
                        <td>$($event.Source)</td>
                        <td><strong>$($event.Count)</strong></td>
                        <td>$($event.LastOccurrence.ToString('yyyy-MM-dd HH:mm'))</td>
                        <td>$($event.Message)</td>
                    </tr>
"@
    }

    $htmlReport += @"
                </tbody>
            </table>
        </div>
"@

    # Add failed logon details if security log was analyzed
    if ($AnalysisData.SecurityAnalysis.FailedLogons) {
        $htmlReport += @"
        <div class="section">
            <h2>🔒 Recent Failed Logon Attempts</h2>
            <table>
                <thead>
                    <tr>
                        <th>Time</th>
                        <th>Account</th>
                        <th>Source IP</th>
                    </tr>
                </thead>
                <tbody>
"@
        foreach ($logon in $AnalysisData.SecurityAnalysis.FailedLogons | Select-Object -First 20) {
            $htmlReport += @"
                    <tr>
                        <td>$($logon.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))</td>
                        <td>$($logon.Account)</td>
                        <td>$($logon.Source)</td>
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
            <p><strong>Event Log Analyzer v1.5</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "EventLogAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    return $reportFile
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║         Windows Event Log Analyzer v1.5                    ║
║         PowerShell Automation by Aykut Yıldız             ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

$startTime = (Get-Date).AddDays(-$DaysBack)
$allEvents = @()
$analysisData = @{}

Write-Host ""
Write-Host "🔍 Analyzing event logs from the last $DaysBack days..." -ForegroundColor Yellow
Write-Host ""

foreach ($computer in $ComputerName) {
    Write-Host "💻 Processing: $computer" -ForegroundColor Cyan
    
    foreach ($log in $LogName) {
        $events = Get-EventLogData -Computer $computer -Log $log -StartTime $startTime
        $allEvents += $events
    }
}

# Analyze events
$analysisData.TotalEvents = $allEvents.Count
$analysisData.ErrorCount = ($allEvents | Where-Object {$_.LevelDisplayName -eq 'Error'}).Count
$analysisData.WarningCount = ($allEvents | Where-Object {$_.LevelDisplayName -eq 'Warning'}).Count
$analysisData.InfoCount = ($allEvents | Where-Object {$_.LevelDisplayName -eq 'Information'}).Count
$analysisData.TopEvents = Get-TopEventSummary -Events $allEvents

# Security analysis if security log was included
if ($LogName -contains "Security" -and $IncludeSecurityEvents) {
    $securityEvents = $allEvents | Where-Object {$_.LogName -eq 'Security'}
    $analysisData.SecurityAnalysis = Get-SecurityEventAnalysis -Events $securityEvents
}

# Generate report
$reportFile = New-EventLogReport -AnalysisData $analysisData

# Export to CSV
$csvFile = Join-Path $ReportPath "EventLogAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$analysisData.TopEvents | Export-Csv -Path $csvFile -NoTypeInformation

Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "         EVENT LOG ANALYSIS COMPLETE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Summary:" -ForegroundColor Yellow
Write-Host "   • Total Events: $($analysisData.TotalEvents)" -ForegroundColor Gray
Write-Host "   • Errors: $($analysisData.ErrorCount)" -ForegroundColor Red
Write-Host "   • Warnings: $($analysisData.WarningCount)" -ForegroundColor Yellow
Write-Host ""
Write-Host "📁 Reports saved:" -ForegroundColor Green
Write-Host "   • $reportFile" -ForegroundColor Gray
Write-Host "   • $csvFile" -ForegroundColor Gray

# Open report
Start-Process $reportFile
#endregion
