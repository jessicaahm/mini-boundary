# PowerShell Script to Install and Configure Active Directory on AWS EC2 Windows Server 2025

# Requires Administrator privileges
#Requires -RunAsAdministrator

# Function to log messages
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting Active Directory installation on AWS EC2 Windows Server 2025"

# Step 1: Install AD DS Role and Management Tools
Write-Log "Installing Active Directory Domain Services role..."
# try {

#     Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
#     Write-Log "AD DS role installed successfully"
# } catch {
#     Write-Log "ERROR: Failed to install AD DS role - $_"
#     exit 1
# }

# Step 2: Configure AD DS (Promote to Domain Controller)
Write-Log "Configuring Active Directory Domain Services..."

# Get server information
$ServerIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"}).IPAddress | Select-Object -First 1
$ServerHostname = $env:COMPUTERNAME

# Define domain parameters
$DomainName = "lab.com"
$DomainNetBIOSName = "LAB"
$SafeModePassword = ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force

Write-Log "Domain Name: $DomainName"
Write-Log "NetBIOS Name: $DomainNetBIOSName"
Write-Log "Server IP: $ServerIP"
Write-Log "Server Hostname: $ServerHostname"

# Promote server to Domain Controller

try {
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $DomainNetBIOSName `
        -SafeModeAdministratorPassword $SafeModePassword `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -NoRebootOnCompletion:$false `
        -Force:$true

    Write-Log "Domain Controller promotion initiated. Server will reboot..."
} catch {
    Write-Log "ERROR: Failed to promote to Domain Controller - $_"
    exit 1
}

# PS C:\Users\Administrator\Desktop> Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" | Select-Object LDAPServerIntegrity, LdapEnforceChannelBinding

# ldapserverintegrity LdapEnforceChannelBinding
# ------------------- -------------------------
#                   0                         0


# Step 3: create a new user for connection to ldap/ad
New-ADUser -Name "vault" `
    -GivenName "vault" `
    -Surname "vault" `
    -SamAccountName "vault" `
    -UserPrincipalName "vault@lab.com" `
    -Path "CN=Users,DC=lab,DC=com" `
    -AccountPassword (ConvertTo-SecureString "P@ssw0rd123!" -AsPlainText -Force) `
    -Enabled $true `
    -PasswordNeverExpires $true `
    -ChangePasswordAtLogon $false

# Add to Domain Admins (full admin rights)
Add-ADGroupMember -Identity "Domain Admins" -Members "vault"

 Verify user was created
Get-ADUser -Identity $Username
Get-ADGroupMember -Identity "Domain Admins" | Where-Object {$_.SamAccountName -eq $Username}
#Get-ADGroupMember -Identity "Domain Admins" | Where-Object {$_.SamAccountName -eq "vault"}
# Note: Server will automatically reboot after promotion
Write-Log "Domain Controller promotion initiated. Server will reboot..."

# Display connection information
Write-Log ""
Write-Log "=========================================="
Write-Log "Active Directory Connection Information"
Write-Log "=========================================="
Write-Log "LDAP Connection String: ldap://$ServerIP"
Write-Log "LDAPS Connection String: ldaps://$ServerIP:636"
Write-Log "Domain Controller: $ServerHostname.$DomainName"
Write-Log "Domain FQDN: $DomainName"
Write-Log "Domain NetBIOS: $DomainNetBIOSName"
Write-Log "LDAP Base DN: DC=$($DomainName.Replace('.', ',DC='))"
Write-Log ""
Write-Log "Example LDAP Bind:"
Write-Log "  Server: ldap://$ServerIP:389"
Write-Log "  Bind DN: CN=Administrator,CN=Users,DC=$($DomainName.Replace('.', ',DC='))"
Write-Log "  Base DN: DC=$($DomainName.Replace('.', ',DC='))"
Write-Log "=========================================="

# Save connection info to file for reference after reboot
$ConnectionInfo = @"
========================================
Active Directory Connection Information
========================================
LDAP Connection String: ldap://$ServerIP
LDAPS Connection String: ldaps://$ServerIP:636
Domain Controller: $ServerHostname.$DomainName
Domain FQDN: $DomainName
Domain NetBIOS: $DomainNetBIOSName
LDAP Base DN: DC=$($DomainName.Replace('.', ',DC='))

Example LDAP Bind:
  Server: ldap://$ServerIP:389
  Bind DN: CN=Administrator,CN=Users,DC=$($DomainName.Replace('.', ',DC='))
  Base DN: DC=$($DomainName.Replace('.', ',DC='))
========================================
"@

$ConnectionInfo | Out-File -FilePath "C:\AD-Connection-Info.txt" -Encoding UTF8
Write-Log "Connection information saved to C:\AD-Connection-Info.txt"

Write-Log "Script completed. Server will reboot to complete AD DS installation."
