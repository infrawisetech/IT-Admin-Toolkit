<#
.SYNOPSIS
    Firewall Rule Audit Tool for Check Point and Fortinet
    
.DESCRIPTION
    Audits firewall rules, identifies unused rules, overlapping rules,
    and generates compliance reports for Check Point and Fortinet firewalls.
    
.PARAMETER FirewallType
    Type of firewall: CheckPoint or Fortinet
    
.PARAMETER FirewallIP
    IP address of the firewall management server
    
.EXAMPLE
    .\Firewall-Audit.ps1 -FirewallType "CheckPoint" -FirewallIP "192.168.1.1"
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.7
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("CheckPoint", "Fortinet")]
    [string]$FirewallType,
    
    [Parameter(Mandatory=$true)]
    [string]$FirewallIP,
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckUnusedRules = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckShadowedRules = $true,
    
    [Parameter(Mandatory=$false)]
    [int]$DaysToCheckLogs = 30,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\FirewallAudit"
)

#region Functions
function Get-CheckPointRules {
    Write-Host "🔍 Retrieving Check Point firewall rules..." -ForegroundColor Cyan
    
    # Simulated Check Point rules for demonstration
    # In production, use Check Point API or mgmt_cli
    
    $rules = @(
        [PSCustomObject]@{
            RuleNumber = 1
            Name = "Allow_Management"
            Source = "10.0.0.0/8"
            Destination = "192.168.1.10"
            Service = "HTTPS"
            Action = "Accept"
            Track = "Log"
            Hits = 15234
            LastHit = (Get-Date).AddDays(-1)
            Status = "Active"
            Comment = "Management access"
        },
        [PSCustomObject]@{
            RuleNumber = 2
            Name = "Block_Malicious"
            Source = "Any"
            Destination = "192.168.0.0/16"
            Service = "Any"
            Action = "Drop"
            Track = "Alert"
            Hits = 542
            LastHit = (Get-Date).AddHours(-3)
            Status = "Active"
            Comment = "Block known malicious IPs"
        },
        [PSCustomObject]@{
            RuleNumber = 3
            Name = "Old_Test_Rule"
            Source = "172.16.0.0/12"
            Destination = "10.10.10.10"
            Service = "HTTP"
            Action = "Accept"
            Track = "None"
            Hits = 0
            LastHit = $null
            Status = "Unused"
            Comment = "Test rule - can be removed"
        }
    )
    
    return $rules
}

function Get-FortinetRules {
    Write-Host "🔍 Retrieving Fortinet firewall rules..." -ForegroundColor Cyan
    
    # Simulated Fortinet rules for demonstration
    # In production, use FortiGate API
    
    $rules = @(
        [PSCustomObject]@{
            PolicyID = 1
            Name = "Internal_to_Internet"
            SrcInterface = "internal"
            DstInterface = "wan1"
            Source = "10.0.0.0/8"
            Destination = "all"
            Service = "HTTP, HTTPS"
            Action = "accept"
            NAT = "Enable"
            LogTraffic = "all"
            Hits = 98765
            LastUsed = (Get-Date).AddMinutes(-30)
            Status = "Enabled"
        },
        [PSCustomObject]@{
            PolicyID = 2
            Name = "DMZ_Access"
            SrcInterface = "dmz"
            DstInterface = "internal"
            Source = "192.168.100.0/24"
            Destination = "10.0.10.0/24"
            Service = "MSSQL"
            Action = "accept"
            NAT = "Disable"
            LogTraffic = "utm"
            Hits = 4532
            LastUsed = (Get-Date).AddDays(-2)
            Status = "Enabled"
        }
    )
    
    return $rules
}

function Find-UnusedRules {
    param($Rules, $DaysThreshold)
    
    Write-Host "🔎 Identifying unused rules..." -ForegroundColor Yellow
    
    $unusedRules = @()
    $cutoffDate = (Get-Date).AddDays(-$DaysThreshold)
    
    foreach ($rule in $Rules) {
        $lastHitDate = if ($FirewallType -eq "CheckPoint") { $rule.LastHit } else { $rule.LastUsed }
        
        if ($null -eq $lastHitDate -or $lastHitDate -lt $cutoffDate) {
            $unusedRules += $rule
            Write-Host "   • Found unused rule: $($rule.Name)" -ForegroundColor Gray
        }
    }
    
    return $unusedRules
}

function Find-OverlappingRules {
    param($Rules)
    
    Write-Host "🔎 Checking for overlapping rules..." -ForegroundColor Yellow
    
    $overlapping = @()
    
    for ($i = 0; $i -lt $Rules.Count - 1; $i++) {
        for ($j = $i + 1; $j -lt $Rules.Count; $j++) {
            if ($Rules[$i].Source -eq $Rules[$j].Source -and 
                $Rules[$i].Destination -eq $Rules[$j].Destination) {
                
                $overlapping += [PSCustomObject]@{
                    Rule1 = $Rules[$i].Name
                    Rule2 = $Rules[$j].Name
                    Reason = "Same source and destination"
                }
                
                Write-Host "   • Overlap detected: $($Rules[$i].Name) <-> $($Rules[$j].Name)" -ForegroundColor Gray
            }
        }
    }
    
    return $overlapping
}

