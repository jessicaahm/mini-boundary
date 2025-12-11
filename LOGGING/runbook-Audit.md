# Vault Audit Log Analysis

Pre-requisite:

- Enable Audit Logs in Vault: [Example](https://www.hashicorp.com/en/blog/streaming-hcp-vault-audit-logs-to-amazon-cloudwatch-for-secure-real-time-visibility)

Action Items:
- Identify your priorities from Low, Medium, High, Critical
- Identify new areas of concerns


Sample IOC mapped to MITRE

| Vault Event | MITRE Tactic | MITRE Technique |
|-------------|--------------|-----------------|
| **Failed authentication** | Credential Access | T1110 - Brute Force |
| **Root token usage (hcp-root)** | Privilege Escalation | T1078 - Valid Accounts |
| **Policy change to gain sudo** | T1548 | Abuse Elevation Control | 
| **Policy modification** | Persistence | T1098 - Account Manipulation |
| **Audit device disabled** | Defense Evasion | T1562 - Impair Defenses |
| **Secrets enumeration** | Discovery | T1087 - Account Discovery |
| **Secrets read from unusual IP** | Exfiltration | T1041 - Exfiltration over C2 Channel |
| **Auth method changes (Enable/Disable)** | Persistence | T1136 - Create Account |
| After-hours access | Initial Access | T1078 - Valid Accounts |

## Sample Queries

```sh
# If a specific source_ip hit a high failed_attempts <threshold> across multiple vault_path, this could be an IOC: enumeration attack/credential stuffing
# If a specfic source_ip may hit a low failed_attempts <thrsohold> but accross multiple vault_path, this could be IOC: Reconnaissance
# If the duration is short and many login attempts (Could be bot): Not identified by this queries

fields @timestamp, @message
| filter @message like /error/ or @message like /"allowed":false/
| parse @message '"remote_address":"*"' as source_ip
| parse @message '"display_name":"*"' as user
| parse @message '"path":"*"' as vault_path
| stats count(*) as failed_attempts by source_ip, vault_path
| sort @failed_attempts desc
```

```sh
# Identify any IP that hit very high authentication failure
fields @timestamp, @message
| filter @message like /error/ or @message like /"allowed":false/
| parse @message '"remote_address":"*"' as source_ip
| stats count(*) as failed_attempts by source_ip, bin(5m)
| sort @timestamp asc
```

```sh
# Show IP not in Whitelist

fields @timestamp, @message
| parse @message '"remote_address":"*"' as source_ip
| parse @message '"display_name":"*"' as user
| parse @message '"path":"*"' as vault_path
| parse @message '"operation":"*"' as operation
| parse @message '"mount_type":"*"' as mount_type

# Exclude known good IPs (whitelist)
| filter source_ip not in [
    "10.0.1.10",
    "10.0.1.11",
    "10.0.1.12",
    "172.16.0.100"
]
| sort access_count desc
```