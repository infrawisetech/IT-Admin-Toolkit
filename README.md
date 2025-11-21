# 🛠️ IT Admin Toolkit

[![PowerShell](https://img.shields.io/badge/PowerShell-5.0%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/infrawisetech/IT-Admin-Toolkit/graphs/commit-activity)
[![GitHub Stars](https://img.shields.io/github/stars/infrawisetech/IT-Admin-Toolkit.svg)](https://github.com/infrawisetech/IT-Admin-Toolkit/stargazers)

Comprehensive PowerShell toolkit for system administrators featuring 20+ automation scripts for Active Directory, Office 365, VMware, and system monitoring. Developed and tested in enterprise defense industry environment at Sarsilmaz Silah Sanayi.

## 🎯 Features

- **Active Directory Management** - Bulk user operations, automated reporting, group management
- **System Monitoring** - Disk space, service health, network connectivity monitoring  
- **VMware Automation** - VM deployment, snapshot management, resource reporting
- **Security & Compliance** - Security baseline checks, firewall auditing, compliance reporting
- **Backup Verification** - Veeam/Acronis job monitoring and verification

## 📂 Repository Structure

```
IT-Admin-Toolkit/
├── 📁 ActiveDirectory/
│   ├── AD-User-Report.ps1           # Comprehensive user reporting with HTML/CSV export
│   ├── Bulk-User-Creation.ps1       # Create multiple users from CSV
│   ├── Inactive-Users-Cleanup.ps1   # Find and disable inactive accounts
│   └── Group-Management.ps1         # Bulk group operations
├── 📁 SystemMonitoring/
│   ├── Disk-Space-Monitor.ps1       # Monitor and alert on disk usage
│   ├── Service-Health-Check.ps1     # Check critical services status
│   ├── Network-Connectivity.ps1     # Network connectivity testing
│   └── Event-Log-Analyzer.ps1       # Analyze Windows event logs
├
├── 📁 VMware/
│   ├── VM-Bulk-Deploy.ps1           # Deploy multiple VMs from template
│   ├── Snapshot-Manager.ps1         # Manage VM snapshots
│   └── Resource-Report.ps1          # vCenter resource utilization
├── 📁 Security/
│   ├── Firewall-Audit.ps1           # Check Point/Fortinet rule audit
│   ├── Security-Baseline.ps1        # Windows security baseline check
│   └── Port-Scanner.ps1             # Network port scanning
└── 📁 Backup/
    ├── Veeam-Job-Monitor.ps1        # Veeam backup job monitoring
    └── Backup-Verification.ps1       # Verify backup integrity
```

## 🚀 Quick Start

### Prerequisites

- Windows PowerShell 5.0 or higher
- Active Directory PowerShell Module (for AD scripts)
- VMware PowerCLI (for VMware scripts)
- Exchange Online PowerShell Module (for O365 scripts)
- Appropriate administrative privileges

### Installation

1. Clone the repository:
```powershell
git clone https://github.com/infrawisetech/IT-Admin-Toolkit.git
```

2. Import the required modules:
```powershell
Import-Module ActiveDirectory
Import-Module VMware.PowerCLI
Import-Module ExchangeOnlineManagement
```

3. Navigate to the desired script:
```powershell
cd IT-Admin-Toolkit\ActiveDirectory
```

4. Run with appropriate parameters:
```powershell
.\AD-User-Report.ps1 -ExportPath "C:\Reports" -DaysInactive 30
```

## 📖 Script Documentation

### AD-User-Report.ps1
Generates comprehensive Active Directory user reports with multiple export formats.

**Features:**
- HTML report with modern, responsive design
- CSV export for Excel analysis
- Inactive user detection
- Password expiration tracking
- Locked account identification
- Email report capability

**Usage:**
```powershell
.\AD-User-Report.ps1 -ExportPath "C:\Reports" -DaysInactive 30 -EmailReport $true
```

**Parameters:**
- `-ExportPath`: Directory for report files (default: C:\AD-Reports)
- `-DaysInactive`: Days threshold for inactive users (default: 30)
- `-EmailReport`: Send report via email (default: $false)

### Disk-Space-Monitor.ps1
Monitors disk space across multiple servers and sends alerts.

**Features:**
- Real-time disk usage monitoring
- Automatic cleanup suggestions
- Email alerts for critical thresholds
- Historical tracking

**Usage:**
```powershell
.\Disk-Space-Monitor.ps1 -Servers "SERVER1","SERVER2" -ThresholdPercent 85
```

## 🔧 Configuration

Most scripts support configuration through parameters or configuration files. Check individual script headers for detailed parameter documentation.

### Email Configuration
For scripts with email capability, configure SMTP settings:
```powershell
$SmtpServer = "smtp.company.local"
$EmailFrom = "it-automation@aykutyildiz.com"
$EmailTo = "it-team@aykutyildiz.comr"
```

### Logging
All scripts include comprehensive logging:
- Default log path: `C:\Logs\IT-Admin-Toolkit\`
- Log levels: Info, Warning, Error, Success
- Automatic log rotation after 30 days

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📊 Script Performance

| Script | Average Runtime | Objects Processed | Environment |
|--------|----------------|-------------------|-------------|
| AD-User-Report.ps1 | 45 seconds | 1000+ users | Enterprise AD |
| Disk-Space-Monitor.ps1 | 12 seconds | 50 servers | VMware vSphere |
| VM-Bulk-Deploy.ps1 | 5 minutes | 10 VMs | ESXi 7.0 |
| Backup-Verification.ps1 | 3 minutes | 20 backup jobs | Veeam B&R 11 |

## 🛡️ Security Considerations

- All scripts follow principle of least privilege
- Sensitive data is never logged in plain text
- Credentials are handled using SecureString
- Audit logging for all administrative actions
- Tested in defense industry compliance environment

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Developed for Sarsilmaz Silah Sanayi IT infrastructure
- Tested in production environment with 1000+ users
- Special thanks to the IT team for testing and feedback

## 📧 Contact

**Aykut Yıldız** - Chief Information Technology Officer

- LinkedIn: [linkedin.com/in/aykutyildiz](https://www.linkedin.com/in/aykut-yildiz-752891256/)
- Email: aykut@aykutyildiz.com
- GitHub: [@infrawisetech](https://github.com/infrawisetech)

## 🌟 Show Your Support

If you find these scripts helpful, please consider giving a ⭐️ on GitHub!

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/infrawisetech">Aykut Yıldız</a> for the System Admin Community
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Defense%20Industry-IT%20Excellence-red.svg">
  <img src="https://img.shields.io/badge/Enterprise-Ready-green.svg">
  <img src="https://img.shields.io/badge/Production-Tested-blue.svg">
</p>
