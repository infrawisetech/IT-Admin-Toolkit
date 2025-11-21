<#
.SYNOPSIS
    Network Connectivity Diagnostic Tool
    
.DESCRIPTION
    Comprehensive network connectivity testing tool that performs ping tests,
    port scanning, DNS resolution checks, traceroute analysis, and bandwidth testing.
    Perfect for diagnosing client connection drops and network issues.
    
.PARAMETER TargetHosts
    Array of hosts to test connectivity
    
.PARAMETER Ports
    Array of ports to test
    
.PARAMETER ContinuousMode
    Run tests continuously to catch intermittent issues
    
.PARAMETER IntervalSeconds
    Interval between tests in continuous mode
    
.EXAMPLE
    .\Network-Connectivity-Test.ps1 -TargetHosts "google.com","8.8.8.8" -Ports 80,443,3389
    
.EXAMPLE
    .\Network-Connectivity-Test.ps1 -ContinuousMode $true -IntervalSeconds 30
    
.NOTES
    Author: Aykut Yıldız
    Version: 2.0
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$TargetHosts = @(
        "8.8.8.8",           # Google DNS
        "1.1.1.1",           # Cloudflare DNS
        "google.com",        # Internet connectivity
        "microsoft.com",     # Microsoft services
        "github.com"         # GitHub
    ),
    
    [Parameter(Mandatory=$false)]
    [int[]]$Ports = @(
        80,    # HTTP
        443,   # HTTPS
        3389,  # RDP
        445,   # SMB
        135,   # RPC
        53,    # DNS
        21,    # FTP
        22,    # SSH
        25,    # SMTP
        1433   # SQL Server
    ),
    
    [Parameter(Mandatory=$false)]
    [bool]$ContinuousMode = $false,
    
    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 60,
    
    [Parameter(Mandatory=$false)]
    [int]$PacketCount = 4,
    
    [Parameter(Mandatory=$false)]
    [bool]$DetailedReport = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\NetworkReports",
    
    [Parameter(Mandatory=$false)]
    [bool]$TestBandwidth = $false
)

#region Functions
function Write-NetworkLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Level) {
        "Error" { 
            Write-Host "[$timestamp] ❌ $Message" -ForegroundColor Red
            $script:errorCount++
        }
        "Warning" { 
            Write-Host "[$timestamp] ⚠️  $Message" -ForegroundColor Yellow
            $script:warningCount++
        }
        "Success" { 
            Write-Host "[$timestamp] ✅ $Message" -ForegroundColor Green
            $script:successCount++
        }
        default { 
            Write-Host "[$timestamp] ℹ️  $Message" -ForegroundColor Cyan
        }
    }
    
    # Ensure report path exists
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }
    
    # Log to file
    $logFile = Join-Path $ReportPath "NetworkTest_$(Get-Date -Format 'yyyy-MM-dd').log"
    "[$timestamp] [$Level] $Message" | Add-Content -Path $logFile
}

function Test-Ping {
    param(
        [string]$HostName,
        [int]$Count = 4
    )
    
    Write-NetworkLog "Testing ping to $HostName..." "Info"
    
    try {
        $pingResult = Test-Connection -ComputerName $HostName -Count $Count -ErrorAction Stop
        
        $avgResponseTime = [math]::Round(($pingResult | Measure-Object ResponseTime -Average).Average, 2)
        $packetLoss = [math]::Round((($Count - $pingResult.Count) / $Count) * 100, 2)
        
        $result = [PSCustomObject]@{
            Host = $HostName
            TestType = "Ping"
            Status = if ($packetLoss -eq 0) { "Success" } elseif ($packetLoss -lt 50) { "Warning" } else { "Failed" }
            ResponseTime = "$avgResponseTime ms"
            PacketLoss = "$packetLoss%"
            Details = "Sent: $Count, Received: $($pingResult.Count)"
            Timestamp = Get-Date
        }
        
        if ($packetLoss -eq 0) {
            Write-NetworkLog "Ping to $HostName successful. Avg: $avgResponseTime ms" "Success"
        } elseif ($packetLoss -lt 100) {
            Write-NetworkLog "Ping to $HostName partial. Loss: $packetLoss%" "Warning"
        }
        
        return $result
    }
    catch {
        Write-NetworkLog "Ping to $HostName failed: $_" "Error"
        return [PSCustomObject]@{
            Host = $HostName
            TestType = "Ping"
            Status = "Failed"
            ResponseTime = "N/A"
            PacketLoss = "100%"
            Details = $_.Exception.Message
            Timestamp = Get-Date
        }
    }
}

