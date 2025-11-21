<#
.SYNOPSIS
    Network Port Scanner Tool
    
.DESCRIPTION
    Scans network ports to identify open services, detect vulnerabilities,
    and create network inventory for security assessment.
    
.PARAMETER Target
    Target IP address or hostname to scan
    
.PARAMETER PortRange
    Port range to scan (e.g., "1-1000" or specific ports "80,443,3389")
    
.PARAMETER ScanType
    Type of scan: Quick, Full, Custom, Stealth
    
.EXAMPLE
    .\Port-Scanner.ps1 -Target "192.168.1.0/24" -ScanType "Quick"
    
.NOTES
    Author: Aykut Yıldız
    Version: 1.8
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Target,
    
    [Parameter(Mandatory=$false)]
    [string]$PortRange = "1-1000",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Quick", "Full", "Custom", "Stealth")]
    [string]$ScanType = "Quick",
    
    [Parameter(Mandatory=$false)]
    [int]$Timeout = 500,
    
    [Parameter(Mandatory=$false)]
    [int]$Threads = 10,
    
    [Parameter(Mandatory=$false)]
    [bool]$ResolveServices = $true,
    
    [Parameter(Mandatory=$false)]
    [bool]$DetectOS = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\PortScanReports"
)

#region Port Definitions
$CommonPorts = @{
    21 = "FTP"
    22 = "SSH"
    23 = "Telnet"
    25 = "SMTP"
    53 = "DNS"
    80 = "HTTP"
    110 = "POP3"
    111 = "RPC"
    135 = "MS-RPC"
    139 = "NetBIOS"
    143 = "IMAP"
    443 = "HTTPS"
    445 = "SMB"
    993 = "IMAPS"
    995 = "POP3S"
    1433 = "MSSQL"
    1521 = "Oracle"
    3306 = "MySQL"
    3389 = "RDP"
    5432 = "PostgreSQL"
    5900 = "VNC"
    5985 = "WinRM-HTTP"
    5986 = "WinRM-HTTPS"
    8080 = "HTTP-Proxy"
    8443 = "HTTPS-Alt"
    9090 = "Zeus Admin"
    27017 = "MongoDB"
}

$VulnerablePorts = @{
    21 = "FTP - Often unencrypted credentials"
    23 = "Telnet - Unencrypted communication"
    135 = "MS-RPC - Vulnerable to attacks"
    139 = "NetBIOS - Information disclosure"
    445 = "SMB - Target for ransomware"
    1433 = "MSSQL - Database exposure"
    3306 = "MySQL - Database exposure"
    3389 = "RDP - Brute force target"
    5900 = "VNC - Often weak authentication"
}
#endregion

#region Functions
function Get-PortRange {
    param([string]$Range)
    
    $ports = @()
    
    switch ($ScanType) {
        "Quick" {
            # Top 20 most common ports
            $ports = @(21, 22, 23, 25, 53, 80, 110, 135, 139, 143, 443, 445, 
                      1433, 3306, 3389, 5900, 8080, 8443)
        }
        "Full" {
            # All ports 1-65535
            $ports = 1..65535
        }
        "Custom" {
            # Parse custom range
            if ($Range -match "^\d+-\d+$") {
                $start, $end = $Range -split '-'
                $ports = [int]$start..[int]$end
            } else {
                $ports = $Range -split ',' | ForEach-Object { [int]$_ }
            }
        }
        "Stealth" {
            # Common service ports for stealth scan
            $ports = @(22, 80, 443, 3389, 8080)
        }
    }
    
    return $ports
}

function Test-Port {
    param(
        [string]$IPAddress,
        [int]$Port,
        [int]$Timeout
    )
    
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $asyncResult = $tcpClient.BeginConnect($IPAddress, $Port, $null, $null)
    $wait = $asyncResult.AsyncWaitHandle.WaitOne($Timeout, $false)
    
    if ($wait) {
        try {
            $tcpClient.EndConnect($asyncResult)
            $tcpClient.Close()
            return $true
        } catch {
            return $false
        }
    } else {
        $tcpClient.Close()
        return $false
    }
}

