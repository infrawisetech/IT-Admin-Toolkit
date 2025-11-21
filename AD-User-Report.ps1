<#
.SYNOPSIS
    Active Directory Kullanıcı Raporu Oluşturma Script'i
    
.DESCRIPTION
    Bu script Active Directory'deki kullanıcıların detaylı raporunu oluşturur.
    Inactive kullanıcıları, password expire olanları, locked hesapları tespit eder.
    Raporu HTML ve CSV formatında export eder.
    
.PARAMETER ExportPath
    Raporun kaydedileceği dizin (Default: C:\AD-Reports)
    
.PARAMETER DaysInactive
    Kaç gündür login olmayan kullanıcıları inactive sayacağı (Default: 30)
    
.PARAMETER EmailReport
    Raporu email ile gönder (True/False)
    
.EXAMPLE
    .\AD-User-Report.ps1 -ExportPath "C:\Reports" -DaysInactive 45
    
.EXAMPLE
    .\AD-User-Report.ps1 -EmailReport $true
    
.NOTES
    Author: Aykut Yıldız - CTO @ Sarsilmaz Silah Sanayi
    Version: 2.0
    Date: 2024-11-21
    Requires: Active Directory PowerShell Module
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ExportPath = "C:\AD-Reports",
    
    [Parameter(Mandatory=$false)]
    [int]$DaysInactive = 30,
    
    [Parameter(Mandatory=$false)]
    [bool]$EmailReport = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$SmtpServer = "smtp.company.local",
    
    [Parameter(Mandatory=$false)]
    [string]$EmailTo = "it-team@company.com",
    
    [Parameter(Mandatory=$false)]
    [string]$EmailFrom = "ad-reports@company.com"
)

#region Functions
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "Error" { Write-Host $logMessage -ForegroundColor Red }
        "Warning" { Write-Host $logMessage -ForegroundColor Yellow }
        "Success" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor White }
    }
    
    # Log to file
    $logFile = Join-Path $ExportPath "AD-Report-$(Get-Date -Format 'yyyy-MM-dd').log"
    Add-Content -Path $logFile -Value $logMessage
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "Info"
    
    # Check AD Module
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Log "Active Directory module is not installed!" "Error"
        Write-Log "Installing RSAT-AD-PowerShell..." "Warning"
        
        try {
            Add-WindowsFeature RSAT-AD-PowerShell
            Import-Module ActiveDirectory
            Write-Log "AD Module installed successfully" "Success"
        }
        catch {
            Write-Log "Failed to install AD Module: $_" "Error"
            return $false
        }
    }
    else {
        Import-Module ActiveDirectory -ErrorAction SilentlyContinue
        Write-Log "AD Module loaded successfully" "Success"
    }
    
    # Check export path
    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
        Write-Log "Created export directory: $ExportPath" "Info"
    }
    
    return $true
}

function Get-ADUserStatistics {
    Write-Log "Collecting AD user statistics..." "Info"
    
    $stats = @{
        TotalUsers = 0
        ActiveUsers = 0
        DisabledUsers = 0
        LockedUsers = 0
        ExpiredPasswords = 0
        NeverExpirePasswords = 0
        InactiveUsers = 0
        NewUsers = 0
        AdminUsers = 0
    }
    
    try {
        $allUsers = Get-ADUser -Filter * -Properties *
        $stats.TotalUsers = $allUsers.Count
        
        $stats.ActiveUsers = ($allUsers | Where-Object {$_.Enabled -eq $true}).Count
        $stats.DisabledUsers = ($allUsers | Where-Object {$_.Enabled -eq $false}).Count
        $stats.LockedUsers = ($allUsers | Where-Object {$_.LockedOut -eq $true}).Count
        
        $currentDate = Get-Date
        $inactiveDate = $currentDate.AddDays(-$DaysInactive)
        $newUserDate = $currentDate.AddDays(-7)
        
        $stats.InactiveUsers = ($allUsers | Where-Object {
            $_.LastLogonDate -lt $inactiveDate -and $_.Enabled -eq $true
        }).Count
        
        $stats.NewUsers = ($allUsers | Where-Object {
            $_.WhenCreated -gt $newUserDate
        }).Count
        
        $stats.ExpiredPasswords = ($allUsers | Where-Object {
            $_.PasswordExpired -eq $true -and $_.Enabled -eq $true
        }).Count
        
        $stats.NeverExpirePasswords = ($allUsers | Where-Object {
            $_.PasswordNeverExpires -eq $true -and $_.Enabled -eq $true
        }).Count
        
        # Admin group members
        $adminGroup = Get-ADGroupMember -Identity "Domain Admins" -Recursive
        $stats.AdminUsers = $adminGroup.Count
        
        Write-Log "Statistics collected successfully" "Success"
        return $stats
    }
    catch {
        Write-Log "Error collecting statistics: $_" "Error"
        return $null
    }
}

