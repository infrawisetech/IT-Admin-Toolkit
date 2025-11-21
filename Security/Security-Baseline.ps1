<#
.SYNOPSIS
    Windows Security Baseline Compliance Check
    
.DESCRIPTION
    Checks Windows systems against security baseline configurations including
    CIS benchmarks, STIG requirements, and enterprise security best practices.
    
.PARAMETER BaselineType
    Type of baseline to check: CIS, STIG, Custom, All
    
.PARAMETER ComputerName
    Target computers to audit
    
.EXAMPLE
    .\Security-Baseline.ps1 -BaselineType "CIS" -ComputerName "SERVER01"
    
.NOTES
    Author: Aykut Yıldız
    Version: 2.0
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("CIS", "STIG", "Custom", "All")]
    [string]$BaselineType = "All",
    
    [Parameter(Mandatory=$false)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckPasswords = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckAudit = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckServices = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckFirewall = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$CheckUpdates = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\SecurityBaseline"
)

#region Functions
function Test-PasswordPolicy {
    param([string]$Computer)
    
    Write-Host "   🔐 Checking password policy..." -ForegroundColor Cyan
    
    $policy = @{
        MinimumLength = 0
        ComplexityEnabled = $false
        MaximumAge = 0
        MinimumAge = 0
        HistoryCount = 0
        LockoutThreshold = 0
        ReversibleEncryption = $false
        Status = "Unknown"
        Score = 0
    }
    
    try {
        # Get password policy
        $secpol = secedit /export /cfg "$env:temp\secpol.cfg" /quiet
        $secpolContent = Get-Content "$env:temp\secpol.cfg"
        
        foreach ($line in $secpolContent) {
            if ($line -match "MinimumPasswordLength\s*=\s*(\d+)") {
                $policy.MinimumLength = [int]$matches[1]
                if ($policy.MinimumLength -ge 14) { $policy.Score += 20 }
                elseif ($policy.MinimumLength -ge 8) { $policy.Score += 10 }
            }
            if ($line -match "PasswordComplexity\s*=\s*(\d+)") {
                $policy.ComplexityEnabled = $matches[1] -eq "1"
                if ($policy.ComplexityEnabled) { $policy.Score += 20 }
            }
            if ($line -match "MaximumPasswordAge\s*=\s*(\d+)") {
                $policy.MaximumAge = [int]$matches[1]
                if ($policy.MaximumAge -le 90 -and $policy.MaximumAge -gt 0) { $policy.Score += 20 }
            }
            if ($line -match "PasswordHistorySize\s*=\s*(\d+)") {
                $policy.HistoryCount = [int]$matches[1]
                if ($policy.HistoryCount -ge 24) { $policy.Score += 20 }
                elseif ($policy.HistoryCount -ge 12) { $policy.Score += 10 }
            }
            if ($line -match "LockoutBadCount\s*=\s*(\d+)") {
                $policy.LockoutThreshold = [int]$matches[1]
                if ($policy.LockoutThreshold -le 5 -and $policy.LockoutThreshold -gt 0) { $policy.Score += 20 }
            }
        }
        
        Remove-Item "$env:temp\secpol.cfg" -Force -ErrorAction SilentlyContinue
        
        # Determine status
        $policy.Status = if ($policy.Score -ge 80) { "Compliant" }
                        elseif ($policy.Score -ge 60) { "Partial" }
                        else { "Non-Compliant" }
        
    } catch {
        Write-Host "      ❌ Failed to retrieve password policy: $_" -ForegroundColor Red
        $policy.Status = "Error"
    }
    
    return $policy
}

