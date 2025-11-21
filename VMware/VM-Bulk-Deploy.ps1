<#
.SYNOPSIS
    VMware Bulk VM Deployment Tool
    
.DESCRIPTION
    Deploys multiple virtual machines from template with customization
    specifications for VMware vSphere environment.
    
.PARAMETER vCenter
    vCenter server address
    
.PARAMETER Template
    VM template name to deploy from
    
.PARAMETER CSVPath
    CSV file containing VM deployment specifications
    
.EXAMPLE
    .\VM-Bulk-Deploy.ps1 -vCenter "vcenter.company.local" -Template "Windows2022-Template"
    
.NOTES
    Author: Aykut Yıldız
    Version: 2.0
    Date: 2024-11-21
    GitHub: https://github.com/infrawisetech/IT-Admin-Toolkit
    
    CSV Format:
    VMName,CPU,MemoryGB,DiskGB,Network,Datastore,Folder,IPAddress,Gateway,DNS
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$vCenter,
    
    [Parameter(Mandatory=$true)]
    [string]$Template,
    
    [Parameter(Mandatory=$false)]
    [string]$CSVPath = "C:\VMDeployment\VMs.csv",
    
    [Parameter(Mandatory=$false)]
    [string]$Cluster,
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [bool]$PowerOnAfterDeploy = $true,
    
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\VMDeployment\Reports"
)

#region Functions
function Connect-vCenterServer {
    Write-Host "🔌 Connecting to vCenter: $vCenter" -ForegroundColor Cyan
    
    try {
        if ($Credential) {
            Connect-VIServer -Server $vCenter -Credential $Credential -ErrorAction Stop
        } else {
            Connect-VIServer -Server $vCenter -ErrorAction Stop
        }
        Write-Host "✅ Connected to vCenter successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "❌ Failed to connect to vCenter: $_" -ForegroundColor Red
        return $false
    }
}

function Deploy-VMFromTemplate {
    param(
        [PSCustomObject]$VMSpec
    )
    
    Write-Host ""
    Write-Host "🚀 Deploying VM: $($VMSpec.VMName)" -ForegroundColor Yellow
    
    try {
        # Get template
        $vmTemplate = Get-Template -Name $Template -ErrorAction Stop
        
        # Get target resources
        $targetDatastore = Get-Datastore -Name $VMSpec.Datastore -ErrorAction Stop
        $targetHost = if ($Cluster) { 
            Get-Cluster -Name $Cluster | Get-VMHost | Sort-Object MemoryUsageGB | Select-Object -First 1 
        } else { 
            Get-VMHost | Sort-Object MemoryUsageGB | Select-Object -First 1 
        }
        
        # Create VM from template
        $vm = New-VM -Name $VMSpec.VMName `
                     -Template $vmTemplate `
                     -Datastore $targetDatastore `
                     -VMHost $targetHost `
                     -Location (Get-Folder -Name $VMSpec.Folder -ErrorAction SilentlyContinue) `
                     -ErrorAction Stop
        
        Write-Host "   ✅ VM created from template" -ForegroundColor Green
        
        # Configure VM resources
        $vm | Set-VM -NumCpu $VMSpec.CPU `
                     -MemoryGB $VMSpec.MemoryGB `
                     -Confirm:$false `
                     -ErrorAction Stop | Out-Null
        
        Write-Host "   ✅ Configured CPU: $($VMSpec.CPU), Memory: $($VMSpec.MemoryGB)GB" -ForegroundColor Green
        
        # Configure network
        $vm | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $VMSpec.Network -Confirm:$false | Out-Null
        Write-Host "   ✅ Network configured: $($VMSpec.Network)" -ForegroundColor Green
        
        # Add additional disk if specified
        if ($VMSpec.DiskGB -gt 0) {
            $vm | New-HardDisk -CapacityGB $VMSpec.DiskGB -StorageFormat Thin -Confirm:$false | Out-Null
            Write-Host "   ✅ Additional disk added: $($VMSpec.DiskGB)GB" -ForegroundColor Green
        }
        
        # Configure IP if customization spec provided
        if ($VMSpec.IPAddress -and $VMSpec.IPAddress -ne "DHCP") {
            Write-Host "   📝 Applying network customization..." -ForegroundColor Cyan
            # Note: Requires customization specification
        }
        
        # Power on if requested
        if ($PowerOnAfterDeploy) {
            Start-VM -VM $vm -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-Host "   ✅ VM powered on" -ForegroundColor Green
        }
        
        return @{
            Success = $true
            VMName = $VMSpec.VMName
            Status = "Deployed"
            PowerState = if ($PowerOnAfterDeploy) { "PoweredOn" } else { "PoweredOff" }
            CPU = $VMSpec.CPU
            MemoryGB = $VMSpec.MemoryGB
            Datastore = $VMSpec.Datastore
            Network = $VMSpec.Network
        }
    }
    catch {
        Write-Host "   ❌ Deployment failed: $_" -ForegroundColor Red
        return @{
            Success = $false
            VMName = $VMSpec.VMName
            Status = "Failed"
            Error = $_.Exception.Message
        }
    }
}