function Get-DetailedUserReport {
    Write-Log "Generating detailed user report..." "Info"
    
    try {
        $users = Get-ADUser -Filter * -Properties * | Select-Object @{
            Name = 'Kullanıcı Adı'; Expression = {$_.SamAccountName}
        }, @{
            Name = 'Ad Soyad'; Expression = {$_.DisplayName}
        }, @{
            Name = 'Email'; Expression = {$_.EmailAddress}
        }, @{
            Name = 'Departman'; Expression = {$_.Department}
        }, @{
            Name = 'Ünvan'; Expression = {$_.Title}
        }, @{
            Name = 'Durum'; Expression = {if($_.Enabled) {'Aktif'} else {'Pasif'}}
        }, @{
            Name = 'Oluşturma Tarihi'; Expression = {$_.WhenCreated.ToString('dd.MM.yyyy')}
        }, @{
            Name = 'Son Giriş'; Expression = {
                if($_.LastLogonDate) {
                    $_.LastLogonDate.ToString('dd.MM.yyyy HH:mm')
                } else {
                    'Hiç giriş yapmadı'
                }
            }
        }, @{
            Name = 'Şifre Son Değişim'; Expression = {
                if($_.PasswordLastSet) {
                    $_.PasswordLastSet.ToString('dd.MM.yyyy')
                } else {
                    'Belirlenmemiş'
                }
            }
        }, @{
            Name = 'Şifre Durumu'; Expression = {
                if($_.PasswordNeverExpires) {
                    'Süresiz'
                } elseif($_.PasswordExpired) {
                    'Süresi Dolmuş'
                } else {
                    'Aktif'
                }
            }
        }, @{
            Name = 'Hesap Kilitli'; Expression = {if($_.LockedOut) {'Evet'} else {'Hayır'}}
        }, @{
            Name = 'Gruplar'; Expression = {
                (Get-ADPrincipalGroupMembership $_.SamAccountName | 
                 Select-Object -ExpandProperty Name) -join ', '
            }
        }
        
        Write-Log "Detailed report generated for $($users.Count) users" "Success"
        return $users
    }
    catch {
        Write-Log "Error generating detailed report: $_" "Error"
        return $null
    }
}

