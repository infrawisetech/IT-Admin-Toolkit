<#
.SYNOPSIS
    Active Directory Group Management Tool
    
.DESCRIPTION
    Manages AD groups with bulk operations including member management,
    permission auditing, and nested group analysis.
    
.PARAMETER Operation
    Operation type: AddMembers, RemoveMembers, CreateGroups, AuditGroups
    
.PARAMETER CSVPath
    Path to CSV file for bulk operations
    
.EXAMPLE
    .\Group-Management.ps1 -Operation AddMembers -CSVPath "C:\GroupMembers.csv"
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.3
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("AddMembers", "RemoveMembers", "CreateGroups", "AuditGroups", "CloneGroup")]
    [string]$Operation,
    
    [Parameter(Mandatory=$false)]
    [string]$CSVPath,
    
    [Parameter(Mandatory=$false)]
    [string]$GroupName,
    
    [Parameter(Mandatory=$false)]
    [bool]$RecursiveMembers = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\AD-Groups"
)

#region Functions
function Add-BulkGroupMembers {
    # CSV Format: GroupName,Username
    $members = Import-Csv $CSVPath
    $results = @()
    
    foreach ($member in $members) {
        try {
            Add-ADGroupMember -Identity $member.GroupName -Members $member.Username
            Write-Host "✅ Added $($member.Username) to $($member.GroupName)" -ForegroundColor Green
            $results += [PSCustomObject]@{
                Group = $member.GroupName
                User = $member.Username
                Action = "Added"
                Status = "Success"
            }
        }
        catch {
            Write-Host "❌ Failed to add $($member.Username): $_" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Group = $member.GroupName
                User = $member.Username
                Action = "Added"
                Status = "Failed: $_"
            }
        }
    }
    
    return $results
}

function Remove-BulkGroupMembers {
    $members = Import-Csv $CSVPath
    $results = @()
    
    foreach ($member in $members) {
        try {
            Remove-ADGroupMember -Identity $member.GroupName -Members $member.Username -Confirm:$false
            Write-Host "✅ Removed $($member.Username) from $($member.GroupName)" -ForegroundColor Yellow
            $results += [PSCustomObject]@{
                Group = $member.GroupName
                User = $member.Username
                Action = "Removed"
                Status = "Success"
            }
        }
        catch {
            Write-Host "❌ Failed to remove $($member.Username): $_" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Group = $member.GroupName
                User = $member.Username
                Action = "Removed"
                Status = "Failed: $_"
            }
        }
    }
    
    return $results
}

function New-BulkADGroups {
    # CSV Format: GroupName,Description,GroupCategory,GroupScope,ManagedBy
    $groups = Import-Csv $CSVPath
    $results = @()
    
    foreach ($group in $groups) {
        try {
            $params = @{
                Name = $group.GroupName
                Description = $group.Description
                GroupCategory = if ($group.GroupCategory) { $group.GroupCategory } else { "Security" }
                GroupScope = if ($group.GroupScope) { $group.GroupScope } else { "Global" }
                Path = if ($group.OU) { $group.OU } else { "CN=Users,$((Get-ADDomain).DistinguishedName)" }
            }
            
            if ($group.ManagedBy) {
                $params.ManagedBy = $group.ManagedBy
            }
            
            New-ADGroup @params
            Write-Host "✅ Created group: $($group.GroupName)" -ForegroundColor Green
            
            $results += [PSCustomObject]@{
                GroupName = $group.GroupName
                Description = $group.Description
                Status = "Created"
            }
        }
        catch {
            Write-Host "❌ Failed to create $($group.GroupName): $_" -ForegroundColor Red
            $results += [PSCustomObject]@{
                GroupName = $group.GroupName
                Description = $group.Description
                Status = "Failed: $_"
            }
        }
    }
    
    return $results
}

