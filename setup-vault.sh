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
export LDAP_BIND_PASSWORD=""

echo "Testing LDAP connection first..."
# Method 1: Append the certificate to the CA bundle --> Get the self-sign cert from AD first
# docker exec vault sh -c 'cat /usr/local/share/ca-certificates/ad-cert.crt >> /etc/ssl/certs/ca-certificates.crt'

# # Verify it was added
# docker exec vault tail -20 /etc/ssl/certs/ca-certificates.crt

# # Restart Vault
# docker restart vault

# Verify LDAP SEARCH work
LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://13.222.94.228:636 -D "CN=Administrator,CN=Users,DC=example,DC=local" -w "*KMN0@nzh2B.RMNNY*Oa&9AzV?8hCX*M" -b "DC=example,DC=local" "(objectClass=user)" cn

LDAPTLS_REQCERT=never ldapsearch -x -H ldaps://13.222.94.228:636 \
  -D "CN=Administrator,CN=Users,DC=example,DC=local" \
  -w "*KMN0@nzh2B.RMNNY*Oa&9AzV?8hCX*M" \
  -b "DC=example,DC=local" \
  "(objectClass=organizationalUnit)" dn
setupldapsecretengine(){
    echo "Logging into Vault..."
    vault login myroot

    echo "Enabling LDAP secrets engine..."
    vault secrets enable ldap

    echo "Configuring LDAP secrets engine for Active Directory..."
    vault write ldap/config \
        binddn="$LDAP_BIND_DN" \
        bindpass="$LDAP_BIND_PASSWORD" \
        url="$LDAP_URL" \
        schema=ad \
        insecure_tls=true \
        userdn="CN=Users,DC=example,DC=local"

    echo "LDAP secrets engine configured successfully!"

    echo ""
    echo "Creating dynamic role for read-only users..."

    # Create LDIF file for user creation (simpler approach)
    cat > /tmp/creation.ldif <<'EOF'
dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: add
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: user
cn: {{.Username}}
sAMAccountName: {{.Username}}
userPrincipalName: {{.Username}}@example.local
unicodePwd:: {{printf "\"%s\"" .Password | utf16le | base64}}
userAccountControl: 66048
accountExpires: 0
EOF

    # Create LDIF file for rollback (disable account instead of delete)
# Create LDIF file for rollback (disable account instead of delete) - FIXED
cat > /tmp/rollback.ldif <<'EOF'
dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: modify
replace: userAccountControl
userAccountControl: 514
-
EOF
    # Create LDIF file for user deletion
    cat > /tmp/deletion.ldif <<'EOF'
dn: CN={{.Username}},CN=Users,DC=example,DC=local
changetype: delete
EOF

    # Copy LDIF files to Vault container
    docker cp /tmp/creation.ldif vault:/tmp/creation.ldif
    docker cp /tmp/rollback.ldif vault:/tmp/rollback.ldif
    docker cp /tmp/deletion.ldif vault:/tmp/deletion.ldif

    # Create the dynamic role
    vault write ldap/role/readonly \
        creation_ldif=@/tmp/creation.ldif \
        deletion_ldif=@/tmp/deletion.ldif \
        rollback_ldif=@/tmp/rollback.ldif \
        default_ttl=1h \
        max_ttl=24h

    # Clean up temp files
    rm -f /tmp/creation.ldif /tmp/deletion.ldif

    echo ""
    echo "Dynamic secrets engine configured!"
    echo ""
    echo "Test dynamic credential generation:"
    echo "  vault read ldap/creds/readonly"
}

setupldapsecretengine