function Export-ReportToHTML {
    param(
        [Parameter(Mandatory=$true)]
        $UserData,
        
        [Parameter(Mandatory=$true)]
        $Statistics
    )
    
    Write-Log "Generating HTML report..." "Info"
    
    $htmlReport = @"
<!DOCTYPE html>
<html lang="tr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Active Directory Kullanıcı Raporu - $(Get-Date -Format 'dd.MM.yyyy')</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header .date {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
        }
        
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 20px rgba(0,0,0,0.15);
        }
        
        .stat-card .number {
            font-size: 2em;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 5px;
        }
        
        .stat-card .label {
            color: #666;
            font-size: 0.9em;
        }
        
        .filters {
            padding: 20px 30px;
            background: #fff;
            border-bottom: 1px solid #e0e0e0;
        }
        
        .filter-input {
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            width: 300px;
            font-size: 16px;
        }
        
        .table-container {
            padding: 0 30px 30px;
            overflow-x: auto;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        
        thead {
            background: #667eea;
            color: white;
        }
        
        th {
            padding: 15px;
            text-align: left;
            font-weight: 500;
            position: sticky;
            top: 0;
            background: #667eea;
        }
        
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #e0e0e0;
        }
        
        tbody tr:hover {
            background: #f5f5f5;
        }
        
        .status-active {
            color: #4caf50;
            font-weight: bold;
        }
        
        .status-inactive {
            color: #f44336;
            font-weight: bold;
        }
        
        .status-locked {
            background: #ffeb3b;
            padding: 2px 8px;
            border-radius: 3px;
        }
        
        .footer {
            background: #f8f9fa;
            padding: 20px;
            text-align: center;
            color: #666;
        }
        
        @media print {
            body {
                background: white;
                padding: 0;
            }
            
            .filters {
                display: none;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Active Directory Kullanıcı Raporu</h1>
            <div class="date">$(Get-Date -Format 'dd MMMM yyyy, HH:mm')</div>
        </div>
        
        <div class="stats-grid">
            <div class="stat-card">
                <div class="number">$($Statistics.TotalUsers)</div>
                <div class="label">Toplam Kullanıcı</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.ActiveUsers)</div>
                <div class="label">Aktif Kullanıcı</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.DisabledUsers)</div>
                <div class="label">Pasif Kullanıcı</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.LockedUsers)</div>
                <div class="label">Kilitli Hesap</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.InactiveUsers)</div>
                <div class="label">$DaysInactive Gündür Giriş Yapmayan</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.ExpiredPasswords)</div>
                <div class="label">Şifresi Dolmuş</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.NeverExpirePasswords)</div>
                <div class="label">Süresiz Şifre</div>
            </div>
            <div class="stat-card">
                <div class="number">$($Statistics.NewUsers)</div>
                <div class="label">Son 7 Günde Eklenen</div>
            </div>
        </div>
        
        <div class="filters">
            <input type="text" class="filter-input" id="searchInput" placeholder="Tabloda ara..." onkeyup="filterTable()">
        </div>
        
        <div class="table-container">
            <table id="userTable">
                <thead>
                    <tr>
                        <th>Kullanıcı Adı</th>
                        <th>Ad Soyad</th>
                        <th>Email</th>
                        <th>Departman</th>
                        <th>Ünvan</th>
                        <th>Durum</th>
                        <th>Son Giriş</th>
                        <th>Şifre Durumu</th>
                        <th>Kilitli</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($user in $UserData) {
        $statusClass = if ($user.'Durum' -eq 'Aktif') { 'status-active' } else { 'status-inactive' }
        $lockedClass = if ($user.'Hesap Kilitli' -eq 'Evet') { 'status-locked' } else { '' }
        
        $htmlReport += @"
                    <tr>
                        <td>$($user.'Kullanıcı Adı')</td>
                        <td>$($user.'Ad Soyad')</td>
                        <td>$($user.Email)</td>
                        <td>$($user.Departman)</td>
                        <td>$($user.Ünvan)</td>
                        <td class="$statusClass">$($user.Durum)</td>
                        <td>$($user.'Son Giriş')</td>
                        <td>$($user.'Şifre Durumu')</td>
                        <td class="$lockedClass">$($user.'Hesap Kilitli')</td>
                    </tr>
"@
    }

    $htmlReport += @"
                </tbody>
            </table>
        </div>
        
        <div class="footer">
            <p>Rapor Sarsilmaz Silah Sanayi IT Departmanı tarafından oluşturulmuştur</p>
            <p>PowerShell AD Reporting Tool v2.0</p>
        </div>
    </div>
    
    <script>
        function filterTable() {
            var input = document.getElementById("searchInput");
            var filter = input.value.toUpperCase();
            var table = document.getElementById("userTable");
            var tr = table.getElementsByTagName("tr");
            
            for (var i = 1; i < tr.length; i++) {
                var display = false;
                var td = tr[i].getElementsByTagName("td");
                
                for (var j = 0; j < td.length; j++) {
                    if (td[j]) {
                        var txtValue = td[j].textContent || td[j].innerText;
                        if (txtValue.toUpperCase().indexOf(filter) > -1) {
                            display = true;
                            break;
                        }
                    }
                }
                
                tr[i].style.display = display ? "" : "none";
            }
        }
    </script>
