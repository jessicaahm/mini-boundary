#!/bin/bash

# Vault environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=myroot

vault() {
    docker exec -e VAULT_ADDR=http://127.0.0.1:8200 -e VAULT_TOKEN=myroot vault vault "$@"
}

# LDAP Variables - Using LDAPS due to Windows Server 2025 security requirements
export LDAP_URL=ldaps://13.222.94.228:636
export LDAP_BIND_DN="CN=Administrator,CN=Users,DC=example,DC=local"
export LDAP_BIND_PASSWORD="*KMN0@nzh2B.RMNNY*Oa&9AzV?8hCX*M"

echo "Testing LDAP connection first..."
# Method 1: Append the certificate to the CA bundle --> Get the self-sign cert from AD first
docker exec vault sh -c 'cat /usr/local/share/ca-certificates/ad-cert.crt >> /etc/ssl/certs/ca-certificates.crt'

# Verify it was added
docker exec vault tail -20 /etc/ssl/certs/ca-certificates.crt

# Restart Vault
docker restart vault

# Verify LDAP SEARCH work
ldapsearch -x -H ldaps://13.222.94.228:636 -D "CN=Administrator,CN=Users,DC=example,DC=local" -w "*KMN0@nzh2B.RMNNY*Oa&9AzV?8hCX*M" -b "DC=example,DC=local" "(objectClass=user)" cn

setupldapsecretengine(){
    echo "Logging into Vault..."
    vault login myroot

    echo "Enabling LDAP secrets engine..."
    vault secrets enable ldap

    echo "Configuring LDAP secrets engine..."
    vault write ldap/config \
        binddn="$LDAP_BIND_DN" \
        bindpass="$LDAP_BIND_PASSWORD" \
        url="$LDAP_URL"
        schema=ad

    echo "LDAP secrets engine configured successfully!"
}
setupldapsecretengine