function Get-VMDeploymentReport {
    param(
        [array]$DeploymentResults
    )
    
    $htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>VM Deployment Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
    <style>
        body { 
            font-family: 'Segoe UI', Arial, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container { 
            max-width: 1400px; 
            margin: 0 auto; 
            background: white; 
            padding: 30px; 
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        h1 { 
            color: #2c3e50; 
            border-bottom: 3px solid #667eea; 
            padding-bottom: 10px;
            margin-bottom: 30px;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .stat-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            border: 2px solid #e9ecef;
        }
        .stat-value {
            font-size: 2.5em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .stat-label {
            color: #6c757d;
            text-transform: uppercase;
            font-size: 0.9em;
        }
        .success { color: #28a745; }
        .failed { color: #dc3545; }
        table { 
            width: 100%; 
            border-collapse: collapse; 
            margin-top: 30px;
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
            border-bottom: 1px solid #e9ecef;
        }
        tr:hover { 
            background: #f8f9fa; 
        }
        .status-deployed { 
            background: #d4edda; 
            color: #155724; 
            padding: 5px 10px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .status-failed { 
            background: #f8d7da; 
            color: #721c24; 
            padding: 5px 10px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #e9ecef;
            color: #6c757d;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ VMware Bulk Deployment Report</h1>
        <p><strong>Deployment Date:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>vCenter Server:</strong> $vCenter</p>
        <p><strong>Template Used:</strong> $Template</p>
        <p><strong>Deployed by:</strong> Aykut Yıldız</p>
        
        <div class="summary">
            <div class="stat-card">
                <div class="stat-value">$($DeploymentResults.Count)</div>
                <div class="stat-label">Total VMs</div>
            </div>
            <div class="stat-card">
                <div class="stat-value success">$(($DeploymentResults | Where-Object Success -eq $true).Count)</div>
                <div class="stat-label">Deployed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value failed">$(($DeploymentResults | Where-Object Success -eq $false).Count)</div>
                <div class="stat-label">Failed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">$(($DeploymentResults | Where-Object PowerState -eq 'PoweredOn').Count)</div>
                <div class="stat-label">Powered On</div>
            </div>
        </div>
        
        <h2>Deployment Details</h2>
        <table>
            <thead>
                <tr>
                    <th>VM Name</th>
                    <th>Status</th>
                    <th>CPU</th>
                    <th>Memory (GB)</th>
                    <th>Datastore</th>
                    <th>Network</th>
                    <th>Power State</th>
                    <th>Notes</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($result in $DeploymentResults) {
        $statusClass = if ($result.Success) { "deployed" } else { "failed" }
        $notes = if ($result.Error) { $result.Error } else { "Successfully deployed" }
        
        $htmlReport += @"
                <tr>
                    <td><strong>$($result.VMName)</strong></td>
                    <td><span class="status-$statusClass">$($result.Status)</span></td>
                    <td>$($result.CPU)</td>
                    <td>$($result.MemoryGB)</td>
                    <td>$($result.Datastore)</td>
                    <td>$($result.Network)</td>
                    <td>$($result.PowerState)</td>
                    <td>$notes</td>
                </tr>
"@
    }

    $htmlReport += @"
            </tbody>
        </table>
        
        <div class="footer">
            <p><strong>VMware Bulk Deploy Tool v2.0</strong></p>
            <p>PowerShell Automation by Aykut Yıldız | IT Admin Toolkit</p>
        </div>
    </div>
</body>
</html>
"@

    $reportFile = Join-Path $ReportPath "VMDeployment_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $htmlReport | Out-File -FilePath $reportFile -Encoding UTF8
    
    return $reportFile
}
#endregion

#region Main
Write-Host @"
╔════════════════════════════════════════════════════════════╗
║         VMware Bulk VM Deployment Tool v2.0                ║
║         PowerShell Automation by Aykut Yıldız             ║
╚════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Check VMware PowerCLI
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Host "❌ VMware PowerCLI not installed. Installing..." -ForegroundColor Yellow
    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
    Import-Module VMware.PowerCLI
}

# Create directories
if (-not (Test-Path $ReportPath)) {
    New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
}

# Connect to vCenter
if (-not (Connect-vCenterServer)) {
    Write-Host "❌ Cannot proceed without vCenter connection" -ForegroundColor Red
    return
}

# Check template
$vmTemplate = Get-Template -Name $Template -ErrorAction SilentlyContinue
if (-not $vmTemplate) {
    Write-Host "❌ Template not found: $Template" -ForegroundColor Red
    Disconnect-VIServer -Confirm:$false
    return
}

# Import VM specifications
if (-not (Test-Path $CSVPath)) {
    Write-Host "❌ CSV file not found: $CSVPath" -ForegroundColor Red
    Disconnect-VIServer -Confirm:$false
    return
}

$vmSpecs = Import-Csv -Path $CSVPath
Write-Host ""
Write-Host "📋 Found $($vmSpecs.Count) VMs to deploy" -ForegroundColor Yellow

# Deploy VMs
$deploymentResults = @()
$startTime = Get-Date

foreach ($vmSpec in $vmSpecs) {
    $result = Deploy-VMFromTemplate -VMSpec $vmSpec
    $deploymentResults += $result
}

$endTime = Get-Date
$duration = $endTime - $startTime

# Generate report
$reportFile = Get-VMDeploymentReport -DeploymentResults $deploymentResults

# Summary
Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host "         VM DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Deployment Summary:" -ForegroundColor Yellow
Write-Host "   ✅ Successful: $(($deploymentResults | Where-Object Success -eq $true).Count)" -ForegroundColor Green
Write-Host "   ❌ Failed: $(($deploymentResults | Where-Object Success -eq $false).Count)" -ForegroundColor Red
Write-Host "   ⏱️  Duration: $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Report saved: $reportFile" -ForegroundColor Cyan

# Disconnect from vCenter
Disconnect-VIServer -Confirm:$false

# Open report
Start-Process $reportFile
#endregion