function Test-Port {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$Timeout = 1000
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($HostName, $Port, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        
        if ($waitHandle.WaitOne($Timeout, $false)) {
            if ($tcpClient.Connected) {
                $tcpClient.Close()
                Write-NetworkLog "Port $Port on $HostName is OPEN" "Success"
                return @{
                    Status = "Open"
                    ResponseTime = $Timeout
                }
            }
        }
        
        $tcpClient.Close()
        return @{
            Status = "Closed"
            ResponseTime = $Timeout
        }
    }
    catch {
        return @{
            Status = "Filtered"
            ResponseTime = $Timeout
        }
    }
}

function Test-DNSResolution {
    param(
        [string]$HostName
    )
    
    Write-NetworkLog "Testing DNS resolution for $HostName..." "Info"
    
    try {
        $startTime = Get-Date
        $dnsResult = Resolve-DnsName -Name $HostName -ErrorAction Stop
        $resolutionTime = ((Get-Date) - $startTime).TotalMilliseconds
        
        $ipAddresses = ($dnsResult | Where-Object { $_.Type -eq "A" } | Select-Object -ExpandProperty IPAddress) -join ", "
        
        Write-NetworkLog "DNS resolution successful: $HostName -> $ipAddresses" "Success"
        
        return [PSCustomObject]@{
            Host = $HostName
            TestType = "DNS"
            Status = "Success"
            IPAddresses = $ipAddresses
            ResolutionTime = "$([math]::Round($resolutionTime, 2)) ms"
            DNSServer = $dnsResult[0].NameHost
            Timestamp = Get-Date
        }
    }
    catch {
        Write-NetworkLog "DNS resolution failed for $HostName: $_" "Error"
        
        return [PSCustomObject]@{
            Host = $HostName
            TestType = "DNS"
            Status = "Failed"
            IPAddresses = "N/A"
            ResolutionTime = "N/A"
            DNSServer = "N/A"
            Timestamp = Get-Date
        }
    }
}

function Test-Traceroute {
    param(
        [string]$HostName,
        [int]$MaxHops = 30
    )
    
    Write-NetworkLog "Running traceroute to $HostName..." "Info"
    
    try {
        $trace = tracert -h $MaxHops -w 1000 $HostName 2>&1
        
        $hops = @()
        $hopCount = 0
        
        foreach ($line in $trace) {
            if ($line -match "^\s*(\d+)\s+(.+)$") {
                $hopCount++
                $hops += $line.Trim()
            }
        }
        
        return [PSCustomObject]@{
            Host = $HostName
            TestType = "Traceroute"
            Status = "Complete"
            TotalHops = $hopCount
            Route = $hops -join " -> "
            Timestamp = Get-Date
        }
    }
    catch {
        Write-NetworkLog "Traceroute to $HostName failed: $_" "Error"
        return $null
    }
}

function Test-NetworkAdapter {
    Write-NetworkLog "Checking network adapter status..." "Info"
    
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    $adapterInfo = @()
    
    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPConfiguration -InterfaceIndex $adapter.ifIndex
        
        $info = [PSCustomObject]@{
            Name = $adapter.Name
            Description = $adapter.InterfaceDescription
            Status = $adapter.Status
            Speed = "$([math]::Round($adapter.LinkSpeed / 1000000, 0)) Mbps"
            IPAddress = ($ipConfig.IPv4Address.IPAddress) -join ", "
            Gateway = $ipConfig.IPv4DefaultGateway.NextHop
            DNSServers = ($ipConfig.DNSServer.ServerAddresses) -join ", "
            MACAddress = $adapter.MacAddress
        }
        
        $adapterInfo += $info
        Write-NetworkLog "Adapter: $($adapter.Name) - Status: $($adapter.Status) - Speed: $($info.Speed)" "Success"
    }
    
    return $adapterInfo
}