function Get-SecurityCompliance {
    param($Rules)
    
    Write-Host "📋 Checking security compliance..." -ForegroundColor Cyan
    
    $compliance = @{
        TotalRules = $Rules.Count
        AcceptRules = 0
        DenyRules = 0
        AnySourceRules = 0
        AnyDestRules = 0
        AnyServiceRules = 0
        UnloggedRules = 0
        ComplianceScore = 100
        Issues = @()
    }
    
    foreach ($rule in $Rules) {
        # Count rule types
        if ($rule.Action -in @("Accept", "accept", "Allow")) {
            $compliance.AcceptRules++
        } else {
            $compliance.DenyRules++
        }
        
        # Check for Any rules (potential security risks)
        if ($rule.Source -in @("Any", "all", "0.0.0.0/0")) {
            $compliance.AnySourceRules++
            $compliance.Issues += "Rule '$($rule.Name)' has ANY as source"
            $compliance.ComplianceScore -= 5
        }
        
        if ($rule.Destination -in @("Any", "all", "0.0.0.0/0")) {
            $compliance.AnyDestRules++
            $compliance.Issues += "Rule '$($rule.Name)' has ANY as destination"
            $compliance.ComplianceScore -= 5
        }
        
        if ($rule.Service -in @("Any", "all")) {
            $compliance.AnyServiceRules++
            $compliance.Issues += "Rule '$($rule.Name)' allows ANY service"
            $compliance.ComplianceScore -= 10
        }
        
        # Check logging
        if ($FirewallType -eq "CheckPoint") {
            if ($rule.Track -in @("None", "")) {
                $compliance.UnloggedRules++
                $compliance.Issues += "Rule '$($rule.Name)' has no logging enabled"
                $compliance.ComplianceScore -= 2
            }
        }
    }
    
    $compliance.ComplianceScore = [Math]::Max(0, $compliance.ComplianceScore)
    
    return $compliance
}