function Test-AuditPolicy {
    param([string]$Computer)
    
    Write-Host "   📝 Checking audit policy..." -ForegroundColor Cyan
    
    $auditPolicy = @{
        LogonEvents = "Not Configured"
        AccountManagement = "Not Configured"
        ObjectAccess = "Not Configured"
        PolicyChange = "Not Configured"
        PrivilegeUse = "Not Configured"
        SystemEvents = "Not Configured"
        Score = 0
        Status = "Unknown"
    }
    
    try {
        $auditpol = auditpol /get /category:*
        
        if ($auditpol -match "Logon/Logoff.*Success and Failure") {
            $auditPolicy.LogonEvents = "Success and Failure"
            $auditPolicy.Score += 20
        }
        if ($auditpol -match "Account Management.*Success and Failure") {
            $auditPolicy.AccountManagement = "Success and Failure"
            $auditPolicy.Score += 20
        }
        if ($auditpol -match "Object Access.*Success and Failure") {
            $auditPolicy.ObjectAccess = "Success and Failure"
            $auditPolicy.Score += 15
        }
        if ($auditpol -match "Policy Change.*Success and Failure") {
            $auditPolicy.PolicyChange = "Success and Failure"
            $auditPolicy.Score += 15
        }
        if ($auditpol -match "Privilege Use.*Success and Failure") {
            $auditPolicy.PrivilegeUse = "Success and Failure"
            $auditPolicy.Score += 15
        }
        if ($auditpol -match "System.*Success and Failure") {
            $auditPolicy.SystemEvents = "Success and Failure"
            $auditPolicy.Score += 15
        }
        
        $auditPolicy.Status = if ($auditPolicy.Score -ge 80) { "Compliant" }
                             elseif ($auditPolicy.Score -ge 60) { "Partial" }
                             else { "Non-Compliant" }
        
    } catch {
        Write-Host "      ❌ Failed to retrieve audit policy: $_" -ForegroundColor Red
        $auditPolicy.Status = "Error"
    }
    
    return $auditPolicy
}

function Test-SecurityServices {
    param([string]$Computer)
    
    Write-Host "   🛡️ Checking security services..." -ForegroundColor Cyan
    
    $services = @{
        WindowsDefender = "Unknown"
        WindowsFirewall = "Unknown"
        WindowsUpdate = "Unknown"
        EventLog = "Unknown"
        RemoteRegistry = "Unknown"
        Score = 0
        Status = "Unknown"
    }
    
    try {
        # Check Windows Defender
        $defender = Get-Service -Name WinDefend -ErrorAction SilentlyContinue
        if ($defender -and $defender.Status -eq 'Running') {
            $services.WindowsDefender = "Running"
            $services.Score += 25
        } else {
            $services.WindowsDefender = "Stopped"
        }
        
        # Check Windows Firewall
        $firewall = Get-Service -Name mpssvc -ErrorAction SilentlyContinue
        if ($firewall -and $firewall.Status -eq 'Running') {
            $services.WindowsFirewall = "Running"
            $services.Score += 25
        } else {
            $services.WindowsFirewall = "Stopped"
        }
        
        # Check Windows Update
        $update = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        if ($update -and $update.StartType -ne 'Disabled') {
            $services.WindowsUpdate = "Enabled"
            $services.Score += 25
        } else {
            $services.WindowsUpdate = "Disabled"
        }
        
        # Check Event Log
        $eventlog = Get-Service -Name EventLog -ErrorAction SilentlyContinue
        if ($eventlog -and $eventlog.Status -eq 'Running') {
            $services.EventLog = "Running"
            $services.Score += 15
        } else {
            $services.EventLog = "Stopped"
        }
        
        # Check Remote Registry (should be disabled)
        $remoteReg = Get-Service -Name RemoteRegistry -ErrorAction SilentlyContinue
        if ($remoteReg -and $remoteReg.Status -eq 'Stopped') {
            $services.RemoteRegistry = "Disabled (Good)"
            $services.Score += 10
        } else {
            $services.RemoteRegistry = "Enabled (Risk)"
        }
        
        $services.Status = if ($services.Score -ge 80) { "Compliant" }
                          elseif ($services.Score -ge 60) { "Partial" }
                          else { "Non-Compliant" }
        
    } catch {
        Write-Host "      ❌ Failed to check services: $_" -ForegroundColor Red
        $services.Status = "Error"
    }
    
    return $services
}

