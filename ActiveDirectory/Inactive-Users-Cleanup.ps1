<#
.SYNOPSIS
    Inactive Users Cleanup Tool for Active Directory
    
.DESCRIPTION
    Identifies and manages inactive Active Directory users based on last logon time,
    with options to disable, move to different OU, or delete accounts.
    
.PARAMETER DaysInactive
    Number of days to consider a user inactive (default: 90)
    
.PARAMETER Action
    Action to take: Report, Disable, Move, Delete
    
.PARAMETER TargetOU
    Target OU for moving inactive users
    
.EXAMPLE
    .\Inactive-Users-Cleanup.ps1 -DaysInactive 90 -Action Disable
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.2
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [int]$DaysInactive = 90,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Report", "Disable", "Move", "Delete")]
    [string]$Action = "Report",
    
    [Parameter(Mandatory=$false)]
    [string]$TargetOU = "OU=InactiveUsers,DC=domain,DC=local",
    
    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeOU = @("OU=ServiceAccounts", "OU=Administrators"),
    
    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeUsers = @("Administrator", "Guest"),
    
    [Parameter(Mandatory=$false)]
    [bool]$ExportToCSV = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\AD-Cleanup"
)

#region Functions
function Find-InactiveUsers {
    $inactiveDate = (Get-Date).AddDays(-$DaysInactive)
    
    Write-Host "🔍 Searching for users inactive since: $($inactiveDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
    
    $allUsers = Get-ADUser -Filter * -Properties LastLogonDate, Created, Enabled, EmailAddress, Department, Title, Manager, MemberOf
    
    $inactiveUsers = $allUsers | Where-Object {
        $_.Enabled -eq $true -and
        $_.LastLogonDate -lt $inactiveDate -and
        $_.SamAccountName -notin $ExcludeUsers -and
        ($ExcludeOU | ForEach-Object { $_.DistinguishedName -notlike "*$_*" }) -notcontains $false
    }
    
    return $inactiveUsers
}

function Process-InactiveUser {
    param($User, $Action)
    
    switch ($Action) {
        "Disable" {
            Disable-ADAccount -Identity $User
            Set-ADUser -Identity $User -Description "Disabled on $(Get-Date -Format 'yyyy-MM-dd') - Inactive"
            Write-Host "   ✅ Disabled: $($User.SamAccountName)" -ForegroundColor Yellow
        }
        "Move" {
            Move-ADObject -Identity $User.DistinguishedName -TargetPath $TargetOU
            Write-Host "   ✅ Moved: $($User.SamAccountName)" -ForegroundColor Blue
        }
        "Delete" {
            Remove-ADUser -Identity $User -Confirm:$false
            Write-Host "   ✅ Deleted: $($User.SamAccountName)" -ForegroundColor Red
        }
    }
}

function Export-InactiveUsersReport {
    param($Users)
    
    $reportData = $Users | Select-Object @{
        Name='Username'; Expression={$_.SamAccountName}
    }, @{
        Name='Full Name'; Expression={$_.Name}
    }, @{
        Name='Email'; Expression={$_.EmailAddress}
    }, @{
        Name='Department'; Expression={$_.Department}
    }, @{
        Name='Title'; Expression={$_.Title}
    }, @{
        Name='Last Logon'; Expression={
            if($_.LastLogonDate) { $_.LastLogonDate.ToString('yyyy-MM-dd') }
            else { 'Never' }
        }
    }, @{
        Name='Days Inactive'; Expression={
            if($_.LastLogonDate) { ((Get-Date) - $_.LastLogonDate).Days }
            else { 'N/A' }
        }
    }, @{
        Name='Created'; Expression={$_.Created.ToString('yyyy-MM-dd')}
    }, @{
        Name='Groups'; Expression={
            ($_.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }) -join '; '
        }
    }
    
    # Export to CSV
    $csvFile = Join-Path $ReportPath "InactiveUsers_$(Get-Date -Format 'yyyyMMdd').csv"
    $reportData | Export-Csv -Path $csvFile -NoTypeInformation
    
    # Create HTML Report
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Inactive Users Report</title>
    <style>
        body { font-family: Arial; margin: 20px; background: #f0f0f0; }
        .container { max-width: 1400px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
        h1 { color: #d35400; border-bottom: 3px solid #e67e22; padding-bottom: 10px; }
        .summary { background: #fff3cd; padding: 15px; border-radius: 5px; margin: 20px 0; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #e67e22; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .never { color: #e74c3c; font-weight: bold; }
        .footer { text-align: center; margin-top: 30px; color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚠️ Inactive Users Report</h1>
        <div class="summary">
            <strong>Report Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm')<br>
            <strong>Inactive Threshold:</strong> $DaysInactive days<br>
            <strong>Total Inactive Users:</strong> $($Users.Count)<br>
            <strong>Action Taken:</strong> $Action<br>
            <strong>Generated by:</strong> Aykut Yıldız
        </div>
        <table>
            <thead>
                <tr>
                    <th>Username</th>
                    <th>Full Name</th>
                    <th>Email</th>
                    <th>Department</th>
                    <th>Last Logon</th>
                    <th>Days Inactive</th>
                    <th>Account Created</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($user in $reportData | Sort-Object 'Days Inactive' -Descending) {
        $lastLogonClass = if ($user.'Last Logon' -eq 'Never') { 'class="never"' } else { '' }
        $htmlReport += @"
                <tr>
                    <td>$($user.Username)</td>
                    <td>$($user.'Full Name')</td>
                    <td>$($user.Email)</td>
                    <td>$($user.Department)</td>
                    <td $lastLogonClass>$($user.'Last Logon')</td>
                    <td>$($user.'Days Inactive')</td>
                    <td>$($user.Created)</td>
                </tr>
"@
    }

    $htmlReport += @"
            </tbody>
        </table>
        <div class="footer">
            <p>Inactive Users Cleanup Tool v1.2 | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    $htmlFile = Join-Path $ReportPath "InactiveUsers_$(Get-Date -Format 'yyyyMMdd').html"
    $htmlReport | Out-File -FilePath $htmlFile -Encoding UTF8
    
    return @($csvFile, $htmlFile)
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║       Inactive Users Cleanup Tool v1.2                     ║
║       PowerShell Automation by Aykut Yıldız               ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

# Import AD Module
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

# Find inactive users
$inactiveUsers = Find-InactiveUsers

Write-Host ""
Write-Host "📊 Found $($inactiveUsers.Count) inactive users" -ForegroundColor Yellow

if ($inactiveUsers.Count -gt 0) {
    # Export report
    if ($ExportToCSV) {
        $reports = Export-InactiveUsersReport -Users $inactiveUsers
        Write-Host "📁 Reports saved:" -ForegroundColor Green
        foreach ($report in $reports) {
            Write-Host "   • $report" -ForegroundColor Gray
        }
    }
    
    # Take action if not just reporting
    if ($Action -ne "Report") {
        Write-Host ""
        Write-Host "⚡ Executing action: $Action" -ForegroundColor Yellow
        
        foreach ($user in $inactiveUsers) {
            Process-InactiveUser -User $user -Action $Action
        }
        
        Write-Host ""
        Write-Host "✅ Action completed for $($inactiveUsers.Count) users" -ForegroundColor Green
    }
    
    # Open HTML report
    if ($reports[1]) {
        Start-Process $reports[1]
    }
} else {
    Write-Host "✅ No inactive users found!" -ForegroundColor Green
}
#endregion