function Get-GroupAuditReport {
    Write-Host "🔍 Auditing all AD groups..." -ForegroundColor Cyan
    
    $allGroups = Get-ADGroup -Filter * -Properties Members, ManagedBy, Created, Modified, Description
    $auditData = @()
    
    foreach ($group in $allGroups) {
        $members = @()
        if ($RecursiveMembers) {
            $members = Get-ADGroupMember -Identity $group -Recursive | Select-Object -Unique
        } else {
            $members = Get-ADGroupMember -Identity $group
        }
        
        $auditData += [PSCustomObject]@{
            GroupName = $group.Name
            Description = $group.Description
            GroupScope = $group.GroupScope
            GroupCategory = $group.GroupCategory
            MemberCount = $members.Count
            DirectMembers = (Get-ADGroupMember -Identity $group).Count
            Created = $group.Created
            Modified = $group.Modified
            ManagedBy = if ($group.ManagedBy) { (Get-ADUser $group.ManagedBy -ErrorAction SilentlyContinue).Name } else { "Not Set" }
            NestedGroups = ($members | Where-Object {$_.objectClass -eq 'group'}).Count
            Users = ($members | Where-Object {$_.objectClass -eq 'user'}).Count
            Computers = ($members | Where-Object {$_.objectClass -eq 'computer'}).Count
        }
        
        Write-Host "   • $($group.Name): $($members.Count) members" -ForegroundColor Gray
    }
    
    # Generate HTML Report
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Group Audit Report</title>
    <style>
        body { font-family: Arial; background: #f5f5f5; margin: 20px; }
        .container { max-width: 1600px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
        h1 { color: #2980b9; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        .stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 30px 0; }
        .stat-card { background: #ecf0f1; padding: 20px; border-radius: 8px; text-align: center; }
        .stat-value { font-size: 2.5em; font-weight: bold; color: #2c3e50; }
        .stat-label { color: #7f8c8d; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #3498db; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ecf0f1; }
        tr:hover { background: #f8f9fa; }
        .empty-group { background: #fff3cd; }
        .large-group { background: #d1ecf1; }
        .footer { text-align: center; margin-top: 30px; color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔐 Active Directory Group Audit Report</h1>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm') | <strong>By:</strong> Aykut Yıldız</p>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value">$($auditData.Count)</div>
                <div class="stat-label">Total Groups</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$(($auditData | Measure-Object MemberCount -Sum).Sum)</div>
                <div class="stat-label">Total Memberships</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$(($auditData | Where-Object {$_.MemberCount -eq 0}).Count)</div>
                <div class="stat-label">Empty Groups</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$(($auditData | Where-Object {$_.MemberCount -gt 100}).Count)</div>
                <div class="stat-label">Large Groups (>100)</div>
            </div>
        </div>
        
        <h2>Group Details</h2>
        <table>
            <thead>
                <tr>
                    <th>Group Name</th>
                    <th>Description</th>
                    <th>Scope</th>
                    <th>Category</th>
                    <th>Total Members</th>
                    <th>Users</th>
                    <th>Groups</th>
                    <th>Computers</th>
                    <th>Managed By</th>
                    <th>Created</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($group in $auditData | Sort-Object MemberCount -Descending) {
        $rowClass = if ($group.MemberCount -eq 0) { 'class="empty-group"' }
                   elseif ($group.MemberCount -gt 100) { 'class="large-group"' }
                   else { '' }
        
        $htmlReport += @"
                <tr $rowClass>
                    <td><strong>$($group.GroupName)</strong></td>
                    <td>$($group.Description)</td>
                    <td>$($group.GroupScope)</td>
                    <td>$($group.GroupCategory)</td>
                    <td><strong>$($group.MemberCount)</strong></td>
                    <td>$($group.Users)</td>
                    <td>$($group.NestedGroups)</td>
                    <td>$($group.Computers)</td>
                    <td>$($group.ManagedBy)</td>
                    <td>$($group.Created.ToString('yyyy-MM-dd'))</td>
                </tr>
"@
    }

    $htmlReport += @"
            </tbody>
        </table>
        
        <div class="footer">
            <p>AD Group Management Tool v1.3 | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    # Save reports
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    $htmlFile = Join-Path $ReportPath "GroupAudit_$(Get-Date -Format 'yyyyMMdd').html"
    $csvFile = Join-Path $ReportPath "GroupAudit_$(Get-Date -Format 'yyyyMMdd').csv"
    
    $htmlReport | Out-File -FilePath $htmlFile -Encoding UTF8
    $auditData | Export-Csv -Path $csvFile -NoTypeInformation
    
    Write-Host ""
    Write-Host "📁 Reports saved:" -ForegroundColor Green
    Write-Host "   • $htmlFile" -ForegroundColor Gray
    Write-Host "   • $csvFile" -ForegroundColor Gray
    
    Start-Process $htmlFile
}

function Copy-ADGroupMembership {
    param(
        [string]$SourceGroup,
        [string]$TargetGroup
    )
    
    Write-Host "📋 Cloning group membership from $SourceGroup to $TargetGroup" -ForegroundColor Cyan
    
    try {
        # Get source group members
        $members = Get-ADGroupMember -Identity $SourceGroup
        
        # Add to target group
        foreach ($member in $members) {
            try {
                Add-ADGroupMember -Identity $TargetGroup -Members $member
                Write-Host "   ✅ Added: $($member.Name)" -ForegroundColor Green
            }
            catch {
                Write-Host "   ⚠️ Failed: $($member.Name) - $_" -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
        Write-Host "✅ Cloned $($members.Count) members successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to clone group: $_" -ForegroundColor Red
    }
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║       Active Directory Group Management Tool v1.3          ║
║       PowerShell Automation by Aykut Yıldız               ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Import-Module ActiveDirectory -ErrorAction Stop

Write-Host ""
Write-Host "🔧 Operation: $Operation" -ForegroundColor Yellow
Write-Host ""

switch ($Operation) {
    "AddMembers" {
        if (-not $CSVPath) {
            Write-Host "❌ CSV path required for bulk add operation" -ForegroundColor Red
            return
        }
        $results = Add-BulkGroupMembers
        $results | Export-Csv -Path (Join-Path $ReportPath "AddMembers_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
    
    "RemoveMembers" {
        if (-not $CSVPath) {
            Write-Host "❌ CSV path required for bulk remove operation" -ForegroundColor Red
            return
        }
        $results = Remove-BulkGroupMembers
        $results | Export-Csv -Path (Join-Path $ReportPath "RemoveMembers_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
    
    "CreateGroups" {
        if (-not $CSVPath) {
            Write-Host "❌ CSV path required for bulk creation" -ForegroundColor Red
            return
        }
        $results = New-BulkADGroups
        $results | Export-Csv -Path (Join-Path $ReportPath "CreateGroups_$(Get-Date -Format 'yyyyMMdd').csv") -NoTypeInformation
    }
    
    "AuditGroups" {
        Get-GroupAuditReport
    }
    
    "CloneGroup" {
        if (-not $GroupName) {
            $SourceGroup = Read-Host "Enter source group name"
            $TargetGroup = Read-Host "Enter target group name"
            Copy-ADGroupMembership -SourceGroup $SourceGroup -TargetGroup $TargetGroup
        }
    }
}

Write-Host ""
Write-Host "✅ Operation completed successfully!" -ForegroundColor Green
#endregion