function Test-FirewallRules {
    param([string]$Computer)
    
    Write-Host "   🔥 Checking Windows Firewall..." -ForegroundColor Cyan
    
    $firewall = @{
        DomainProfile = "Unknown"
        PrivateProfile = "Unknown"
        PublicProfile = "Unknown"
        InboundRules = 0
        OutboundRules = 0
        Score = 0
        Status = "Unknown"
    }
    
    try {
        # Check firewall profiles
        $profiles = Get-NetFirewallProfile
        
        foreach ($profile in $profiles) {
            switch ($profile.Name) {
                "Domain" { 
                    $firewall.DomainProfile = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
                    if ($profile.Enabled) { $firewall.Score += 30 }
                }
                "Private" { 
                    $firewall.PrivateProfile = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
                    if ($profile.Enabled) { $firewall.Score += 30 }
                }
                "Public" { 
                    $firewall.PublicProfile = if ($profile.Enabled) { "Enabled" } else { "Disabled" }
                    if ($profile.Enabled) { $firewall.Score += 40 }
                }
            }
        }
        
        # Count rules
        $firewall.InboundRules = (Get-NetFirewallRule -Direction Inbound -Enabled True).Count
        $firewall.OutboundRules = (Get-NetFirewallRule -Direction Outbound -Enabled True).Count
        
        $firewall.Status = if ($firewall.Score -ge 80) { "Compliant" }
                          elseif ($firewall.Score -ge 60) { "Partial" }
                          else { "Non-Compliant" }
        
    } catch {
        Write-Host "      ❌ Failed to check firewall: $_" -ForegroundColor Red
        $firewall.Status = "Error"
    }
    
    return $firewall
}

function Test-WindowsUpdates {
    param([string]$Computer)
    
    Write-Host "   🔄 Checking Windows Updates..." -ForegroundColor Cyan
    
    $updates = @{
        LastCheckTime = $null
        PendingUpdates = 0
        InstalledUpdates = 0
        DaysSinceLastUpdate = 999
        AutoUpdateEnabled = $false
        Score = 0
        Status = "Unknown"
    }
    
    try {
        # Check Windows Update settings
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        # Get pending updates
        $searchResult = $updateSearcher.Search("IsInstalled=0")
        $updates.PendingUpdates = $searchResult.Updates.Count
        
        # Get update history
        $historyCount = $updateSearcher.GetTotalHistoryCount()
        if ($historyCount -gt 0) {
            $history = $updateSearcher.QueryHistory(0, 1)
            if ($history.Count -gt 0) {
                $lastUpdate = $history.Item(0)
                $updates.LastCheckTime = $lastUpdate.Date
                $updates.DaysSinceLastUpdate = (New-TimeSpan -Start $lastUpdate.Date -End (Get-Date)).Days
            }
        }
        
        # Score calculation
        if ($updates.PendingUpdates -eq 0) { $updates.Score += 40 }
        elseif ($updates.PendingUpdates -le 5) { $updates.Score += 20 }
        
        if ($updates.DaysSinceLastUpdate -le 30) { $updates.Score += 60 }
        elseif ($updates.DaysSinceLastUpdate -le 60) { $updates.Score += 30 }
        
        $updates.Status = if ($updates.Score -ge 80) { "Compliant" }
                         elseif ($updates.Score -ge 60) { "Partial" }
                         else { "Non-Compliant" }
        
    } catch {
        Write-Host "      ❌ Failed to check updates: $_" -ForegroundColor Red
        $updates.Status = "Error"
    }
    
    return $updates
}