function Get-NetworkStatistics {
    $stats = Get-NetAdapterStatistics
    
    $totalSent = [math]::Round(($stats | Measure-Object -Property SentBytes -Sum).Sum / 1GB, 2)
    $totalReceived = [math]::Round(($stats | Measure-Object -Property ReceivedBytes -Sum).Sum / 1GB, 2)
    
    return [PSCustomObject]@{
        TotalSentGB = $totalSent
        TotalReceivedGB = $totalReceived
        TotalPacketsSent = ($stats | Measure-Object -Property SentUnicastPackets -Sum).Sum
        TotalPacketsReceived = ($stats | Measure-Object -Property ReceivedUnicastPackets -Sum).Sum
        Errors = ($stats | Measure-Object -Property ReceivedDiscardedPackets -Sum).Sum
    }
}

function New-NetworkReport {
    param(
        [array]$TestResults,
        [array]$AdapterInfo,
        [object]$Statistics
    )
    
    Write-NetworkLog "Generating comprehensive network report..." "Info"
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Connectivity Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
    <meta charset="UTF-8">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
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
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .header h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 2.5em;
        }
        
        .header .subtitle {
            color: #666;
            font-size: 1.1em;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
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
        
        .card h3 {
            color: #333;
            margin-bottom: 20px;
            padding-bottom: 10px;
            border-bottom: 2px solid #f0f0f0;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            margin-bottom: 10px;
            padding: 10px;
            background: #f8f9fa;
            border-radius: 5px;
        }
        
        .metric-label {
            color: #666;
            font-weight: 500;
        }
        
        .metric-value {
            font-weight: bold;
            color: #333;
        }
        
        .status-success { color: #28a745; }
        .status-warning { color: #ffc107; }
        .status-failed { color: #dc3545; }
        
        .test-results {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        
        th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 15px;
            text-align: left;
            font-weight: 500;
        }
        
        td {
            padding: 12px 15px;
            border-bottom: 1px solid #f0f0f0;
        }
        
        tr:hover {
            background: #f8f9fa;
        }
        
        .badge {
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
            display: inline-block;
        }
        
        .badge-success { background: #d4edda; color: #155724; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        
        .adapter-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .adapter-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            border: 2px solid #e9ecef;
        }
        
        .adapter-card h4 {
            color: #495057;
            margin-bottom: 15px;
            font-size: 1.2em;
        }
        
        .adapter-detail {
            display: flex;
            justify-content: space-between;
            margin-bottom: 8px;
            font-size: 0.9em;
        }
        
        .chart-container {
            background: white;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #e9ecef;
            border-radius: 15px;
            overflow: hidden;
            margin: 10px 0;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #28a745, #20c997);
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            transition: width 0.5s ease;
        }
        
        .footer {
            background: white;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            color: #666;
            box-shadow: 0 5px 20px rgba(0,0,0,0.1);
        }
        
        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.05); }
            100% { transform: scale(1); }
        }
        
        .pulse {
            animation: pulse 2s infinite;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌐 Network Connectivity Diagnostic Report</h1>
            <div class="subtitle">Generated by Aykut Yıldız | $(Get-Date -Format 'dddd, MMMM dd, yyyy HH:mm:ss')</div>
        </div>
        
        <div class="grid">
            <div class="card">
                <h3>📊 Test Summary</h3>
                <div class="metric">
                    <span class="metric-label">Total Tests:</span>
                    <span class="metric-value">$($TestResults.Count)</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Successful:</span>
                    <span class="metric-value status-success">$($script:successCount)</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Warnings:</span>
                    <span class="metric-value status-warning">$($script:warningCount)</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Failed:</span>
                    <span class="metric-value status-failed">$($script:errorCount)</span>
                </div>
            </div>
            
            <div class="card">
                <h3>📈 Network Statistics</h3>
                <div class="metric">
                    <span class="metric-label">Data Sent:</span>
                    <span class="metric-value">$($Statistics.TotalSentGB) GB</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Data Received:</span>
                    <span class="metric-value">$($Statistics.TotalReceivedGB) GB</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Packet Errors:</span>
                    <span class="metric-value">$($Statistics.Errors)</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Active Adapters:</span>
                    <span class="metric-value">$($AdapterInfo.Count)</span>
                </div>
            </div>
            
            <div class="card">
                <h3>⚡ Connection Quality</h3>
                <div class="metric">
                    <span class="metric-label">Overall Health:</span>
                    <span class="metric-value">
"@

    # Calculate health percentage
    $healthPercentage = [math]::Round((($script:successCount / ($script:successCount + $script:errorCount + $script:warningCount)) * 100), 2)
    
    $htmlReport += @"
                        $healthPercentage%
                    </span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" style="width: $healthPercentage%;">
                        $healthPercentage% Healthy
                    </div>
                </div>
            </div>
        </div>
        
        <div class="test-results">
            <h3>🔍 Connectivity Test Results</h3>
            <table>
                <thead>
                    <tr>
                        <th>Host</th>
                        <th>Test Type</th>
                        <th>Status</th>
                        <th>Response</th>
                        <th>Details</th>
                        <th>Timestamp</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($result in $TestResults | Sort-Object Timestamp -Descending | Select-Object -First 100) {
        $badgeClass = switch($result.Status) {
            "Success" { "badge-success" }
            "Warning" { "badge-warning" }
            default { "badge-danger" }
        }
        
        $responseValue = if ($result.ResponseTime) { $result.ResponseTime } 
                        elseif ($result.ResolutionTime) { $result.ResolutionTime }
                        elseif ($result.PacketLoss) { "Loss: $($result.PacketLoss)" }
                        else { "N/A" }
        
        $details = if ($result.Details) { $result.Details }
                  elseif ($result.IPAddresses) { $result.IPAddresses }
                  elseif ($result.TotalHops) { "$($result.TotalHops) hops" }
                  else { "-" }
        
        $htmlReport += @"
                    <tr>
                        <td><strong>$($result.Host)</strong></td>
                        <td>$($result.TestType)</td>
                        <td><span class="badge $badgeClass">$($result.Status)</span></td>
                        <td>$responseValue</td>
                        <td>$details</td>
                        <td>$($result.Timestamp.ToString('HH:mm:ss'))</td>
                    </tr>
"@
    }

    $htmlReport += @"
                </tbody>
            </table>
        </div>
        
        <div class="test-results">
            <h3>🖥️ Network Adapters</h3>
            <div class="adapter-grid">
"@

    foreach ($adapter in $AdapterInfo) {
        $htmlReport += @"
                <div class="adapter-card">
                    <h4>$($adapter.Name)</h4>
                    <div class="adapter-detail">
                        <span>Status:</span>
                        <strong class="status-success">$($adapter.Status)</strong>
                    </div>
                    <div class="adapter-detail">
                        <span>Speed:</span>
                        <strong>$($adapter.Speed)</strong>
                    </div>
                    <div class="adapter-detail">
                        <span>IP Address:</span>
                        <strong>$($adapter.IPAddress)</strong>
                    </div>
                    <div class="adapter-detail">
                        <span>Gateway:</span>
                        <strong>$($adapter.Gateway)</strong>
                    </div>
                    <div class="adapter-detail">
                        <span>DNS Servers:</span>
                        <strong>$($adapter.DNSServers)</strong>
                    </div>
                    <div class="adapter-detail">
                        <span>MAC Address:</span>
                        <strong>$($adapter.MACAddress)</strong>
                    </div>
                </div>
"@
    }

    $htmlReport += @"
            </div>
        </div>
        
        <div class="footer">
            <p><strong>Network Connectivity Diagnostic Tool v2.0</strong></p>
            <p>PowerShell Network Automation | IT Admin Toolkit</p>
            <p>Report generated in $(((Get-Date) - $script:startTime).TotalSeconds) seconds</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "NetworkReport_$(Get-Date -Format 'yyyy-MM-dd_HHmm').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    Write-NetworkLog "Report saved to: $reportFile" "Success"
    return $reportFile
}
#endregion

#region Main Script
function Main {
    $script:startTime = Get-Date
    $script:successCount = 0
    $script:warningCount = 0
    $script:errorCount = 0
    
    Write-Host @"
╔════════════════════════════════════════════════════════════╗
║       Network Connectivity Diagnostic Tool v2.0            ║
║       PowerShell Automation by Aykut Yıldız               ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    
    $allResults = @()
    
    do {
        Write-Host ""
        Write-Host "🔄 Starting Network Diagnostics..." -ForegroundColor Yellow
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
        
        # Get adapter information
        $adapterInfo = Test-NetworkAdapter
        
        # Ping tests
        Write-Host ""
        Write-Host "📡 PING TESTS" -ForegroundColor Cyan
        Write-Host "─────────────" -ForegroundColor Gray
        
        foreach ($host in $TargetHosts) {
            $result = Test-Ping -HostName $host -Count $PacketCount
            $allResults += $result
        }
        
        # DNS resolution tests
        Write-Host ""
        Write-Host "🌐 DNS RESOLUTION TESTS" -ForegroundColor Cyan
        Write-Host "───────────────────────" -ForegroundColor Gray
        
        foreach ($host in $TargetHosts | Where-Object { $_ -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' }) {
            $result = Test-DNSResolution -HostName $host
            $allResults += $result
        }
        
        # Port scanning
        Write-Host ""
        Write-Host "🔌 PORT SCANNING" -ForegroundColor Cyan
        Write-Host "────────────────" -ForegroundColor Gray
        
        foreach ($host in $TargetHosts[0..1]) {  # Test first 2 hosts only for ports
            foreach ($port in $Ports) {
                Write-Host -NoNewline "Testing $host`:$port... "
                $portResult = Test-Port -HostName $host -Port $port
                
                $allResults += [PSCustomObject]@{
                    Host = $host
                    TestType = "Port $port"
                    Status = $portResult.Status
                    ResponseTime = "$($portResult.ResponseTime) ms"
                    Details = "TCP Port Test"
                    Timestamp = Get-Date
                }
                
                if ($portResult.Status -eq "Open") {
                    Write-Host "OPEN" -ForegroundColor Green
                } else {
                    Write-Host $portResult.Status -ForegroundColor Yellow
                }
            }
        }
        
        # Get network statistics
        $stats = Get-NetworkStatistics
        
        # Generate report if not in continuous mode or if requested
        if ($DetailedReport -and (-not $ContinuousMode -or $allResults.Count -ge 100)) {
            $reportFile = New-NetworkReport -TestResults $allResults -AdapterInfo $adapterInfo -Statistics $stats
            
            if (-not $ContinuousMode) {
                Start-Process $reportFile
            }
        }
        
        # Summary
        Write-Host ""
        Write-Host "════════════════════════════════════════════" -ForegroundColor Green
        Write-Host "         NETWORK DIAGNOSTICS COMPLETE" -ForegroundColor Green
        Write-Host "════════════════════════════════════════════" -ForegroundColor Green
        Write-Host ""
        Write-Host "📊 Results Summary:" -ForegroundColor Yellow
        Write-Host "   ✅ Successful: $script:successCount" -ForegroundColor Green
        Write-Host "   ⚠️  Warnings: $script:warningCount" -ForegroundColor Yellow
        Write-Host "   ❌ Failed: $script:errorCount" -ForegroundColor Red
        
        if ($ContinuousMode) {
            Write-Host ""
            Write-Host "⏳ Waiting $IntervalSeconds seconds for next test cycle..." -ForegroundColor Cyan
            Write-Host "   Press Ctrl+C to stop continuous monitoring" -ForegroundColor Gray
            Start-Sleep -Seconds $IntervalSeconds
        }
        
    } while ($ContinuousMode)
    
    Write-Host ""
    Write-Host "📁 All reports saved to: $ReportPath" -ForegroundColor Cyan
}

# Run the script
Main
#endregion