</body>
</html>
"@
    
    $htmlFile = Join-Path $ExportPath "AD-Report-$(Get-Date -Format 'yyyy-MM-dd-HHmm').html"
    $htmlReport | Out-File -FilePath $htmlFile -Encoding UTF8
    
    Write-Log "HTML report saved to: $htmlFile" "Success"
    return $htmlFile
}

function Send-EmailReport {
    param(
        [string]$HtmlFile,
        [string]$CsvFile
    )
    
    Write-Log "Sending email report..." "Info"
    
    try {
        $subject = "Active Directory Kullanıcı Raporu - $(Get-Date -Format 'dd.MM.yyyy')"
        
        $body = @"
<html>
<body style="font-family: Arial, sans-serif;">
    <h2>Active Directory Haftalık Rapor</h2>
    <p>Merhaba,</p>
    <p>$(Get-Date -Format 'dd MMMM yyyy') tarihli Active Directory kullanıcı raporu ekte sunulmuştur.</p>
    <p>Rapor Detayları:</p>
    <ul>
        <li>HTML formatında detaylı rapor</li>
        <li>CSV formatında veri export'u</li>
    </ul>
    <p>Saygılarımla,<br>IT Departmanı</p>
</body>
</html>
"@
        
        Send-MailMessage -SmtpServer $SmtpServer `
                        -From $EmailFrom `
                        -To $EmailTo `
                        -Subject $subject `
                        -Body $body `
                        -BodyAsHtml `
                        -Attachments $HtmlFile, $CsvFile
        
        Write-Log "Email sent successfully to $EmailTo" "Success"
    }
    catch {
        Write-Log "Failed to send email: $_" "Error"
    }
}
#endregion

#region Main Script
function Main {
    Write-Host @"
╔════════════════════════════════════════════════════════════╗
║     Active Directory User Report Tool v2.0                 ║
║     Sarsilmaz Silah Sanayi IT Department                  ║
║     ──────────────────────────────────────────────────    ║
║     PowerShell Automation by Aykut Yıldız                 ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    # Check prerequisites
    if (-not (Test-Prerequisites)) {
        Write-Log "Prerequisites check failed. Exiting..." "Error"
        return
    }
    
    # Collect statistics
    Write-Log "Starting AD report generation..." "Info"
    $stats = Get-ADUserStatistics
    
    if ($null -eq $stats) {
        Write-Log "Failed to collect statistics. Exiting..." "Error"
        return
    }
    
    # Generate detailed report
    $detailedReport = Get-DetailedUserReport
    
    if ($null -eq $detailedReport) {
        Write-Log "Failed to generate detailed report. Exiting..." "Error"
        return
    }
    
    # Export to CSV
    $csvFile = Join-Path $ExportPath "AD-Report-$(Get-Date -Format 'yyyy-MM-dd-HHmm').csv"
    $detailedReport | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
    Write-Log "CSV report saved to: $csvFile" "Success"
    
    # Generate HTML report
    $htmlFile = Export-ReportToHTML -UserData $detailedReport -Statistics $stats
    
    # Send email if requested
    if ($EmailReport) {
        Send-EmailReport -HtmlFile $htmlFile -CsvFile $csvFile
    }
    
    # Summary
    Write-Host ""
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "     RAPOR BAŞARIYLA OLUŞTURULDU!" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""
    Write-Host "📊 İstatistikler:" -ForegroundColor Yellow
    Write-Host "   • Toplam Kullanıcı: $($stats.TotalUsers)"
    Write-Host "   • Aktif Kullanıcı: $($stats.ActiveUsers)"
    Write-Host "   • Problem Tespit Edilen: $($stats.LockedUsers + $stats.ExpiredPasswords)"
    Write-Host ""
    Write-Host "📁 Raporlar:" -ForegroundColor Yellow
    Write-Host "   • HTML: $htmlFile"
    Write-Host "   • CSV: $csvFile"
    Write-Host ""
    
    # Open HTML report
    Start-Process $htmlFile
}

# Run the script
Main
#endregion
