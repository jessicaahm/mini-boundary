# PowerShell Script to Test Active Directory Connection
# Run this script AFTER the server has rebooted and AD is fully installed

#Requires -RunAsAdministrator

# Function to log messages
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Testing Active Directory Connection..."

# Get domain information
try {
    $Domain = Get-ADDomain
    $DomainController = Get-ADDomainController

    Write-Log ""
    Write-Log "=========================================="
    Write-Log "Active Directory Domain Information"
    Write-Log "=========================================="
    Write-Log "Domain Name: $($Domain.DNSRoot)"
    Write-Log "Domain NetBIOS: $($Domain.NetBIOSName)"
    Write-Log "Domain DN: $($Domain.DistinguishedName)"
    Write-Log "Forest: $($Domain.Forest)"
    Write-Log ""
    Write-Log "Domain Controller Information"
    Write-Log "=========================================="
    Write-Log "DC Name: $($DomainController.Name)"
    Write-Log "DC Hostname: $($DomainController.HostName)"
    Write-Log "DC IP Address: $($DomainController.IPv4Address)"
    Write-Log "LDAP Port: 389"
    Write-Log "LDAPS Port: 636"
    Write-Log "Global Catalog Port: 3268"
    Write-Log "=========================================="

    # Build connection strings
    $ServerIP = $DomainController.IPv4Address
    $DomainDN = $Domain.DistinguishedName

    Write-Log ""
    Write-Log "Connection Strings"
    Write-Log "=========================================="
    Write-Log "LDAP URI: ldap://$ServerIP:389"
    Write-Log "LDAPS URI: ldaps://$ServerIP:636"
    Write-Log "Base DN: $DomainDN"
    Write-Log "Admin Bind DN: CN=Administrator,CN=Users,$DomainDN"
    Write-Log "=========================================="

} catch {
    Write-Log "ERROR: Failed to get domain information - $_"
    exit 1
}

# Test LDAP connection
Write-Log ""
Write-Log "Testing LDAP Connection..."
try {
    $LDAPPath = "LDAP://$($DomainController.IPv4Address)"
    $DirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry($LDAPPath)

    if ($DirectoryEntry.Name) {
        Write-Log "SUCCESS: LDAP connection established"
        Write-Log "  Root DSE: $($DirectoryEntry.Name)"
        Write-Log "  Path: $LDAPPath"
    } else {
        Write-Log "WARNING: LDAP connection established but no data returned"
    }

    $DirectoryEntry.Close()
} catch {
    Write-Log "ERROR: LDAP connection failed - $_"
}

# Test LDAP Search
Write-Log ""
Write-Log "Testing LDAP Search for Users..."
try {
    $Searcher = New-Object System.DirectoryServices.DirectorySearcher
    $Searcher.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($Domain.DistinguishedName)")
    $Searcher.Filter = "(objectClass=user)"
    $Searcher.PageSize = 10

    $Results = $Searcher.FindAll()
    Write-Log "SUCCESS: Found $($Results.Count) user objects"

    if ($Results.Count -gt 0) {
        Write-Log "Sample users:"
        $Results | Select-Object -First 5 | ForEach-Object {
            Write-Log "  - $($_.Properties['samaccountname'])"
        }
    }

} catch {
    Write-Log "ERROR: LDAP search failed - $_"
}

# Test DNS resolution
Write-Log ""
Write-Log "Testing DNS Resolution..."
try {
    $DnsResult = Resolve-DnsName -Name $Domain.DNSRoot -Type A -ErrorAction Stop
    Write-Log "SUCCESS: DNS resolution working"
    Write-Log "  Domain: $($Domain.DNSRoot)"
    Write-Log "  Resolved to: $($DnsResult.IPAddress -join ', ')"
} catch {
    Write-Log "WARNING: DNS resolution failed - $_"
}

# Summary
Write-Log ""
Write-Log "=========================================="
Write-Log "Connection Test Summary"
Write-Log "=========================================="
Write-Log "Use these connection details for Boundary or other LDAP clients:"
Write-Log ""
Write-Log "LDAP URL: ldap://$($DomainController.IPv4Address):389"
Write-Log "Bind DN: CN=Administrator,CN=Users,$($Domain.DistinguishedName)"
Write-Log "Bind Password: <Your Administrator Password>"
Write-Log "User Search Base: CN=Users,$($Domain.DistinguishedName)"
Write-Log "User Search Filter: (objectClass=user)"
Write-Log ""
Write-Log "For Boundary LDAP Auth Method:"
Write-Log "  URLs: ldap://$($DomainController.IPv4Address)"
Write-Log "  User DN: CN=Users,$($Domain.DistinguishedName)"
Write-Log "  User Attr: sAMAccountName"
Write-Log "  Group DN: CN=Users,$($Domain.DistinguishedName)"
Write-Log "=========================================="

Write-Log ""
Write-Log "Test completed successfully!"