function Get-ServiceBanner {
    param(
        [string]$IPAddress,
        [int]$Port
    )
    
    $banner = ""
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($IPAddress, $Port)
        
        $stream = $tcpClient.GetStream()
        $buffer = New-Object byte[] 1024
        $stream.ReadTimeout = 1000
        
        $read = $stream.Read($buffer, 0, 1024)
        if ($read -gt 0) {
            $banner = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
            $banner = $banner -replace "`r`n", " " -replace "`n", " "
            if ($banner.Length -gt 50) {
                $banner = $banner.Substring(0, 50) + "..."
            }
        }
        
        $tcpClient.Close()
    } catch {
        # No banner available
    }
    
    return $banner
}

function Scan-Host {
    param(
        [string]$HostIP,
        [array]$Ports
    )
    
    Write-Host "   🔍 Scanning $HostIP..." -ForegroundColor Cyan
    
    $openPorts = @()
    $progress = 0
    
    foreach ($port in $Ports) {
        $progress++
        
        if ($progress % 10 -eq 0) {
            Write-Progress -Activity "Port Scanning $HostIP" `
                          -Status "Checking port $port" `
                          -PercentComplete (($progress / $Ports.Count) * 100)
        }
        
        if (Test-Port -IPAddress $HostIP -Port $port -Timeout $Timeout) {
            $serviceName = if ($CommonPorts.ContainsKey($port)) { 
                $CommonPorts[$port] 
            } else { 
                "Unknown" 
            }
            
            $banner = if ($ResolveServices) {
                Get-ServiceBanner -IPAddress $HostIP -Port $port
            } else {
                ""
            }
            
            $vulnerability = if ($VulnerablePorts.ContainsKey($port)) {
                $VulnerablePorts[$port]
            } else {
                ""
            }
            
            $portInfo = [PSCustomObject]@{
                Host = $HostIP
                Port = $port
                State = "Open"
                Service = $serviceName
                Banner = $banner
                Vulnerability = $vulnerability
                Timestamp = Get-Date
            }
            
            $openPorts += $portInfo
            
            $color = if ($vulnerability) { "Yellow" } else { "Green" }
            Write-Host "      ✅ Port $port ($serviceName) - OPEN" -ForegroundColor $color
        }
    }
    
    Write-Progress -Activity "Port Scanning $HostIP" -Completed
    
    return $openPorts
}

function Get-HostsFromRange {
    param([string]$Range)
    
    $hosts = @()
    
    if ($Range -match "^\d+\.\d+\.\d+\.\d+$") {
        # Single IP
        $hosts += $Range
    } elseif ($Range -match "^(\d+\.\d+\.\d+)\.(\d+)-(\d+)$") {
        # Range like 192.168.1.1-10
        $base = $matches[1]
        $start = [int]$matches[2]
        $end = [int]$matches[3]
        
        for ($i = $start; $i -le $end; $i++) {
            $hosts += "$base.$i"
        }
    } elseif ($Range -match "^(\d+\.\d+\.\d+\.\d+)/(\d+)$") {
        # CIDR notation
        Write-Host "   ℹ️ CIDR scanning not fully implemented, scanning /24 subnet" -ForegroundColor Yellow
        $base = ($matches[1] -split '\.')[0..2] -join '.'
        
        for ($i = 1; $i -le 254; $i++) {
            $hosts += "$base.$i"
        }
    } else {
        # Try to resolve hostname
        try {
            $ip = [System.Net.Dns]::GetHostAddresses($Range) | 
                  Where-Object { $_.AddressFamily -eq 'InterNetwork' } |
                  Select-Object -First 1
            
            if ($ip) {
                $hosts += $ip.ToString()
            }
        } catch {
            Write-Host "   ❌ Cannot resolve host: $Range" -ForegroundColor Red
        }
    }
    
    return $hosts
}