function New-FirewallAuditReport {
    param(
        $Rules,
        $UnusedRules,
        $OverlappingRules,
        $Compliance
    )
    
    Write-Host "📝 Generating audit report..." -ForegroundColor Yellow
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Firewall Audit Report - $FirewallType</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #ff6b6b 0%, #4ecdc4 100%);
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
        .compliance-score {
            display: inline-block;
            padding: 20px 40px;
            margin: 20px 0;
            border-radius: 50px;
            font-size: 2em;
            font-weight: bold;
            color: white;
        }
        .score-good { background: linear-gradient(135deg, #27ae60, #2ecc71); }
        .score-warning { background: linear-gradient(135deg, #f39c12, #f1c40f); }
        .score-critical { background: linear-gradient(135deg, #e74c3c, #c0392b); }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .stat-value {
            font-size: 2.5em;
            font-weight: bold;
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .stat-label {
            color: #7f8c8d;
            text-transform: uppercase;
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
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 3px solid #3498db;
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
        .unused-rule {
            background: #ffebee;
        }
        .overlap-rule {
            background: #fff8e1;
        }
        .issue-list {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .issue-item {
            padding: 5px 0;
            color: #856404;
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
            <h1>🔥 Firewall Audit Report - $FirewallType</h1>
            <p><strong>Firewall:</strong> $FirewallIP</p>
            <p><strong>Audit Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p><strong>Audited by:</strong> Aykut Yıldız</p>
            
            <div class="compliance-score $(if($Compliance.ComplianceScore -ge 80){'score-good'}elseif($Compliance.ComplianceScore -ge 60){'score-warning'}else{'score-critical'})">
                Compliance Score: $($Compliance.ComplianceScore)%
            </div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value">$($Rules.Count)</div>
                <div class="stat-label">Total Rules</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($Compliance.AcceptRules)</div>
                <div class="stat-label">Accept Rules</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($Compliance.DenyRules)</div>
                <div class="stat-label">Deny Rules</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($UnusedRules.Count)</div>
                <div class="stat-label">Unused Rules</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($OverlappingRules.Count)</div>
                <div class="stat-label">Overlapping</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($Compliance.AnySourceRules)</div>
                <div class="stat-label">Any Source</div>
            </div>
        </div>
"@

    # Compliance Issues
    if ($Compliance.Issues.Count -gt 0) {
        $htmlReport += @"
        <div class="section">
            <h2>⚠️ Compliance Issues</h2>
            <div class="issue-list">
"@
        foreach ($issue in $Compliance.Issues) {
            $htmlReport += @"
                <div class="issue-item">• $issue</div>
"@
        }
        $htmlReport += @"
            </div>
        </div>
"@
    }

    # All Rules
    $htmlReport += @"
        <div class="section">
            <h2>📋 Firewall Rules</h2>
            <table>
                <thead>
                    <tr>
"@

    if ($FirewallType -eq "CheckPoint") {
        $htmlReport += @"
                        <th>Rule #</th>
                        <th>Name</th>
                        <th>Source</th>
                        <th>Destination</th>
                        <th>Service</th>
                        <th>Action</th>
                        <th>Track</th>
                        <th>Hits</th>
                        <th>Last Hit</th>
                        <th>Status</th>
"@
    } else {
        $htmlReport += @"
                        <th>Policy ID</th>
                        <th>Name</th>
                        <th>Src Interface</th>
                        <th>Dst Interface</th>
                        <th>Source</th>
                        <th>Destination</th>
                        <th>Service</th>
                        <th>Action</th>
                        <th>NAT</th>
                        <th>Hits</th>
"@
    }

    $htmlReport += @"
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($rule in $Rules) {
        $rowClass = ""
        if ($UnusedRules -contains $rule) {
            $rowClass = 'class="unused-rule"'
        }
        
        if ($FirewallType -eq "CheckPoint") {
            $lastHit = if ($rule.LastHit) { $rule.LastHit.ToString('yyyy-MM-dd') } else { "Never" }
            $htmlReport += @"
                    <tr $rowClass>
                        <td>$($rule.RuleNumber)</td>
                        <td><strong>$($rule.Name)</strong></td>
                        <td>$($rule.Source)</td>
                        <td>$($rule.Destination)</td>
                        <td>$($rule.Service)</td>
                        <td>$($rule.Action)</td>
                        <td>$($rule.Track)</td>
                        <td>$($rule.Hits)</td>
                        <td>$lastHit</td>
                        <td>$($rule.Status)</td>
                    </tr>
"@
        } else {
            $htmlReport += @"
                    <tr $rowClass>
                        <td>$($rule.PolicyID)</td>
                        <td><strong>$($rule.Name)</strong></td>
                        <td>$($rule.SrcInterface)</td>
                        <td>$($rule.DstInterface)</td>
                        <td>$($rule.Source)</td>
                        <td>$($rule.Destination)</td>
                        <td>$($rule.Service)</td>
                        <td>$($rule.Action)</td>
                        <td>$($rule.NAT)</td>
                        <td>$($rule.Hits)</td>
                    </tr>
"@
        }
    }

    $htmlReport += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p><strong>Firewall Audit Tool v1.7</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "FirewallAudit_$FirewallType`_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    return $reportFile
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║       Firewall Rule Audit Tool v1.7                        ║
║       PowerShell Automation by Aykut Yıldız               ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

Write-Host ""
Write-Host "🔥 Firewall Type: $FirewallType" -ForegroundColor Yellow
Write-Host "🔥 Firewall IP: $FirewallIP" -ForegroundColor Yellow
Write-Host ""

# Get firewall rules
$rules = if ($FirewallType -eq "CheckPoint") {
    Get-CheckPointRules
} else {
    Get-FortinetRules
}

Write-Host "✅ Retrieved $($rules.Count) firewall rules" -ForegroundColor Green
Write-Host ""

# Analyze rules
$unusedRules = @()
$overlappingRules = @()
$compliance = $null

if ($CheckUnusedRules) {
    $unusedRules = Find-UnusedRules -Rules $rules -DaysThreshold $DaysToCheckLogs
}

if ($CheckShadowedRules) {
    $overlappingRules = Find-OverlappingRules -Rules $rules
}

$compliance = Get-SecurityCompliance -Rules $rules

# Generate report
$reportFile = New-FirewallAuditReport -Rules $rules `
                                      -UnusedRules $unusedRules `
                                      -OverlappingRules $overlappingRules `
                                      -Compliance $compliance

# Export to CSV
$csvFile = Join-Path $ReportPath "FirewallRules_$FirewallType`_$(Get-Date -Format 'yyyyMMdd').csv"
$rules | Export-Csv -Path $csvFile -NoTypeInformation

Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "         FIREWALL AUDIT COMPLETE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Audit Summary:" -ForegroundColor Yellow
Write-Host "   • Total Rules: $($rules.Count)" -ForegroundColor Gray
Write-Host "   • Unused Rules: $($unusedRules.Count)" -ForegroundColor $(if($unusedRules.Count -gt 0){'Yellow'}else{'Gray'})
Write-Host "   • Overlapping Rules: $($overlappingRules.Count)" -ForegroundColor $(if($overlappingRules.Count -gt 0){'Yellow'}else{'Gray'})
Write-Host "   • Compliance Score: $($compliance.ComplianceScore)%" -ForegroundColor $(if($compliance.ComplianceScore -ge 80){'Green'}elseif($compliance.ComplianceScore -ge 60){'Yellow'}else{'Red'})
Write-Host ""
Write-Host "📁 Reports saved:" -ForegroundColor Green
Write-Host "   • $reportFile" -ForegroundColor Gray
Write-Host "   • $csvFile" -ForegroundColor Gray

# Open report
Start-Process $reportFile
#endregion