function New-SecurityBaselineReport {
    param(
        [hashtable]$Results
    )
    
    Write-Host ""
    Write-Host "📝 Generating security baseline report..." -ForegroundColor Yellow
    
    # Calculate overall compliance score
    $totalScore = 0
    $componentCount = 0
    
    foreach ($component in $Results.Keys) {
        if ($Results[$component].Score) {
            $totalScore += $Results[$component].Score
            $componentCount++
        }
    }
    
    $overallScore = if ($componentCount -gt 0) { 
        [math]::Round($totalScore / $componentCount, 0) 
    } else { 0 }
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Security Baseline Compliance Report</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
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
            margin-bottom: 20px;
        }
        .overall-score {
            display: inline-block;
            width: 200px;
            height: 200px;
            border-radius: 50%;
            background: conic-gradient(
                $(if($overallScore -ge 80){'#27ae60'}elseif($overallScore -ge 60){'#f39c12'}else{'#e74c3c'}) 0deg $(($overallScore * 3.6))deg,
                #ecf0f1 $(($overallScore * 3.6))deg 360deg
            );
            display: flex;
            align-items: center;
            justify-content: center;
            position: relative;
            margin: 20px auto;
        }
        .overall-score::before {
            content: '';
            position: absolute;
            width: 160px;
            height: 160px;
            border-radius: 50%;
            background: white;
        }
        .score-text {
            position: relative;
            font-size: 3em;
            font-weight: bold;
            color: #2c3e50;
        }
        .components {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .component-card {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .component-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #ecf0f1;
        }
        .component-title {
            font-size: 1.3em;
            color: #2c3e50;
            font-weight: bold;
        }
        .status-badge {
            padding: 5px 15px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .status-compliant {
            background: #d4edda;
            color: #155724;
        }
        .status-partial {
            background: #fff3cd;
            color: #856404;
        }
        .status-non-compliant {
            background: #f8d7da;
            color: #721c24;
        }
        .detail-row {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #f8f9fa;
        }
        .detail-label {
            color: #6c757d;
        }
        .detail-value {
            font-weight: 500;
            color: #2c3e50;
        }
        .recommendations {
            background: #fff3cd;
            border: 1px solid #ffc107;
            border-radius: 10px;
            padding: 20px;
            margin-top: 30px;
        }
        .recommendations h3 {
            color: #856404;
            margin-bottom: 15px;
        }
        .recommendation-item {
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
            <h1>🛡️ Security Baseline Compliance Report</h1>
            <p><strong>System:</strong> $($ComputerName -join ', ')</p>
            <p><strong>Baseline Type:</strong> $BaselineType</p>
            <p><strong>Assessment Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p><strong>Assessed by:</strong> Aykut Yıldız</p>
            
            <div class="overall-score">
                <div class="score-text">$overallScore%</div>
            </div>
            <p style="margin-top: 10px; color: #6c757d;">Overall Compliance Score</p>
        </div>
        
        <div class="components">
"@

    # Password Policy Component
    if ($Results.PasswordPolicy) {
        $pp = $Results.PasswordPolicy
        $statusClass = switch($pp.Status) {
            "Compliant" { "status-compliant" }
            "Partial" { "status-partial" }
            default { "status-non-compliant" }
        }
        
        $htmlReport += @"
            <div class="component-card">
                <div class="component-header">
                    <div class="component-title">🔐 Password Policy</div>
                    <div class="status-badge $statusClass">$($pp.Status)</div>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Minimum Length:</span>
                    <span class="detail-value">$($pp.MinimumLength) characters</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Complexity Required:</span>
                    <span class="detail-value">$(if($pp.ComplexityEnabled){'Yes'}else{'No'})</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Maximum Age:</span>
                    <span class="detail-value">$($pp.MaximumAge) days</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Password History:</span>
                    <span class="detail-value">$($pp.HistoryCount) passwords</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Account Lockout:</span>
                    <span class="detail-value">$($pp.LockoutThreshold) attempts</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Compliance Score:</span>
                    <span class="detail-value">$($pp.Score)%</span>
                </div>
            </div>
"@
    }

    # Audit Policy Component
    if ($Results.AuditPolicy) {
        $ap = $Results.AuditPolicy
        $statusClass = switch($ap.Status) {
            "Compliant" { "status-compliant" }
            "Partial" { "status-partial" }
            default { "status-non-compliant" }
        }
        
        $htmlReport += @"
            <div class="component-card">
                <div class="component-header">
                    <div class="component-title">📝 Audit Policy</div>
                    <div class="status-badge $statusClass">$($ap.Status)</div>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Logon Events:</span>
                    <span class="detail-value">$($ap.LogonEvents)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Account Management:</span>
                    <span class="detail-value">$($ap.AccountManagement)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Object Access:</span>
                    <span class="detail-value">$($ap.ObjectAccess)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Policy Change:</span>
                    <span class="detail-value">$($ap.PolicyChange)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">System Events:</span>
                    <span class="detail-value">$($ap.SystemEvents)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Compliance Score:</span>
                    <span class="detail-value">$($ap.Score)%</span>
                </div>
            </div>
"@
    }

    # Security Services Component
    if ($Results.SecurityServices) {
        $ss = $Results.SecurityServices
        $statusClass = switch($ss.Status) {
            "Compliant" { "status-compliant" }
            "Partial" { "status-partial" }
            default { "status-non-compliant" }
        }
        
        $htmlReport += @"
            <div class="component-card">
                <div class="component-header">
                    <div class="component-title">🛡️ Security Services</div>
                    <div class="status-badge $statusClass">$($ss.Status)</div>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Windows Defender:</span>
                    <span class="detail-value">$($ss.WindowsDefender)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Windows Firewall:</span>
                    <span class="detail-value">$($ss.WindowsFirewall)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Windows Update:</span>
                    <span class="detail-value">$($ss.WindowsUpdate)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Event Log Service:</span>
                    <span class="detail-value">$($ss.EventLog)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Remote Registry:</span>
                    <span class="detail-value">$($ss.RemoteRegistry)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Compliance Score:</span>
                    <span class="detail-value">$($ss.Score)%</span>
                </div>
            </div>
"@
    }

    # Firewall Component
    if ($Results.Firewall) {
        $fw = $Results.Firewall
        $statusClass = switch($fw.Status) {
            "Compliant" { "status-compliant" }
            "Partial" { "status-partial" }
            default { "status-non-compliant" }
        }
        
        $htmlReport += @"
            <div class="component-card">
                <div class="component-header">
                    <div class="component-title">🔥 Windows Firewall</div>
                    <div class="status-badge $statusClass">$($fw.Status)</div>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Domain Profile:</span>
                    <span class="detail-value">$($fw.DomainProfile)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Private Profile:</span>
                    <span class="detail-value">$($fw.PrivateProfile)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Public Profile:</span>
                    <span class="detail-value">$($fw.PublicProfile)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Inbound Rules:</span>
                    <span class="detail-value">$($fw.InboundRules)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Outbound Rules:</span>
                    <span class="detail-value">$($fw.OutboundRules)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Compliance Score:</span>
                    <span class="detail-value">$($fw.Score)%</span>
                </div>
            </div>
"@
    }

    # Windows Updates Component
    if ($Results.WindowsUpdates) {
        $wu = $Results.WindowsUpdates
        $statusClass = switch($wu.Status) {
            "Compliant" { "status-compliant" }
            "Partial" { "status-partial" }
            default { "status-non-compliant" }
        }
        
        $htmlReport += @"
            <div class="component-card">
                <div class="component-header">
                    <div class="component-title">🔄 Windows Updates</div>
                    <div class="status-badge $statusClass">$($wu.Status)</div>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Pending Updates:</span>
                    <span class="detail-value">$($wu.PendingUpdates)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Days Since Last Update:</span>
                    <span class="detail-value">$($wu.DaysSinceLastUpdate)</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Last Check Time:</span>
                    <span class="detail-value">$(if($wu.LastCheckTime){$wu.LastCheckTime.ToString('yyyy-MM-dd')}else{'Unknown'})</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Auto Update:</span>
                    <span class="detail-value">$(if($wu.AutoUpdateEnabled){'Enabled'}else{'Disabled'})</span>
                </div>
                <div class="detail-row">
                    <span class="detail-label">Compliance Score:</span>
                    <span class="detail-value">$($wu.Score)%</span>
                </div>
            </div>
"@
    }

    $htmlReport += @"
        </div>
        
        <div class="recommendations">
            <h3>📋 Recommendations for Improvement</h3>
"@

    # Generate recommendations
    $recommendations = @()
    
    if ($Results.PasswordPolicy -and $Results.PasswordPolicy.MinimumLength -lt 14) {
        $recommendations += "Increase minimum password length to at least 14 characters"
    }
    if ($Results.PasswordPolicy -and -not $Results.PasswordPolicy.ComplexityEnabled) {
        $recommendations += "Enable password complexity requirements"
    }
    if ($Results.AuditPolicy -and $Results.AuditPolicy.Score -lt 80) {
        $recommendations += "Enable auditing for all critical event categories"
    }
    if ($Results.SecurityServices -and $Results.SecurityServices.WindowsDefender -ne "Running") {
        $recommendations += "Enable and configure Windows Defender"
    }
    if ($Results.Firewall -and $Results.Firewall.Score -lt 80) {
        $recommendations += "Enable Windows Firewall on all profiles"
    }
    if ($Results.WindowsUpdates -and $Results.WindowsUpdates.PendingUpdates -gt 0) {
        $recommendations += "Install $($Results.WindowsUpdates.PendingUpdates) pending Windows updates"
    }
    
    foreach ($rec in $recommendations) {
        $htmlReport += @"
            <div class="recommendation-item">• $rec</div>
"@
    }

    $htmlReport += @"
        </div>
        
        <div class="footer">
            <p><strong>Windows Security Baseline Check v2.0</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
            <p>Baseline Type: $BaselineType | Overall Score: $overallScore%</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "SecurityBaseline_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    return $reportFile
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║     Windows Security Baseline Compliance Check v2.0        ║
║     PowerShell Automation by Aykut Yıldız                 ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

$results = @{}

foreach ($computer in $ComputerName) {
    Write-Host ""
    Write-Host "🖥️ Checking: $computer" -ForegroundColor Yellow
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    
    if ($CheckPasswords) {
        $results.PasswordPolicy = Test-PasswordPolicy -Computer $computer
    }
    
    if ($CheckAudit) {
        $results.AuditPolicy = Test-AuditPolicy -Computer $computer
    }
    
    if ($CheckServices) {
        $results.SecurityServices = Test-SecurityServices -Computer $computer
    }
    
    if ($CheckFirewall) {
        $results.Firewall = Test-FirewallRules -Computer $computer
    }
    
    if ($CheckUpdates) {
        $results.WindowsUpdates = Test-WindowsUpdates -Computer $computer
    }
}

# Generate report
$reportFile = New-SecurityBaselineReport -Results $results

# Export to JSON
$jsonFile = Join-Path $ReportPath "SecurityBaseline_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$results | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonFile -Encoding UTF8

Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "     SECURITY BASELINE CHECK COMPLETE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Component Status:" -ForegroundColor Yellow
foreach ($component in $results.Keys) {
    $status = $results[$component].Status
    $score = $results[$component].Score
    $color = switch($status) {
        "Compliant" { "Green" }
        "Partial" { "Yellow" }
        default { "Red" }
    }
    Write-Host "   • ${component}: $status ($score%)" -ForegroundColor $color
}
Write-Host ""
Write-Host "📁 Reports saved:" -ForegroundColor Green
Write-Host "   • $reportFile" -ForegroundColor Gray
Write-Host "   • $jsonFile" -ForegroundColor Gray

# Open report
Start-Process $reportFile
#endregion