function New-PortScanReport {
    param(
        [array]$ScanResults
    )
    
    Write-Host ""
    Write-Host "📝 Generating scan report..." -ForegroundColor Yellow
    
    $totalHosts = ($ScanResults | Select-Object -Unique Host).Count
    $totalOpenPorts = $ScanResults.Count
    $vulnerablePorts = ($ScanResults | Where-Object { $_.Vulnerability }).Count
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Port Scan Report</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #232526 0%, #414345 100%);
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
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            text-align: center;
        }
        h1 {
            color: #2c3e50;
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .stats {
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
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        .stat-value {
            font-size: 2.5em;
            font-weight: bold;
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
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
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
            background: #2c3e50;
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
        .port-open {
            background: #d4edda;
            color: #155724;
            padding: 3px 8px;
            border-radius: 3px;
            font-weight: bold;
        }
        .vulnerable {
            background: #fff3cd;
            color: #856404;
        }
        .service-banner {
            font-family: monospace;
            font-size: 0.85em;
            color: #6c757d;
        }
        .vulnerability-warning {
            background: #fff3cd;
            border: 1px solid #ffc107;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .host-group {
            margin-bottom: 40px;
        }
        .host-header {
            background: #3498db;
            color: white;
            padding: 10px 15px;
            border-radius: 5px 5px 0 0;
            font-weight: bold;
        }
        .port-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));
            gap: 10px;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 5px;
            margin: 20px 0;
        }
        .port-badge {
            background: #27ae60;
            color: white;
            padding: 8px;
            border-radius: 5px;
            text-align: center;
            font-weight: bold;
        }
        .port-badge.vulnerable {
            background: #e74c3c;
        }
        .footer {
            background: white;
            border-radius: 15px;
            padding: 25px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
            color: #7f8c8d;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Network Port Scan Report</h1>
            <p><strong>Target:</strong> $Target</p>
            <p><strong>Scan Type:</strong> $ScanType</p>
            <p><strong>Port Range:</strong> $PortRange</p>
            <p><strong>Scan Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
            <p><strong>Performed by:</strong> Aykut Yıldız</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value">$totalHosts</div>
                <div class="stat-label">Hosts Scanned</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$totalOpenPorts</div>
                <div class="stat-label">Open Ports</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$vulnerablePorts</div>
                <div class="stat-label">Vulnerable Ports</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$($Ports.Count)</div>
                <div class="stat-label">Ports Checked</div>
            </div>
        </div>
"@

    if ($vulnerablePorts -gt 0) {
        $htmlReport += @"
        <div class="vulnerability-warning">
            <h3>⚠️ Security Warnings</h3>
            <p>Found $vulnerablePorts potentially vulnerable open ports that may pose security risks.</p>
            <p>Review the detailed results below and consider implementing additional security measures.</p>
        </div>
"@
    }

    # Group results by host
    $hostGroups = $ScanResults | Group-Object Host
    
    foreach ($hostGroup in $hostGroups) {
        $htmlReport += @"
        <div class="section">
            <h2>🖥️ Host: $($hostGroup.Name)</h2>
            <p><strong>Open Ports:</strong> $($hostGroup.Count)</p>
            
            <div class="port-grid">
"@
        
        foreach ($port in $hostGroup.Group | Sort-Object Port) {
            $badgeClass = if ($port.Vulnerability) { "vulnerable" } else { "" }
            $htmlReport += @"
                <div class="port-badge $badgeClass" title="$($port.Service)">
                    $($port.Port)
                </div>
"@
        }
        
        $htmlReport += @"
            </div>
            
            <table>
                <thead>
                    <tr>
                        <th>Port</th>
                        <th>State</th>
                        <th>Service</th>
                        <th>Banner</th>
                        <th>Security Notes</th>
                    </tr>
                </thead>
                <tbody>
"@
        
        foreach ($port in $hostGroup.Group | Sort-Object Port) {
            $rowClass = if ($port.Vulnerability) { 'class="vulnerable"' } else { '' }
            
            $htmlReport += @"
                    <tr $rowClass>
                        <td><strong>$($port.Port)</strong></td>
                        <td><span class="port-open">$($port.State)</span></td>
                        <td>$($port.Service)</td>
                        <td class="service-banner">$($port.Banner)</td>
                        <td>$($port.Vulnerability)</td>
                    </tr>
"@
        }
        
        $htmlReport += @"
                </tbody>
            </table>
        </div>
"@
    }

    # Summary and recommendations
    $htmlReport += @"
        <div class="section">
            <h2>📊 Scan Summary</h2>
            <h3>Most Common Open Services:</h3>
            <ul>
"@

    $serviceSummary = $ScanResults | Group-Object Service | Sort-Object Count -Descending | Select-Object -First 10
    foreach ($service in $serviceSummary) {
        $htmlReport += @"
                <li><strong>$($service.Name):</strong> $($service.Count) instances</li>
"@
    }

    $htmlReport += @"
            </ul>
            
            <h3>Security Recommendations:</h3>
            <ol>
                <li>Close unnecessary open ports to reduce attack surface</li>
                <li>Implement firewall rules to restrict access to sensitive services</li>
                <li>Update services with known vulnerabilities</li>
                <li>Enable encryption for services transmitting sensitive data</li>
                <li>Regularly audit and monitor open ports</li>
            </ol>
        </div>
        
        <div class="footer">
            <p><strong>Network Port Scanner v1.8</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "PortScan_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    return $reportFile
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║         Network Port Scanner Tool v1.8                     ║
║         PowerShell Automation by Aykut Yıldız             ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Create report directory
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

Write-Host ""
Write-Host "🎯 Target: $Target" -ForegroundColor Yellow
Write-Host "🔍 Scan Type: $ScanType" -ForegroundColor Yellow
Write-Host "🔢 Port Range: $PortRange" -ForegroundColor Yellow
Write-Host ""

# Get ports to scan
$Ports = Get-PortRange -Range $PortRange
Write-Host "📊 Ports to scan: $($Ports.Count)" -ForegroundColor Cyan

# Get hosts to scan
$Hosts = Get-HostsFromRange -Range $Target
Write-Host "🖥️ Hosts to scan: $($Hosts.Count)" -ForegroundColor Cyan
Write-Host ""

# Scan each host
$allResults = @()
$startTime = Get-Date

foreach ($hostIP in $Hosts) {
    # Quick ping test first
    if (Test-Connection -ComputerName $hostIP -Count 1 -Quiet) {
        $results = Scan-Host -HostIP $hostIP -Ports $Ports
        $allResults += $results
        
        if ($results.Count -gt 0) {
            Write-Host "   ✅ Found $($results.Count) open ports on $hostIP" -ForegroundColor Green
        } else {
            Write-Host "   ❌ No open ports found on $hostIP" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ⚠️ Host $hostIP is not responding to ping" -ForegroundColor Gray
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

# Generate report
if ($allResults.Count -gt 0) {
    $reportFile = New-PortScanReport -ScanResults $allResults
    
    # Export to CSV
    $csvFile = Join-Path $ReportPath "PortScan_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $allResults | Export-Csv -Path $csvFile -NoTypeInformation
    
    # Export to JSON for automation
    $jsonFile = Join-Path $ReportPath "PortScan_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $allResults | ConvertTo-Json -Depth 3 | Out-File -FilePath $jsonFile -Encoding UTF8
}

Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "         PORT SCAN COMPLETE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Scan Summary:" -ForegroundColor Yellow
Write-Host "   • Hosts Scanned: $($Hosts.Count)" -ForegroundColor Gray
Write-Host "   • Open Ports Found: $($allResults.Count)" -ForegroundColor Gray
Write-Host "   • Scan Duration: $($duration.TotalSeconds) seconds" -ForegroundColor Gray

if ($allResults.Count -gt 0) {
    $vulnerableCount = ($allResults | Where-Object { $_.Vulnerability }).Count
    if ($vulnerableCount -gt 0) {
        Write-Host "   ⚠️ Vulnerable Ports: $vulnerableCount" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "📁 Reports saved:" -ForegroundColor Green
    Write-Host "   • $reportFile" -ForegroundColor Gray
    Write-Host "   • $csvFile" -ForegroundColor Gray
    Write-Host "   • $jsonFile" -ForegroundColor Gray
    
    # Open report
    Start-Process $reportFile
} else {
    Write-Host ""
    Write-Host "❌ No open ports were found in the scan" -ForegroundColor Yellow
}
#endregion
